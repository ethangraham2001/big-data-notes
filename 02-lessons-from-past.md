# 02: Lessons Learned from the Past

DBMS stack has four layers to it

- Logical query language which the user uses to query data
- Logical model for the data
- Physical compute layer that processes the query on an instance of the model
- A physical storage layer

Data independence should always apply.

**RDBMS:**

First class citizens:

- _Table_ which is a collection of records
- _attribute_ which is a propery these records can have
- _row_ which is a record in a collection
- _primary key_ which is a particular attribute or set of attributes that 
uniquely identify a row in its table

## Mathematical formulation of a relation

The set of records is the set of partial functions from $\mathbb S$ to
$\mathbb V$. We call this $C$.

The domain is over $\mathbb S$, the set of strings, because we map from an
attribute name to some value.

This reflects the unordered nature of the records.

## Contraints

Tables have additional contrains that aren't expressed in the mathematical
formulation

- _relational integrity_: all records have identical support - i.e. that all
records are defined over the same set of inputs.
- _domain integrity_: the values associated with each attribute are restricted
to a domain. Typically these domains are standard sets such as integers, 
booleans, etc... This still allows for missing values, mind you.
- _atomic integrity_: the values used are only atomic values. I.e. we don't
support nested tables or arrays, for instance.

We define a relational table as one that satisfies these three fundamental
integrity constraints.

Leaving these integrity constraints, we enter the realm of NoSQL.

We can also extend these relational semantics to list semantics _(ordered 
rows)_, bag semantics _(multiset, we allow duplicates)_. By design, it 
satisfies _set_ semantics.

## Relational algebra

We can classify the operations that we can perform on a table into four broad
categories

- _set queries_: `UNION, INTERSECTION, SUBTRACTION`
- _filter queries_: `SELECT, PROJECT`
- _renaming queries_: relation renaming, attribute renaming
- _joining queries_: `JOIN`, cartesian product, theta-join

## Normal forms

- _first normal form_: what we have discussed so far, respecting atomic 
integrity
- _second normal form_: each column in a record contains information on the
entire record. Every column value depends on the primary key. We can normally
obtain the first normal form version of the table through `JOIN` ops - so 
normalizing is just the opposite of joining, basically.
- _third normal form_: forbid functional dependencies on anything other than
the primary key.

In big data we normally throw normal forms away, denormalizing the data a lot
in order to allow for better scalability and performance.

## Transactions

We want ACID here.
