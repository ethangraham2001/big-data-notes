# 03 Cloud Storage

SQL doesn't scale. This becomes a problem when our dataset becomes huge. Some
relational constraints make sense on clusters, but we will have to relax some
others, namely consistency constraints which we relax partially or fully.
Moreover, in NoSQL, we oftel also relax domain integrity constraints as we will
allow for nested and heterogeneous data! We call this data denormalization.

## CAP Theorem

We can pick two of the three from

- _(atomic, eventual) consistency_
- _availability_
- _partition tolerance_: system continues to function even if the network
linking its machines is occasionally partitioned.

## DBMS vs Data Lakes

We distinguish between systems that require data to be imported into the 
database _(ETL, extract-transform-load)_ which is required by RDBMS. On the 
other hand, we can just store the data on some FS and query it in-place - this
is called a data lake.

Data lakes are slower, but users can query without the effort of ETLing their 
data.

## Local storage

Normally uses 4kB block sizes - we never R/W a bit individually - this balances
throughput and latency.

## Distributed storage

Local storage can support up to millions of files, but cannot reach support
billions, for instance. In order to scale this, the approach for object storage
is

- throw away hierarchy
- make metadata flexible _(no schema)_
- use a simple / trivial data model _(just use an identifier, don't expose
blocks to user)_
- Use a large number of cheap machines

## Object stores

Blobs, despite being built atop a flat key-value model, typically emulate a
file hierarchy by allowing `/` chars in keys, interpreting these as virtual
paths. As far as the storage layer is concerned, `/` chars are just like any
other character.

Object stores are popular as data lakes.

### Amazon S3

Simple storage service.

Buckets identified with bucket ID, each object in a bucket identified with an
object ID. Object is just a synonym for file - we prefer using the term object
because it isn't stored in a hierarchical file system.

Objects are limited to at-most 5TB, and is uploaded as chunks that are at-most
5GB _(large objects uploaded as multiple chunks)_.

### Azure blob storage

Very similar to S3, but

- Architecture is publicly documented
- Objects are defined with three, rather than two IDs - account ID, container
ID _(called partition in scientific papers)_ and a blob ID.
- Exposes more information to users, e.g. that objects are divided into several
blocks. S3 frontends tends to hide this.
- Differentiate between block blobs and append blobs _(logging)_ and page blobs
_(storing and accessing memory of VMs)_.
- Maximum sizes are different

## REST API

**REST:** representational state transfer.

A client and server communicating _(over HTTP)_ interact in terms of _methods_
applied to _resources_.

A resource is indentified by _URI_ (uniform resource identifier) like

```
http://www.example.com/api/collection/foobar?id=foobar#head
```

Where

- `http` is the scheme
- `//www.example.com` is the authority
- `/api/collection/foobar` is the path
- `?id=foobar` is the query
- `#head` is the fragment

We define the following methods

- `GET` (no body): returns a representation of the resource in some format
- `PUT`: creates or updates a resource from a representation of a newer version
- `DELETE`: deletes a resource
- `POST`: blank-check, acts on a resource in any way that the datastore sees
fit. For example, create a new resource.

An Amazon S3 bucket URI may look like

```
http://bucket.s3.amazonaws.com/object-name
```

## Key-value stores

Lower latency than object stores, and support a basic `GET/PUT/DELETE` API.
Think Amazon dynamo.

Normally guarantees eventual consistency as opposed to atomic consistency.

## Amazon Dynamo

Based on the chord protocol which is a DHT - highly scalable, self-organizing,
and robust against failure. However, no support provided to range queries or
data integrity which is in turn pushed up to the user.

### Incremental stability

New nodes can join the system at any time, and nodes can leave at any time _(
whether that be because of a crash, or if they leave gracefully)_.

### Symmetry

No node is special in any way.

### Decentralization

No central node that orchestrates the others.

### Heterogeneity

Nodes may differ in CPU power, memory capacity, etc...

### Chord protocol

Nodes are in a hash-ring _(p2p)_. Logical keys are hashed, and this hash is 
called the ID. In Dynamo, this is 128-bits.

All nodes get a random position on the hash ring.

We can use virtual nodes and employ the same mechanism for better distribution
of data across the physical nodes which also accouts for machine heterogeneity.

### Vector clocks

Allows for reconciliation after network partitions have resolved. This is 
pushed up to the client _(in Dynamo we assume the client to knows how to 
reconcile)_.

To determine a conflict, and which key the conflict is associated to a 
conflict, we use vector clocks. We can create a partial ordering of these 
vector clocks.

```
{ A: 2, C: 1 } <= { A: 3, B: 1, C: 1 }
```

We don't necessarily have a maximum for a partial ordering, but we may have
several maxima. If we have a unique maximum, then there is no conflict. 
Reconciliation happens when there are several maxima.

One maximum implies that in the DHT, there is only one value associated to the
key, and thus there are no conflicting updates.

## Network partitions in general

Above, we introduced the CAP theorem _(which is more of a conjecture because
it isn't formally proven)_. We now analyze how a DHT behaves in the presense
of network partitions.

- **CA** the system crashes. If we require strong consistency and availability,
then we cannot function in the presence of a network partition
- **CP** we become unavailable temporarily until the partition is resolved. If
there is a network partition and we tolerate it while providing strong 
consistency, then we must wait for all nodes to become reachable before serving
read/write reqs.
- **AP** we downgrade our consistency guarantees. This is what _most_ DHT
based systems, including Dynamo, choose to do. In Dynamo's case, it downgrades
to eventual consistency.
