About
=====

nim.uri3 is a Nim module that provides improved way for working with URIs. It is based on the "uri" module in the Nim standard library
and the "[purl](https://github.com/codeinthehole/purl)" Python module. This is based on "[nim-uri2](https://github.com/achesak/nim-uri2)"

Examples
========

Working with path and path segments:

    # Parse a URI.
    var uri : Uri3 = parseUri3("http://www.examplesite.com/path/to/location")
    echo(uri.getPath()) # "/path/to/location"

    # Append a path segment.
    uri.appendPathSegment("extra")
    # uri / "extra" would have the same effect as the previous line.
    echo(uri.getPath()) # "/path/to/location/extra"

    # Prepend a path segment.
    uri.prependPathSegment("new")
    # "new" / uri would have the same effect as the previous line.
    echo(uri.getPath()) # "/new/path/to/location/extra

    # Set the path to something completely new.
    uri.setPath("/my/path")
    echo(uri.getPath()) # "/my/path"

    # Set the path as individual segments.
    uri.setPathSegments(@["new", "path", "example"])
    echo(uri.getPath()) # "/new/path/example"

    # Set a single path segment at a specific index.
    uri.setPathSegment("changed", 1)
    echo(uri.getPath()) # "/new/changed/example"

Working with queries:

    # Parse a URI.
    var uri : Uri3 = parseUri3("http://www.examplesite.com/index.html?ex1=hello&ex2=world")

    # Get all queries.
    var queries : seq[seq[string]] = uri.getAllQueries()
    for i in queries:
        echo(i[0]) # Query name.
        echo(i[1]) # Query value.

    # Get a specific query.
    var query : string = uri.getQuery("ex1")
    echo(query) # "hello"

    # Get a specific query, with a default value for if that query is not found.
    echo(uri.getQuery("ex1", "DEFAULT")) # exists: "hello"
    echo(uri.getQuery("ex3", "DEFAULT")) # doesn't exist: "DEFAULT"
    # If no default is specified and a query isn't found, getQuery() will return the empty string.

    # Set a query.
    uri.setQuery("ex3", "example")
    echo(uri.getQuery("ex3")) # "example"

    # Set queries without overwriting.
    uri.setQuery("ex4", "another", false)
    echo(uri.getQuery("ex4")) # "another"
    uri.setQuery("ex1", "test", false)
    echo(uri.getQuery("ex1")) # not overwritten: still "hello"

    # Set all queries.
    uri.setAllQueries(@[  @["new", "value1",],  @["example", "value2"]])
    echo(uri.getQuery("new")) # exists: "value1"
    echo(uri.getQuery("ex1")) # doesn't exist: ""

    # Set multiple queries.
    uri.setQueries(@[  @["ex1", "new"],  @["new", "changed"]])
    echo(uri.getQuery("new")) # "changed"
    echo(uri.getQuery("example")) # "value2"
    echo(uri.getQuery("ex1")) # "new"

Other examples:

    # Parse a URI.
    var uri : Uri3 = parseUri3("http://www.examplesite.com/path/to/location")

    # Convert the URI to a string representation.
    var toString : string = $uri.
    echo(toString) # "http://www.examplesite.com/path/to/location"

    # Get the domain.
    echo(uri.getDomain()) # "www.examplesite.com"

    # Set the domain.
    uri.setDomain("example.newsite.org")
    echo(uri) # "http://example.newsite.org/path/to/location"

    # Encode uri
    let encUri = encodeUri("example.newsite.org/path/to/location yeah", usePlus=false) #default usePlus = true
    echo(encUri)

    # Decode uri
    let decUri = encodeUri(encUri, decodePlus=false) #default decodePlus = true
    echo(decUri)

    # encodeToQuery
    assert encodeToQuery({:}) == ""
    assert encodeToQuery({"a": "1", "b": "2"}) == "a=1&b=2"
    assert encodeToQuery({"a": "1", "b": ""}) == "a=1&b"

License
=======

nim.uri3 is released under the MIT open source license.
