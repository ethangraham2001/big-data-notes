# 13 Graph Databases

Relational tables are very easy for us to wrap our heads around. However, the
more we normalize our data to separate concerns, the more we end up having to
join afterwards. This is an exceptionally expensive operation at large scales.

The idea is to try and avoid joins altogether - perhaps by encoding the
relationship between tables directly into the table itself...

We describe a few different types of graph databases.

- Labeled property graph model versus triple stores
- Read-intensive vs. write-intensive.
- Local vs. distributed
- Native vs non-native: some graph DBs are just a layer on top of another
    DB, like Postgres or something.

## Labeled Property Graphs

We firstly define a **label** as a string tag attached to a node or an edge in
a graph.

We additionally define **properties**, which is a string-to-value map 
associated to each node or edge. You can think of the properties as a JSON
object associated with each node or edge.

We can pretty easily convert a relational table to a labeled property graph

- Labels can be seen as table names
- Nodes as records
- Properties as attribute values for records
- Edges as foreign key / primary key relationships

![Relational table as an equivalent graph DB](images/graph-relational.png)

## Triple Stores

This is a simpler model than labeled property graphs - it views the graph as
nodes and edges that all have labels, but without any properties.

Each edge is a triple with the label of the origin node called **subject**, 
label of the edge called **property**, and label of the destination node called
the **object**.

Labels can be pretty much anything, whether that be URIs, atomic values, or 
absent altogether.

## Querying Graph DBMS

We focus on **Cypher**, which is a querying language for labeled property
graphs. This is done using pattern matching like semantics, the syntax that
looks like ASCII art.

```
MATCH (alpha)-[:A]->(beta)-[:B]->(gamma)
RETURN alpha, beta, gamma
```

I.e. match these edge patterns _(representing some relation)_ and return the
nodes satisfying it. This query returns an output with three columns 
`alpha, beta, gamma` which are of type `node`. 

We can filter on node or edge properties.

```
MATCH (alpha)-[:A]->(beta:yellow)-[:B]->(gamma)
RETURN alpha, beta, gamma
```

We can also filter on node or edge properties as well

```
MATCH (alpha)-[:A]->(beta { name: ’Einstein’ })-[:B]->(gamma)
RETURN alpha, beta, gamma
```

Here are some other examples of things that we can do.

```
// filter on label and property
MATCH (alpha)-[:A]->(beta)-[:B]->(gamma: blue { name : ’ETH’})
RETURN alpha, beta, gamma

// reverse edges in pattern syntax
MATCH (alpha)-[:A]->(beta)-[:B]->(gamma)<-[:B]-(delta)
RETURN alpha, beta, gamma, delta

// reuse variable to look for cycle
MATCH (alpha)-[:A]->(beta)-[:B]->(gamma)<-[:B]-(alpha)
RETURN alpha, beta, gamma

// match longer paths
MATCH (alpha)-[*1..4]->(beta)<-[:B]-(alpha)
RETURN alpha, beta
```
