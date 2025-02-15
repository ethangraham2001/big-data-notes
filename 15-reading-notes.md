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

## XML in a Nutshell (Chapter 17)

Here we go over XML schemas - quite a shitstorm. No need for motivation here,
let's just get into the nitty gritty.

- `xsi:schemaLocation` attribute on an elemrn contains a list of namespaces
    used within that element and the URI of the schemas with which to validate
    elements and attributes in those namespaces.
- `xsi:noNamespaceSchemaLocation` attribute contains a URI for the schema used
    to validate elements that are not in any namespace.


### Complex Types

Simple types are the basic atomic building blocks. Complex types are just a 
combination of different types. Think objects in OOP. Only elements can contain
complex types, attributes always have simple types.

### Simple Content

`xs:simpleType` can define new simple data types, which can be referenced by
both element and attribute declarations within the schema.

```xml
<xs:complexType name="contactsType">
    <xs:sequence>
        <xs:element name="phone" minOccurs="0">
            <xs:attribute name="number" type="xs:string"/>
            <xs:attribute name="location" type="addr:locationType"/>
        </xs:element>
    </xs:sequence>
</xs:complexType>

<!-- we define a simple type that is used by an attribute above -->
<xs:simpleType name="locationType">
    <xs:restriction base="xs:string"/>
</xs:simpleType>
```

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

We define the various terms that are used to describe MapReduce.

- **Splits:** the input will be split before being passed to the map task.
    The `InputFormat` class is responsible for doing this. HBase provides tight
    integration with MapReduce, and we can efficiently split an entire HBase
    table.
- **Mapper:** the `Mapper` classes are responsible for processing key-value 
    pairs. There are some pre-defined ones that integrate with HBase, for 
    example `IdentityTableMapper`.
- **Reducer:** reducers receive random keys as input _(shuffled)_.
- **OutputFormat:** Final stage of a MapReduce job persists the data in various
    locations. HBase exposes `TableOutputFormat` class to write a specific
    HBase output table.
- **TableMapReduceUtil:** this is a class that helps set up MapReduce jobs over
    HBase.

Hadoop handled block replication automatically since everything is running on
top of HDFS. Noting that a file will be split up into blocks sitting on HDFS
DataNodes, we can choose to run out map tasks on those same nodes for better
data locality. Because these blocks are replicated, we can even run these map
tasks _(on the same block)_ in several different locations. Since HBase runs
atop HDFS, using MapReduce with HBase provides similar guarantees, albeit more
difficult to reason about given how it is hidden behind a layer of abstraction.

## Apache Hadoop YARN: Yet Another Resource Negotiator

- **ResourceManager:** tracks resource usage and node liveness, enforces
    allocation invariants, arbitrates contention among tenants.
- **ApplicationMaster:** requests resources from the ResourceManager, 
    generates a physical plan, coordinates execution, handles fault tolerance

The ResouceManager runs on a dedicated machine. It will schedule and 
dynamically allocate **containers** to applications to run on a particular 
node, which is leases out with a token. A container is just a logical bundle
of resources, normally expressed in terms of `(RAM, CPU)`.

Each node has a **NodeManager** which exchanges heartbeats with the 
ResourceManager, and is responsible for monitoring resource availability,
fault reporting, container life cycle management.

Jobs are submitted to the ResourceManager - if accepted, and once there are
sufficient resources available, these are scheduled. The ApplicationMaster can
spawn the job on a node inside some container.

Locality preferences are known by the ResourceManager which allows it to
intelligently schedule jobs - for example when we want to schedule a MapReduce
job close to the data. It also maintains a priority queue of jobs, first 
scheduling jobs with a higher priority.

Note that the ApplicationMaster itself is running inside of a container on the
cluster. It should be resilient to failures, as it monitors the life cycle of
a job. We can implement the ApplicationMaster however we like so long as its
communication adheres to the standardized interface that YARN requires.

The ResourceManager is a single point of failure in YARN. It can recover its
state on startup by reading from persistent storage _(checkpoint)_.

If a NodeManager fails, the ResourceManager marks all containers as killed.
This happens when a hearbeat times out. The ApplicationMaster handles the 
actual application-level fault-tolerance.

## Dominant Resource Fairness: Fair Allocation of Multiple Resource Types

**Intuition:** in a multi-resource environment, the allocation of a user should
be determined by the user's dominant share, which is the maximum share of 
something that the user has been allocated. DRF seeks to maximize the minimum
dominant share.

**Example:** if a job requires 10% of the total CPU and 30% of the available
memory, the dominant resource is memory. We treat this job as requiring 30%
of a node. Our scheduling decisions are based on this, where we try to maximize
cluster utilization.

The resource manager fulfills the following properties

- **Sharing incentive:** user should be better off sharing than exlusively 
    using their own partition of the cluster.
- **Strategy-proofness:** user shouldn't benefit from lying about their 
    resource requirements - allocation cannot be improved by lying.
- **Envy-freeness:** A user should not prefer the allocation of another user.
- **Pareto efficiency:** It should not be possible to increase the allocation
    of a user without decreasing the allocation of at least one other user.
- **Single resource fairness:** For a single resource, solution should be to
    reduce max-min fairness
- **Bottleneck fairness:** if there is one resource that is percent-wise 
    demanded most by every user, then the solution should be to reduce to 
    max-min fairness for that resource
- **Population monotonicity:** When a user leaves the system and relenquishes
    their resources, none of the allocations of the remaining users should
    decrease.
- **Resource monotonicity:** if more resources are added to the system, none of
    the allocations of the existing users should decrease.

## Resilient Distributed Datasets

MapReduce lacks abstractions for leveraging distributed memory - the only way 
to reuse data is to persist it in between computations. But data reuse data
is important - want a computation graph, A DAG.

**RDD:** read-only partitioned collection of records that can only be created
through deterministic computation. We call these _transformations_, and we
materialize through _actions_. These are much coarser-grained than DSM which
allows reads / writes to individual memory addresses. This allows for efficient
fault tolerance, and straggler mitigation. 

RDDs are not suited for applications that make asynchronous fine-grained 
updates to shared state. They are for efficent bulk transformations.

The Spark programming interface is all transformations and actions on RDDs.
Workers do the computation - they are long-lived processes that can store
partitions in RAM across operations.

- `partitions()`: return a list of partition objects
- `preferredLocations(p)`: list nodes where partition `p` can be accessed 
    faster due to data locality.
- `dependencies()`: return a list of dependencies
- `iterator(p, parentIters)`: compute the elements of partition `p` given
    iterators for its parent partitions.
- `partitioner()`: return metadata specifiying whether the RDD is hash/range
    partitioned

We define **narrow** and **wide** dependencies. Narrow dependencies are used by
at most one partition of the child RDD, and wide dependencies are such that 
multiple child RDDs may depend on it. Narrow dependencies preserve locality,
and are very efficient to chain together.

Narrow dependencies allow for pipelines execution on one cluster node, and
handling node failures are more efficient as only the lost parent partitions
need to be recomputed which can be done on different nodes. The lineage graph
of a wide dependency may mean that a lost partition requires all of the 
dependencies to be recomputed on a node failure.

## Spark SQL: Relational Data Processing in Spark

The Spark API is functional by design. We provide an interface that mixes
relational and procedural - this is the Spark DataFrame API, and its optimizer
Catalyst.

The **DataFrame API** models a distributed collection of rows with the same
schema. Logically just a relational table, but we do support nesting here.
Operations are _lazy_ like RDDs in general, and only computed when an action is
triggered.

We have a DSL for dataframe operations. User-defined functions can be 
registered in SparkSQL, and are inlined.

The **Catalyst** optimizer, based largely on trees and rules to manipulate
them.

Schema inference is added, as well as integration with ML libraries allowing
us to build ML pipelines.

## MongoDB: The Definitive Guide (Chapters 3, 4 and 5)

This covers some of the syntax that we see in MongoDB. The query API is very
difficult to read, and easy to get wrong.

```javascript
// returns all documents where age == 27
db.users.find({"age" : 27})

// returns all documents where username == joe AND age == 27
db.users.find({"username": "joe", "age": 27})

// returns the user name and email of all documents, omitting the ID which is
// always present by default
db.users.find({}, {"username": 1, "email": 1, "_id": 0})
```

Now we move onto some more complex queries.

```javascript
// searches for elements fitting one out of a list of values
db.users.find({"user_id": { "$in": [ 12345, "joe" ] }})

// searches for elements where ticket_no == 725 OR winner == true
db.raffles.find({"$or": [{"ticket_no": 725}, {"winner": true}]})

// find users not older than 21
db.users.find({ age: { $not: { $gt: 21 } } })

// conditional semantics
db.users.find({"age": { "$gt": 20, "$lt": 30 }})

// we can use regex
db.users.find({"name": "regexStuff"})
```

Querying in arrays works interestingly. When querying them, a result if found
if one element in the array satisfies the condition. If we want all of them
to satisfy the condition, then we must use `$all`.

```javascript
db.food.insert({"_id" : 1, "fruit" : ["apple", "banana", "peach"]})
db.food.insert({"_id" : 2, "fruit" : ["apple", "kumquat", "orange"]})
db.food.insert({"_id" : 3, "fruit" : ["cherry", "banana", "apple"]})

db.food.find({fruit : {$all : ["apple", "banana"]}})
// > {"_id" : 1, "fruit" : ["apple", "banana", "peach"]}
// > {"_id" : 3, "fruit" : ["cherry", "banana", "apple"]
```

When we query without the `$all`, only documents where the array is an exact
match will be returned - including the order.

The `$size` operator can be used to look for arrays of a certain size, and the
`$slice` operator can be used to slice an array.

```javascript
// returns 5 comments starting at index 10
db.posts.find({}, { comments: { $slice: [10, 5] } })

// matches posts that have exactly three comments
db.posts.find({ comments: { $size: 3 } })
```

Querying embedded documents is a little counter-intuitive.

```javascript
// looks for an exact match `name == {"first": "Joe", "last": "Schmoe" }`
db.people.find({"name" : {"first" : "Joe", "last" : "Schmoe"}})

// looks for any document where first name is "Joe", last name is "Schmoe"
db.people.find({"name.first": "Joe", "name.last": "Schmoe"})
```
