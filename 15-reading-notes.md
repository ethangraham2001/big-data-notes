# Reading Notes

There are several documents to read for the course. As there is already a 
summary for these on the [VIS website](vis.ethz.ch), I am just going to state
definitions and some high-level observations to condense that down a little.

## Windows Azure Storage _(WAS)_

**Keywords:** object storage, data partitioning

**Account name** specifies cluster holding data. **Partition name** locates the
data inside of a cluster _(think sharding)_. **Object name** used to access
individual pieces of data.

```
http(s)://[AccountName].<service>.core.windows.net/[PartitionName]/[ObjectName]
```

**Storage stamp** is a cluster of $N$ racks of storage. Independent fault 
domain, which we want to keep at 70% utilization. We replicate inside and 
across stamps. 

- Intra-stamp replication is synchronous, and handled by the stream layer. This
    is for fault-tolerance.
- Inter-stamp replication is async, and handled by the partition layer. This is
    geo-redundancy

**Location service** manages all stamps, account names, assignment of accounts
across stamps.

We employ **stream layer** for storing data on disks _(durability, 
replication across stamp)_. Files are called streams, which are ordered lists 
of extents. **Partition layer** manges address, caching, and consistency of
data. Provide higher level abstraction _(Blob)_. **Front-end layer** is a set
of stateless services for access control and caching.

Writes are append-only, and are atomic. Only the last extend of a stream can be
appended to, and our blocks are the minimum unit for storage. To the partition
layer, this presents as a big file.

## Amazon Dynamo KVS

**Keywords:** key-value store, consistent hashing, availability, SLA, 
decentralized architecture

Dynamo is a highly available KVS used internally by Amazon, providing a simple
`GET/PUT` API for blobs with a size less than 1MB. No authentication/access
control as it is intended to be used internally in a non-hostile environment.

Dynamo abides by a strict SLA that constrains the $99.9^{th}$ percentile tail
latency.

The goals are **incremental scalability** _(add more storage nodes)_, 
**symmetry** _(no primary node(s))_, **decentralization**, and **support of 
heterogeneous infrastructure**.

Partitioning relies on consistent hashing, leveraging virtual nodes for a fair 
distribution of the key-space across physical nodes. We use a replication 
factor of $N$, with a single virtual node holding redundant copies of the data
handled by the next $N$ nodes counter-clockwise to it _(i.e. a section of the
virtual key-space covers $N$ virtual nodes)_.

A `get() / put()` query is answered by a coordinator node, typically the first
in the preference list for a piece of data, but could be different due to load
balancing. Consistency is maintained with a protocol mimicking quorums. Every 
read needs to be answered by $R$ nodes, every write request by $W$ nodes. 

On `put()`, the coordinator will generate a vector clock, writing to it 
locally. It propagates the data and vector clock through to the $N$ 
highest-ranked reachable nodes, and if $W$ respond, we deem the `put()` 
successful.

We choose $R + W > N$ as this guarantees that the set of nodes that answer a
read or write request will overlap. If we choose $W = 1$, then the system will
still accept write requests so long as at least one node is still active. We
can tailor to our use case.

## Hadoop Distributed File System

**keywords:** Replication, centralized architecture

This section was covered pretty extensively in the course, so here I will focus
on highlighting the details that weren't necessarily discussed in-depth during
the lectures.

All communication between nodes in the system happen over TCP-based protocols.

- **Image:** inode data, list of blocks in a file. In-memory.
- **Checkpoint:** persistent record of an image.
- **Journal:** modification log of the image stored on the NameNode disk.

Every block replicat on a DataNode is stored in two files on the local file 
system - the first containing the data, the second containing the block 
metadata _(checksums, generation stamp)_.

Heartbeats are sent every 3 seconds by default, and if the NameNode doesn't 
receive a heartbeat from a DataNode in 10 minutes, it is considered 
out-of-service and we consider the replicas unavailable. The content of a 
heartbeat contains total storage capacity, fraction of used storgae, number of
data transfers currently in progress.

Default replication factor is 3.

**CheckpointNode:** periodically combine the existing checkpoint and journal to
produce a new checkpoint, returning it back to the NameNode. This takes that
burden off of the NameNode which is important in handling requests.

**BackupNode:** next to period checkpoints, and maintains up-to-date image of
file-system namespace. The NameNode delegates the responsibility of 
checkpointing onto the BackupNode so that it only has to keep everything in
memory.

For writing, a client receives a lease from the NameNode, which is periodically
renewed via heartbeat. A client creates a file, and writes to it. After 
closing, the file can only be appended to _(cannot modify existing content)_.

Leases have a hard and soft limit.

- soft limit: another client can kick the writer.
- hard limit: DataNode revokes the lease of a writer.

Reading is never blocked by a lease. Block reading is done based on distance
from client in the network topology _(we have a list, if any block reads fail,
we move onto another block replica on a different node)_.

A block is said **over-replicated** if it exceeds the replication factor, and
the NameNode decides which copy to remove, trying to minimize the number of 
racks that a block lives on, and prefers removing from a DataNode with low free
space. A block is **under-replicated** when the number of replicas is less than
the replication factor. Under replicated blocks are placed in a replica queue,
where less replicas mean higher priority. We replicate using the same rule
described just above.

Block placement does not take into account disk utilization. We say that disk
usage is balanced if the disk usage is close to the mean utilization of the 
cluster minus some defined threshold.

We decomission a DataNode by marking it. It can still serve read requests, but
writes are blocked and the data is replicated onto other DataNodes.

Three time replication is robust against data loss caused by uncorrelated node
failures, however no recovery can be guaranteed in the case of correlated node
failures. The **block scanner** regularly scans blocks for corrupted data which
it checks via the checksums stored as metadata.

Future work states improvement of the BackupNode _(ability to take over from 
the NameNode entirely on failure)_ and improve scalability of the NameNode via
the introduction of separate namespaces on different NameNodes.

## Hadoop: The Definitive Guide (Chapter 3)

This just summarizes some concepts we have already seen.

HDFS designed for very large files. Write once, read many times. Uses commodity
hardware. Not designed for low-latency access, lots of small files, multiple
writers, or arbitrary file modifications.

Files are chunked into `BLOCK_SIZE`, smaller files do not occupy the whole 
block _(only the required portion)_.

DataNodes cache frequently-used in memory, and we normally only cache a given
block on a single DataNode.

HDFS federation allows for distinct namespaces on different NameNodes, which
was proposed as future work in the previous paper on HDFS described above.

Restarting a NameNode can take ~30 minutes. To improve active-standby, extra
NameNodes are introduced which can immediately take over on the failure of the
primary NameNode. This requires a highly-available shared storage medium 
between NameNodes for the EditLog, allowing the standby NameNodes to sync up
quickly.

HDFS can interact with various file systems, as well as object stores. HDFS is
implemented in Java, meaning these interactions are mediated through the Java
API.

## Bigtable: A Distributed Storage System for Structured Data

BT does not provide a full relational model, instead exposing to clients a 
simple data model that support dynamic control over data layout and format, as
well as paramaters that let clients dynamically control whether to serve data
from disk or memory. We can optimize for latency-sensitive user services or
throughput-oriented batch processing.

Bigtable is a sparse, distributed, persistent multi-dimensional map. Every cell
is an uninterpreted byte array.

**Row** keys are arbitrary strings, and each operation under a given row key is
atomic _(row-level atomicity)_. A **tablet**, which is a range of row keys, is
the unit of distribution and thus load balancing. By choosing row keys which,
in lexicographical order, group simultaneously accessed data together, we
optimize for performance.

**Column families** are how we group columns together, and form the basic unit
of access control. All data stored in a column family is usually of the same 
type. The number of column families should be small, and should seldom change.
We can have an arbitrary number of columns within a column family, and this 
scales dynamically.

**Timestamps** are the mechanism we use for versioning each cell. We sort the
data by timestamp descending so that we can quickly access the most recent
data. Garbage keeps the number of versions in check - it is configurable how
long we keep a version for.

## HBase: The Definitive Guide (Chapters 1, 3)

HBase persists data in a columnar format, but this is the only real similarity
with RDBMS. HBase excels at providing key-based access to a specific cell of
data, or a sequential range of cells.

HBase is built for sparsity - while empty values would require a `null` in 
RDBMS, we don't need to store anything for absent columns in HBase.

Like Bigtable, row-level access is atomic. We provide no atomicity guarantees
for writes spanning over multiple rows.

Contiguous rows are stored in regions, which are stored on **RegionServers**.
Each region exists on a single RegionServer, but multiple regions may exist on
a given RegionServer, ideally 10 to 1000 regions per server, with each of them
around 1GB to 2GB in size. If a region becomes too large or too small, it
is split/fused to better balance the load between servers.

Data is persisted in HFiles, which are order immutable maps from keys to 
values. These are typically stored in HDFS, with a RegionServer running as a
process on the same machine as a DataNode.

When the memstore reaches some macimum capacity, we flush to an HFile on disk.
To assign specific regions to specific RegionServers, the head server uses
Apache Zookeeper.

## Dremel: Interactive Analysis of Web-Scale Datasets

Dremel is an interactive ad hoc query system for read-only nested data. It is
capable of running trillion-row queries in seconds, and scales to thousands of
CPUs and petabytes of data.

The data model is based on strongly typed nested records _(protocol buffers)_.

The goal is store all values of a given field consectively in order to improve
retrieval efficiency. We must also be able to assemble records efficiently for
any given subset of columns.

We store, alongside an attribute, its **repetition level** and **definition 
level**. The repetition-level is the longest common prefix with the attributes
predecessor in the list, and the definition level is how far down the tree we
can go before reaching an attribute - a sub-maximal definition level indicates
a `NULL` value.

Table is sharded as _tablets_ each of which is a horizonal partition of the
data. It also stores the schema and extra metadata.

## MapReduce: Simplified Data Processing on Large Clusters

**Goal:** run highly parallisable computations on many commidity machines.

Since we have already covered the logical model of this to death in the course,
I will focus on highlighting the interesting details that may or may not come
up in an exam.

Input data is partitioned into $M$ splits which are processed in parallel.
The intermediate data is partitioned into $R$ splits using a hash function and
fed to the reducer tasks.

One of the mapper and reducer tasks is called the **master**, and keeps track
of the progress of individual machines. It also propagates the location of the
data of completed jobs to the workers.

MapReduce needs to handle failures gracefully, as there are potentially loads
of machines involved in a given job.

- **Worker failure:** the master pings workers periodically. If a worker 
    connection times out, the progress of the currently handled partition is
    reset and the partition is assigned to a new worker. Other workers are
    notified to read the output data from the new machine instead of the old
    one.
- **Master failure:** The master can write checkpoints to an off-machine 
    storage medium which a new master cna use to resume the old job if the old
    master dies. Otherwise, we can abort and restart the whole job.
- **Semantics in presence of failures:** as long map and reduce operators are
    deterministic, they are idempotent and we can just call them again without
    hassle.

When assigning jobs, the master looks at the location of the data relative to
the nodes in order to reduce overall network usage.

To mitigate stragglers, we can run the same job on multiple machines if a given
machine is known to take particularly long. This prevents a single machine from
slowing the whole job down. This is called **backup tasks** in this case.

If a record is known to cause a crash of the mapper or reducer functions, this
is flagged to the master so that it knows to skip that record.

## HBase: The Definitive Guide (Chapter 7)
