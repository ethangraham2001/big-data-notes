# 05 Syntax

I'm not going to spend heaps of time on this because I feel that it lacks any
meaningful substance.

The key motivation is that in a relational DBMS, the user doesn't have to 
understand the format of the data. In a data lake, the data is stored in the
format uploaded by the user - i.e. JSON, XML, or something else. So this is
now exposed to the user directly. Data is no longer ETLed, we query in-situ.

## CSV

This is a textual format _(can open it in `vim`)_ unlike binary formats which
are more opaque.

There are many different dialects and variants despite there existing a 
standard. This hinders on interoperability.

## Data denormalization

We saw previously that data denormalization is sometimes desirable - this is
especially true in data lakes. We now get to nest tables within tables!

Denormalization is fantastic in read-heavy workloads where we don't want to 
`JOIN` excessively. In read-intensive scenarios, we love anything that is a 
linear scan.

The generic term for denormalized data is **semi-structured data**.

## JSON

Six building blocks

- Strings
- numbers
- booleans
- `null`
- objects
- arrays

JSON keys **must** be strings. Some parsers are lenient, but for compatibility 
with the spec, one should always double-quote key names.

We should also never create any JSON docs with duplicate keys - a lot of 
parsers don't support this. We should try and save ourselves the hassle of
disambiguiating the JSON documents down the line, and just never create such
documents in the first place.

## XML

Extensible markup language. Terribly complex, much more so than JSON anyway.
But we only cover a slim subset of XML features.

```
<person/> == <person></person>
```

Unlike JSON keys, element names can repeat at will - it is even commmon in 
fact. We need to watch out while parenthesizing - our document should of course
be well-parenthesized.

A well-formed XML document has exactly one element at the top-level.

XML forbids users from creating element names that start with `xml` (uppercase,
or lower case, or anything) - it is reserved. XML parsers have to be forward
compatible with any future specs that might arise and introduce special names
starting with XML.

**Attributes** appear in any opening element tags and are basically key-value
pairs.

```xml
<person birth="1879" death="1955">
    <first>(some content)</first>
    <last>(some other content)</last>
</person>
```

or we can single quote the values.

```xml
<person birth='1879' death='1955'>
    <first>(some content)</first>
    <last>(some other content)</last>
</person>
```

**The key is never quoted in XML _(unlike JSON)_. There can also be no
duplicate keys within the same tag**

Attributes can also appear in an empty element tag

```xml
<person age="1912/>
```

Note that we cannot nest within attribute values

```xml
<!-- not allowed! -->
<person birth="<date>1879</date>" death="1955">
```

Text cannot appear by itself at the top-level.

Within an element, text can freely alternate with other elements. This is 
called mixed content and is unique to XML

```xml
<person>
    <style>His Royal Highness</style>
    The <title>Duke of <location>Cambridge</location></title>
</person>
```

Note that we can put comments wherever we want

```xml
<person birth="1879" death="1955">
    <first>Albert</first>
    <last>Einstein</last>
    <!-- He is still famous today -->
</person>

<!-- He is still famous today -->
<person birth="1879" death="1955">
    <first>Albert</first>
    <last>Einstein</last>
</person>
<!-- He is -->
<!-- He totally is -->
```

We can identify XML documents by an optional declaration containing the
version number and encoding

```xml
<?xml version="1.0" encoding="UTF-8"?>
<person birth="1879" death="1955">
    <first>Albert</first>
    <last>Einstein</last>
</person>
```
