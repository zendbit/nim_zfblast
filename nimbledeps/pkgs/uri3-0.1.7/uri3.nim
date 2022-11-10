# Nim module for improved URI handling.
# Based on the "uri" module in the Nim standard library and the
# "purl" Python module at https://github.com/codeinthehole/purl.

# Written by Adam Chesak.
# Released under the MIT open source license.


# uri3 is a Nim module for improved URI handling. It allows for easy parsing of URIs, and
# can get and set various parts.
#
# Examples:
#
#  .. code-block:: nimrod
#
#    # Working with path and path segments.
#
#    # Parse a URI.
#    var uri : URI3 = parseURI3("http://www.examplesite.com/path/to/location")
#    echo(uri.getPath()) # "/path/to/location"
#
#    # Append a path segment.
#    uri.appendPathSegment("extra")
#    # uri / "extra" would have the same effect as the previous line.
#    echo(uri.getPath()) # "/path/to/location/extra"
#
#    # Prepend a path segment.
#    uri.prependPathSegment("new")
#    # "new" / uri would have the same effect as the previous line.
#    echo(uri.getPath()) # "/new/path/to/location/extra
#
#    # Set the path to something completely new.
#    uri.setPath("/my/path")
#    echo(uri.getPath()) # "/my/path"
#
#    # Set the path as individual segments.
#    uri.setPathSegments(@["new", "path", "example"])
#    echo(uri.getPath()) # "/new/path/example"
#
#    # Set a single path segment at a specific index.
#    uri.setPathSegment("changed", 1)
#    echo(uri.getPath()) # "/new/changed/example"
#
#
# .. code-block:: nimrod
#
#    # Working with queries.
#
#    # Parse a URI.
#    var uri : URI3 = parseURI3("http://www.examplesite.com/index.html?ex1=hello&ex2=world")
#
#    # Get all queries.
#    var queries : seq[seq[string]] = uri.getAllQueries()
#    for i in queries:
#        echo(i[0]) # Query name.
#        echo(i[1]) # Query value.
#
#    # Get a specific query.
#    var query : string = uri.getQuery("ex1")
#    echo(query) # "hello"
#
#    # Get a specific query, with a default value for if that query is not found.
#    echo(uri.getQuery("ex1", "DEFAULT")) # exists: "hello"
#    echo(uri.getQuery("ex3", "DEFAULT")) # doesn't exist: "DEFAULT"
#    # If no default is specified and a query isn't found, getQuery() will return the empty string.
#
#    # Set a query.
#    uri.setQuery("ex3", "example")
#    echo(uri.getQuery("ex3")) # "example"
#
#    # Set queries without overwriting.
#    uri.setQuery("ex4", "another", false)
#    echo(uri.getQuery("ex4")) # "another"
#    uri.setQuery("ex1", "test", false)
#    echo(uri.getQuery("ex1")) # not overwritten: still "hello"
#
#    # Set all queries.
#    uri.setAllQueries(@[  @["new", "value1",],  @["example", "value2"]])
#    echo(uri.getQuery("new")) # exists: "value1"
#    echo(uri.getQuery("ex1")) # doesn't exist: ""
#
#    # Set multiple queries.
#    uri.setQueries(@[  @["ex1", "new"],  @["new", "changed"]])
#    echo(uri.getQuery("new")) # "changed"
#    echo(uri.getQuery("example")) # "value2"
#    echo(uri.getQuery("ex1")) # "new"
#
#
# .. code-block:: nimrod
#
#    # Other examples.
#
#    # Parse a URI.
#    var uri : URI3 = parseURI3("http://www.examplesite.com/path/to/location")
#
#    # Convert the URI to a string representation.
#    var toString : string = $uri.
#    echo(toString) # "http://www.examplesite.com/path/to/location"
#
#    # Get the domain.
#    echo(uri.getDomain()) # "www.examplesite.com"
#
#    # Set the domain.
#    uri.setDomain("example.newsite.org")
#    echo(uri) # "http://example.newsite.org/path/to/location"
#
#    #Encode uri
#    let encUri = encodeUri("example.newsite.org/path/to/location yeah", usePlus=false) #default usePlus = true
#    echo(encUri)
#
#    # Decode uri
#    let decUri = encodeUri(encUri, decodePlus=false) #default decodePlus = true
#    echo(decUri)
#
#    # encodeToQuery
#    assert encodeToQuery({:}) == ""
#    assert encodeToQuery({"a": "1", "b": "2"}) == "a=1&b=2"
#    assert encodeToQuery({"a": "1", "b": ""}) == "a=1&b"


import uri
import strutils
import strformat

type
  URI3* = ref object
    scheme: string
    username: string
    password: string
    hostname: string
    port: string
    path: string
    anchor: string
    queries: seq[(string, string)]
    hashQueries: seq[(string, string)]
    hash: string


proc parseURI3*(url: string): URI3 =
  # Parses a URI.
  
  proc collectQueries(q: string): seq[(string, string)] =
    let queries: seq[string] = q.split("&")
    for i in 0..high(queries):
      let tmp = queries[i].split("=")
      if tmp.len == 2:
        result.add((tmp[0], tmp[1]))

  let u: URI = parseUri(url.split("/#")[0].split("#")[0])

  ##
  ##  process if url contains hash
  ##
  let findHash = url.find("#")
  var urlHash = ""
  var hashQueries: seq[(string, string)] = @[]
  if findHash != -1:
    let uHash = url.subStr(findHash, url.len - 1).split("?")
    urlHash = uHash[0]
    if uHash.len > 1:
      hashQueries = collectQueries(uHash[1])

  var newuri: URI3 = URI3(
    scheme: u.scheme,
    username: u.username,
    password: u.password,
    hostname: u.hostname,
    port: u.port,
    path: u.path,
    anchor: u.anchor,
    queries: collectQueries(u.query),
    hash: urlHash,
    hashQueries: hashQueries)

  return newuri

proc encodeUri*(url: string, usePlus: bool = true): string =
  result = encodeUrl(url, usePlus)

proc decodeUri*(url: string, decodePlus: bool = true): string =
  result = decodeUrl(url, decodePlus)

proc encodeToQuery*(query: openArray[(string, string)],
  usePlus: bool = true; omitEq: bool = true): string =
  result = encodeQuery(query, usePlus, omitEq)

proc appendPathSegment*(self: URI3, path: string) =
  # Appends the path segment specified by ``path`` to the end of the existing path.
  var newPath: string = self.path
  var path2: string = path
  if newPath.endsWith("/"):
    newPath = newPath[0..high(newPath) - 1]
  if path2.startsWith("/"):
    path2 = path2[1..high(path2)]
  newPath = newPath & "/" & path2
  self.path = newPath

proc appendHashSegment*(self: URI3, path: string) =
  # Appends the path segment specified by ``path`` to the end of the existing path.
  var newPath: string = self.hash
  var path2: string = path
  if newPath.endsWith("/"):
    newPath = newPath[0..high(newPath) - 1]
  if path2.startsWith("/"):
    path2 = path2[1..high(path2)]
  newPath = newPath & "/" & path2
  self.hash = newPath

proc prependPathSegment*(self: URI3, path: string) =
  # Prepends the path segment specified by ``path`` to the end of the existing path.
  var newPath: string = self.path
  var path2: string = path
  if newPath.startsWith("/"):
    newPath = newPath[1..high(newPath)]
  if path2.endsWith("/"):
    path2 = path2[0..high(path2) - 1]
  if not path2.startsWith("/"):
    path2 = "/" & path2
  newPath = path2 & "/" & newPath
  self.path = newPath

proc prependHashSegment*(self: URI3, path: string) =
  # Prepends the path segment specified by ``path`` to the end of the existing path.
  var newPath: string = self.hash
  var path2: string = path
  if newPath.startsWith("/"):
    newPath = newPath[1..high(newPath)]
  if path2.endsWith("/"):
    path2 = path2[0..high(path2) - 1]
  if not path2.startsWith("/"):
    path2 = "/" & path2
  newPath = path2 & "/" & newPath
  self.hash = newPath

proc getDomain*(self: URI3): string =
  # Returns the domain of ``uri``.
  result = self.hostname


proc getScheme*(self: URI3): string =
  # Returns the scheme of ``uri``.
  result = self.scheme


proc getUsername*(self: URI3): string =
  # Returns the username of ``uri``.
  result = self.username


proc getPassword*(self: URI3): string =
  # Returns the password of ``uri``.
  result = self.password


proc getPort*(self: URI3): string =
  # Returns the port of ``uri``.
  result = self.port


proc getPath*(self: URI3): string =
  # Returns the path of ``uri``.
  result = self.path

proc getHash*(self: URI3): string =
  # Returns the path of ``uri``.
  result = self.hash


proc getPathSegments*(self: URI3): seq[string] =
  # Returns the path segments of ``uri`` as a sequence.
  var paths: seq[string] = self.path.split("/")
  result = paths[1..high(paths)]

proc getHashSegments*(self: URI3): seq[string] =
  # Returns the path segments of ``uri`` as a sequence.
  var paths: seq[string] = self.hash.split("/")
  result = paths[1..high(paths)]

proc getPathSegment*(self: URI3, index: int): string =
  # Returns the path segment of ``uri`` at the specified index.
  return self.getPathSegments()[index]

proc getHashSegment*(self: URI3, index: int): string =
  # Returns the path segment of ``uri`` at the specified index.
  return self.getHashSegments()[index]


proc getAnchor*(self: URI3): string =
  # Returns the anchor of ``uri``.
  result = self.anchor


proc getAllQueries*(self: URI3): seq[(string, string)] =
  # Returns all queries of ``uri``.

  result = self.queries

proc getAllHashQueries*(self: URI3): seq[(string, string)] =
  # Returns all queries of ``uri``.

  result = self.hashQueries


proc getQuery*(self: URI3, query: string, default: string = ""): string =
  # Returns a specific query in ``uri``, or the specified ``default`` if there is no query with that name.
  var queryResult: string = default
  for i in self.queries:
    if i[0] == query:
      queryResult = i[1]
      break
  result = queryResult

proc getHashQuery*(self: URI3, query: string, default: string = ""): string =
  # Returns a specific query in ``uri``, or the specified ``default`` if there is no query with that name.
  var queryResult: string = default
  for i in self.hashQueries:
    if i[0] == query:
      queryResult = i[1]
      break
  result = queryResult

proc getQueryString*(self: URI3): string =
    # Returns a specific query in ``uri``, or the specified ``default`` if there is no query with that name.

    var query: string = ""
    for i in 0..high(self.queries):
      let k = self.queries[i][0].strip()
      let v = self.queries[i][1].strip()
      query &= k & "=" & v
      if i != high(self.queries):
        query &= "&"

    if query.strip() != "":
      result = "?" & query

proc getHashQueryString*(self: URI3): string =
    # Returns a specific query in ``uri``, or the specified ``default`` if there is no query with that name.

    var query: string = ""
    for i in 0..high(self.hashQueries):
      let k = self.hashQueries[i][0].strip()
      let v = self.hashQueries[i][1].strip()
      query &= k & "=" & v
      if i != high(self.queries):
        query &= "&"

    if query.strip() != "":
      result = "?" & query


proc setDomain*(self: URI3, domain: string) =
  # Sets the domain of ``uri``.
  self.hostname = domain


proc setScheme*(self: URI3, scheme: string) =
  # Sets the scheme of ``uri``.
  self.scheme = scheme


proc setUsername*(self: URI3, username: string) =
  # Sets the username of ``uri``.
  self.username = username


proc setPassword*(self: URI3, password: string) =
  # Sets the password of ``uri``.
  self.password = password


proc setPort*(self: URI3, port: string) =
  # Sets the port of ``uri``.
  self.port = port


proc setPath*(self: URI3, path: string) =
  # Sets the path of ``uri``.
  self.path = path


proc setPathSegments*(self: URI3, paths: seq[string]) =
  # Sets the path segments of ``uri``.
  var newpath: string = ""
  for i in 0..high(paths):
    newpath &= "/" & paths[i]
  self.path = newpath

proc setHashSegments*(self: URI3, paths: seq[string]) =
  # Sets the path segments of ``uri``.
  var newpath: string = ""
  for i in 0..high(paths):
    newpath &= "/" & paths[i]
  self.hash = newpath

proc setPathSegment*(self: URI3, path: string, index: int) =
  # Sets the path segment of ``uri`` at the given index. If the given index is larger than the highest
  # current index, there will be no change.
  var segments: seq[string] = self.getPathSegments()
  if high(segments) < index:
    return
  segments[index] = path
  self.setPathSegments(segments)

proc setHashSegment*(self: URI3, path: string, index: int) =
  # Sets the path segment of ``uri`` at the given index. If the given index is larger than the highest
  # current index, there will be no change.
  var segments: seq[string] = self.getHashSegments()
  if high(segments) < index:
    return
  segments[index] = path
  self.setHashSegments(segments)

proc setAnchor*(self: URI3, anchor: string) =
  # Sets the anchor of ``uri``.
  self.anchor = anchor

proc setAllQueries*(self: URI3, queries: seq[(string, string)]) =
  # Sets all the queries for ``uri``.
  self.queries = queries

proc setAllHashQueries*(self: URI3, queries: seq[(string, string)]) =
  # Sets all the queries for ``uri``.
  self.hashQueries = queries

proc setQuery*(
  self: URI3,
  query: string,
  value: string,
  overwrite: bool = true) =
  # Sets the query with the specified name and value in ``uri``. If ``overwrite`` is set to false, this will not
  # overwrite any query with the same name that is already present.
  if not overwrite and self.getQuery(query) != "":
    return
  var exists: bool = false
  var index: int = -1
  for i in 0..high(self.queries):
    if self.queries[i][0] == query:
      exists = true
      index = i
      break
  if exists:
    self.queries[index][1] = value
  else:
    self.queries.add(@[(query, value)])

proc setHashQuery*(
  self: URI3,
  query: string,
  value: string,
  overwrite: bool = true) =
  # Sets the query with the specified name and value in ``uri``. If ``overwrite`` is set to false, this will not
  # overwrite any query with the same name that is already present.
  if not overwrite and self.getHashQuery(query) != "":
    return
  var exists: bool = false
  var index: int = -1
  for i in 0..high(self.hashQueries):
    if self.hashQueries[i][0] == query:
      exists = true
      index = i
      break
  if exists:
    self.hashQueries[index][1] = value
  else:
    self.hashQueries.add(@[(query, value)])

proc setQueries*(
  self: URI3,
  queryList: openarray[(string, string)],
  overwrite: bool = true) =
  #
  # set queries, default overwrite to true
  # will overwrite with new value if query already exists
  # let urix = parseURI3("https://hello.com").setQueries(@[("foo", "bar"), ("foo1", "bar1")])
  # urix will have value https://hello.com?foo=bar&foo1=bar1
  #
  # Sets multiple queries with the specified names and values in ``uri``. If ``overwrite`` is set to false, this will not
  # overwrite any query with the same name that is already present.
  #
  # This proc differs from ``setAllQueries()`` in that it does not remove any existing queries, but instead
  # just appends the new ones.
  for i in queryList:
    self.setQuery(i[0], i[1], overwrite)

proc setHashQueries*(
  self: URI3,
  queryList: openarray[(string, string)],
  overwrite: bool = true) =
  #
  # set queries, default overwrite to true
  # will overwrite with new value if query already exists
  # let urix = parseURI3("https://hello.com").setQueries(@[("foo", "bar"), ("foo1", "bar1")])
  # urix will have value https://hello.com?foo=bar&foo1=bar1
  #
  # Sets multiple queries with the specified names and values in ``uri``. If ``overwrite`` is set to false, this will not
  # overwrite any query with the same name that is already present.
  #
  # This proc differs from ``setAllQueries()`` in that it does not remove any existing queries, but instead
  # just appends the new ones.
  for i in queryList:
    self.setHashQuery(i[0], i[1], overwrite)

proc `/`*(self: URI3, path: string) =
  #
  # append new segment to the url
  # let urix = parseURI3("https://hello.com")/"welcome"/"home"
  # urix will have value https://hello.com/welcome/home
  #
  # Operator version of ``appendPathSegment()``.
  self.appendPathSegment(path)

proc `/h`*(self: URI3, path: string) =
  #
  # append new segment to the url for hash url
  # let urix = parseURI3("https://hello.com")/"welcome"/"home"
  # urix will have value https://hello.com/welcome/home
  #
  # Operator version of ``appendPathSegment()``.
  self.appendHashSegment(path)

proc `/`*(path: string, self: URI3) =
  #
  # prepend new segment to the url
  # let urix = "welcome"/parseURI3("https://hello.com/home")
  # urix will have value https://hello.com/welcome/home
  #
  # Operator version of ``prependPathSegment()``.
  self.prependPathSegment(path)

proc `/h`*(path: string, self: URI3) =
  #
  # prepend new segment to the url for hash url
  # let urix = "welcome"/parseURI3("https://hello.com/home")
  # urix will have value https://hello.com/welcome/home
  #
  # Operator version of ``prependPathSegment()``.
  self.prependHashSegment(path)

proc `?`*(self: URI3; query: openArray[(string, string)]) =
  #
  # add query parameter
  # let urix = parseURI3("https://hello.com") ? [("search", "hai"), ("offset", "4")]
  # urix will have value https://hello.com?search=hai&offset=4
  #
  for q in query:
    self.setQuery(q[0], q[1], true)

proc `?h`*(self: URI3; query: openArray[(string, string)]) =
  #
  # add query parameter for hash url
  # let urix = parseURI3("https://hello.com") ? [("search", "hai"), ("offset", "4")]
  # urix will have value https://hello.com?search=hai&offset=4
  #
  for q in query:
    self.setHashQuery(q[0], q[1], true)

proc getBaseUrl*(self: URI3): string =
  if self.port == "" or self.port == "80":
    result = &"{self.getScheme}://{self.getDomain}"

  else:
    result = &"{self.getScheme}://{self.getDomain}:{self.getPort}"

proc `$`*(self: URI3): string =
  # Convers ``uri`` to a string representation.
  proc buildQuery(q: seq[(string, string)]): string =
    var query: string = ""
    for i in 0..high(q):
      let k = q[i][0].strip()
      let v = q[i][1].strip()
      if k == "" and v == "": continue
      query &= k & "=" & v
      if i != high(q):
        query &= "&"

    result = query

  # Let's be lazy about this. :P
  var u: URI = URI(
    scheme: self.scheme,
    username: self.username,
    password: self.password,
    hostname: self.hostname,
    port: self.port,
    path: self.path,
    query: buildQuery(self.queries),
    anchor: self.anchor)

  var url = $u
  if self.hash != "":
    url &= "/" & self.hash & buildQuery(self.hashQueries)

  result = $url
