# Distributed File Systems

Previously, we discussed mechanisms that can store huge of large objects - such
as S3 and Azure blob. In this section we will discuss large amount of huge
objects - i.e. we have less objects to store but they are massive. bigger than
the 5TB constraint on object sizes in S3.

## Requirements

- Data can be collected _(for example from sensors and logs)_
- New datasets need to be written back to large-scale storage backends
- Rinse and repeat with more derived large datasets
- Must be resilient to failures _(in a large cluster, thing WILL fail)_: be
able to self-monitor, detect failures, automatically recover

We don't care so much about random access for large network attached datasets.
We optimize mainly for fast sequential reads over the entire datasets, and
append new data efficiently _(particularly important for logging and sensors)_.
we must be able to do this when there is high contention. 

Distributed file systems support both parallelism and batch processing 
natively - thus forming the ideal storage system for Spark and MapReduce.

## HDFS model

### File hierarchy

We use the word file here instead of object, an HDFS file corresponds logically
to an S3 object.

We organize things in a file system - i.e. a tree, instead of a flat key-value
model. We call this the **namespace**.

HDFS files are exposed as a list of **blocks**, similarly to a local FS. This 
is because a 1PB file cannot be stored on local disk, so we have to partition
it in some way - blocks are the granularity at which we do this. Moreover,
this block abstraction is simple enough that we can expose it logically, and
they can easily be shared among machines. **These blocks are typically 64MB
or 128MB** each _(much larger than on local disk)_. This is not at all 
optimized for random access - they are designed to be shipped over the network 
and thus we want to amortize the network overhead. This size is also within the
range of convenience for spreading across machines, allowing for parallel 
access.

So to summarize, all files are stored in blocks of 128MB, with the last of 
these blocks occupying less space _(file sizes are seldom a perfect multiple of 
128MB)_

Blocks are replicated and stored on multiple nodes _(see next section)_. The
number of times this is done is called the _replication factor_ and is
tunable. **There is no primary replica** (no preference lists like Dynamo).

## Physical architecture

HDFS follows a master-slave architecture - i.e. it is centralized. 
Specifically, in HDFS we refer to **NameNodes and DataNodes**. These are 
processes running on the servers that are participating.

### NameNode

Responsible for the system-wide activity of the HDFS cluster. Three things in
particular.

- Responsible for the file namespace, i.e. the hierarchy of directory names and
file names, as well as any access-control information
- Mapping from each file to the list of blocks composing it (64-bit identifier)
- Mapping from each block to the list of DataNodes storing a copy.

Clients connect to the NameNode via the client protocol, and can perform 
metadata operations such as creating or deleting a directory. The NameNode 
responds with the lists of DataNode locations for each block that the file
consists of.

The NameNode exposes the API that is available to the client.

### DataNode

For every block of the file, with the exception of the very last block, there
is no internal fragmentation _(unlike local block storage)_.

DataNodes regularly send heartbeats to the NameNode _(every 3s by default)_ to
let the NameNode know that everything is alright, as well as

- Tell the NameNode that a new block was received and stored successfully
- Tell the NameNode if there is an issue with the local storage - i.e. report
a block as corrupted - so that the NameNode can replicate it elsewhere async

A NameNode never initiates a connection to the DataNode - it only responds to 
heartbeats. If it needs to tell something to a DataNode, it will wait for the
next heartbeat to tell it.

DataNodes can communicate with eachother through replication pipelines - i.e.
when a new HDFS file is created, the client won't send the data to every 
individual DataNode assigned to a block - it just sends it to the first 
DataNode which then starts a replication chain.

The whole 128MB normally isn't sent at once - it is streamed over the network
in 64kB blocks - this is less cumbersome in the event that a packet goes 
missing.

## Functionality

### Reading

- Connect to NameNode, initiate read and request info on the file
- NameNode responds with a list of all blocks, as well as a list of DataNodes
containing a replica of each block _(sorted by increasing distance)_.
- Connect to the DataNodes to download a copy of the blocks, starting with the
closest ones and increasing the distance in the case that one is unavailable.

The downloaded files are typically received as an `InputStream`, which is
encapsulating just a large stream of bytes, allowing us to process a file 
larger than the working memory.

The client can also store the whole multi-block file on its local disk if it
fits.

### Writing

This can either be done from a single large file stored locally, or from a
stream of bits like an `OutputStream`.

- Connect to NameNode expressing intent to create a new file
- NameNode responds with a list of DataNodes to which the content should be
sent. Note that the file is not yet guaranteed to be available for reads, so it
is locked so that nobody else can write to it at the same time.
- Client connects to the first DataNode and instructs it to organize a pipeline
with the other DataNodes provided by the NameNode for this block
- Client receives regular ACKs from the first DataNode that the other bits
have been received.
- When all bits have been ack'd, the client connects to the NameNode once more
in order to move over to the second block.
- Rinse and repeat for each block.
- Once the last block has been written, inform the NameNode that the file is
complte, and asks to release the lock.
- NameNode checks for minimal replication through the DataNode protocol.
- Finally gives an ack to the client.

### Replication strategy

The placement strategy for replicas is based on the knowledge of the physical
setup of the cluster!

Since some nodes are colocated and connected with others over the network, we
have a topology. This is what allows us to define the notion of distance 
between two nodes in the system.

Firstly, an important thing to note is that the client initiating a file write
with the NameNode is likely running on the same physical machine as an HDFS
node _(i.e. on one of the nodes of the HDFS cluster)_.

Bearing this in mind, the first block replica will go by deault to the same
machine that the client is running on _(if possible)_. The second node we write
to is on a different rack than the client is running on. Call this rack B. The
third replica is written to a different DataNode also on rack B. 

Further replicas are written mostly at random but respecting two rules for
resilience

- At most one replica per node
- At most two replicas per rack

### Fault tolerance and availability

The NamdeNode is a single point of failure - if the metadata is lost, then all
the data on the cluster is lost because the blocks have no semantics from the
point of view of the DataNodes.

For this reason, we back the metadata up! We call this a snapshot. We don't
need to backup the `blockID -> DataNode` mapping as we can recover this through
periodic block reports.

We can't do a snapshot at each update, so we also use an edit log which is
persisted - thus on crash we take the snapshot, replay the edit log, and we
have an up-to-date view of the metadata after a crash. We can then trigger 
block reports to rebuild the `blockID -> DataNode` mappings.

The snapshots and edit logs can be stored locally or on NAS. For resilience we
probably want to be backing these up in multiple locations.

Note that replaying the edit log can be very expensive! It can take 30+ minutes
to replay the edit log if it is long. Incremental improvements to this were 
made in subsequent releases of HDFS.

- Periodically merge the edit-log into a larger snapshot _(called checkpoint)_
in a phantom NameNode.
- Configure a phantom NameNode to be able to instantly take over from NameNode
on crash

We call these phantom NameNodes standby NameNodes in current documentation.

Later on, federated NameNodes were introduced - i.e. multiple NameNodes can run
at the same time.

## Using HDFS

- `hdfs dfs <cmd>`
- `hadoop fs <cmd>` _(recommended)_

We can use unix FS commands here.

Paths are encoded in URIs: `hdfs://www.example.com:8021/user/hadoop/file.json`.
