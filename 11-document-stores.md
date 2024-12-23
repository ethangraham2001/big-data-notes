# 11 Document Stores

The problem with what we discussed previously, is that a lot of Big Data 
systems expose a pretty low-level interface. They function as a data lake, and
push a lot of complexity up to the user, and replace ACID with CAP. It doesn't
function as a fully integrated DBMS ike older systems.

There was a movement to bring back some of the nice-to-haves from RDBMS, namely
ACID, query languages, data management. Document stores are part of this 
effort.

## Motivation

Relational data always comes with a schema.

We saw in chapter 7 that we can in fact extend data to break relational
integrity _(optional fields, for example)_ or domain integrity _(union types,
`item` topmost type)_, and atomic integrity _(dataframes)_.

However, in the wild, we can rarely ever guarantee a schema. It would be nice
to be able to form schemas on the fly, discover them, offer query functionality
to find out what kind of value is associated to each key, or even functionality
that directly infers a schema.

We would also like it if we could make trees fit into tables, which is pretty
natural if the data is flat homogeneous. However, tables don't handle 
nestedness or heterogeneity well.

## Document Stores

This provides a native DBMS for semi-structured data, and they scale to
GB or TB of data and typically support millions to billions of records. 
Document stores typically specializes in JSON or XML _(sometimes both)_.

We could, for instance, have a collection that looks like

```json
{
    "foo": 1,
    "bar": [ "foo", "bar" ],
    "foobar" : true,
    "a" : { "foo" : null, "b" : [ 3, 2 ] },
    "b" : 3.14
}
{
    "foo": 1,
    "bar": "foo"
}
{
    "foo": 2,
    "bar": [ "foo", "foobar" ],
    "foobar" : false,
    "a" : { "foo" : "foo", "b" : [ 3, 2 ] },
    "b" : 3.1415
}
...
```

We call the records **documents** here. We want lots of documents that are
relatively small, at around a maximum of 16GB. Some document stores will
enforce a maximum size. **We don't need a collection of documents to have a
schema**, we an just insert random documents with dissimilar structures. 
However, most document stores do provide the ability to add a schema and thus
validate documents.

A schema can be added before documents ***(schema-on-write)*** or while 
processing a collection ***(schema-on-read)***.

Idea: generalize the relational model to nested heterogeneous data while
retaining the ability to enforce a minimum structure via schemas.

Document stores are typically optimized for selection and projection, but don't
do joining particularly well and sometimes it isn't even exposed via their API.
We push that up to the user.

## MongoDB

DBMS typically has an optimized custom data format, and data lakes store files
as they are. How do document stores handle this?

**MongoDB** chooses to store documents as **BSON**, or Binary-JSON, which is
based on a token sequence that efficiently encode the JSON constructs that are
found in a document, reducing the storage footprint.

MongoDB, like other document stores, is based on the CRUD paradigm, and 
supports various client languages via SDKs. We focus on the Mongo Shell, which
is a wrapper around JavaScript.

```javascript
// insert one document
db.scientists.insertOne(
    {
    "Last" : "Einstein",
    "Theory" : "Relativity"
    }
)

// insert multiple documents
db.scientists.insertMany(
    [
        {
            "Last" : "Lovelace",
            "Theory" : "Analytical Engine"
        },
        {
            "Last" : "Einstein",
            "Theory" : "Relativity"
        }
    ]
}
```

MongoDB automatically adds a `_id` field to each inserted document, which is
a 12-byte binary value.

```javascript
// scan a whole collection
db.collection.find()

// selection with one field
db.collection.find({ "Theory" : "Relativity" })

// selection with multiple fields (logical and)
db.collection.find(
    {
        "Theory":"Relativity",
        "Last":"Einstein"
    }
)

// selection with multiple fields (logical or)
db.collection.find(
    {
        "$or" : [
            { "Theory":"Relativity" },
            { "Last":"Einstein" }
        ]
    }
)

// selection with a more complicated predicate (greater than or equal)
db.collection.find(
    {
        "Publications" : { "$gte" : 100 }
    }
)

// projection after a selection
db.scientists.find(
    { "Theory" : "Relativity" },
    { "First" : 1, "Last": 1 }
)

// omit _id, which is always included by default
db.scientists.find(
    { "Theory" : "Relativity" },
    { "First" : 1, "Last" : 1, "_id" : 0 }
)

// project first and last away, keep the rest
db.scientists.find(
    { "Theory" : "Relativity" },
    { "First" : 0, "Last" : 0 }
)

// count
db.scientists.find(
    { "Theory" : "Relativity" }
).count()

// sorting, limits and offsets
db.scientists.find(
    { "Theory" : "Relativity" },
    { "First" : 1, "Last" : 1 }
).sort(
    {
    "First" : 1, // ascending
    "Name" : -1  // descending
    }
).skip(30).limit(10)
```

Note that contrary to intuition, the order of the calls does not matter. This
just creates a query plan by providing parameters in any order.

```javascript
// duplicate elimination
db.scientists.distinct("Theory")

// filter absent fields
db.scientists.find(
    { "Theory" : null }
)
/**
equivalent to:
    SELECT *
    FROM scientists
    WHERE Theory IS NULL
*/

// query for several values with different types
db.collection.find(
{
    "$or" : [
        { "Theory": "Relativity" },
        { "Theory": 42 },
        { "Theory": null }
    ]
}

// alternate syntax for the same thing
db.scientists.find(
    {
        "Theory" : {
            "$in" : [
                "Relativity",
                42,
                null
            ]
        }
    }
)
```

Querying for nestedness is done a little counter-intuitively

```javascript
// will look for EXACT matches "Name": { "First": "Albert" }
db.scientists.find({
    "Name" : {
    "First" : "Albert"
    }
})

// catches all scientists with first name "Albert"
db.scientists.find({
    "Name.First" : "Albert"
})
```

For nested arrays, we filter based on whether an array _contains_ a value or
not - it doesn't look for an exact match.

```javascript
db.scientists.find({
    "Theories" : "Special relativity"
})

// could return
{
    "Name" : "Albert Einstein",
    "Theories" : [
        "Special relativity",
        "General relativity"
    ]
}
```

```javascript
// deletes all documents matching criteria (as it would with find())
db.scientists.deleteMany(
    { "century" : "15" }
)

// only deletes one
db.scientists.deleteOne(
    { "century" : "15" }
)

db.scientists.updateMany(
    { "Last" : "Einstein" },
    { $set : { "Century" : "20" } }
)
```

For more complex queries, MongoDB exposes an aggregation pipeline API.

```javascript
db.scientists.aggregate(
    { $match : { "Century" : 20 },
    { $group : {
        "Year" : "$year",
        "Count" : { "$sum" : 1 }
    }
    },
    { $sort : { "Count" : -1 } },
    { $limit : 5 }
)
```

This is pretty akin to a sequence of Spark transformations.

We note that the API provided here is pretty rich, supporting things that
traditional DBMS and SQL does not cover. However, as states before, no joining
is provided for example. So a lot of burden is still pushed up to the user.

## Architecture

Collections can be sharded in MongoDB. **The shards are determined by one or
more fields**. These shards are, of course, stored in different physical
locations.

MongoDB defines **replica sets**, wherein each of the nodes has a copy of the
same data. Each shard is assigned exactly one replica set. When writing in 
any way _(update, delete, insert)_ to a collection, MongoDB checks that a
specific minimum number of nodes within the responsible replica set have
successfully performed the update. Once the minimum number of replication is
reached, the user call will return and replication will continue 
asynchronously.

MongoDB provides the notion of **indexes**, both _hash indexes_ for point 
queries and _B+Tree indexes_ for range queries.

```javascript
// hash index
db.scientists.createIndex({
    "Name.Last" : "hash"
})

// B+Tree index
db.scientists.createIndex({
    "Name.Last" : 1
})

// secondary indexes
db.scientists.createIndex({
    "Name.Last" : 1
    "Name.First" : -1
})
```

The order of the fields in these secondary indexes is important - we sort outer
based on the first field, and then within the clusters, we sort again on the
second field _(so-on and so forth)_.

If we have a tree index on `(A, B, C, D)`, then a tree index on `(A)` is 
superfluous. However, if we need to query only based on `C`, then our composite
tree index is useless. In general, if we have a tree index on `A_1, ..., A_n`,
then we don't need a tree index on any prefix of this, i.e. `A_1, ..., A_m` 
with `m <= n`.

### When Indexes are Useful

```javascript
// hash index on Name.last: super fast
db.scientists.find({
    "Name.Last" : "Einstein"
})

// Hash index on Profession: faster than if we had no index, but less fast than 
// the previous query
db.scientists.find({
    "Profession" : "Physicist",
    "Theories" : "Relativity"
})

// consider:
db.scientists.createIndex({
    "Birth" : 1,
    "Death" : -1
})

// super fast
db.scientists.find({
    "Birth" : 1887,
    "Death" : 1946
})

// fast!
db.scientists.find({
    "Birth" : { "$gte": 1946 }
})

// can't use index since it is the second field
db.scientists.find({
    "Death" : { "$gte": 1946 }
})

// fast, but additional post-processing needed
db.scientists.find({
    "Birth" : { "$gte": 1946 },
    "Death" : 1998
})
```
