About
=====

High performance http server (https://tools.ietf.org/html/rfc2616) with persistent connection for nim language.
Serving in 1-2 miliseconds for persistent connection.

read persistent connection RFC (https://tools.ietf.org/html/rfc2616)

Nimble installation
===================

```
nimble install zfblast
```

Examples
========

```
need to compiled with -d:ssl and make sure openssl installed
```

```
let zfb = newZFBlast(
    "0.0.0.0",
    Port(8000),
    # default value for debug is false
    # if want to know about tracing the data process set to true
    debug = false,
    sslSettings = newSslSettings(
        certFile = joinPath("ssl", "certificate.pem"),
        keyFile = joinPath("ssl", "key.pem"),
        verifyMode = SslCVerifyMode.CVerifyNone,
        port = Port(8443)
    ))
waitfor zfb.serve(proc (ctx: HttpContext): Future[void] {.async.} =
    case ctx.request.url.getPath
    # http(s)://localhost
    of "/":
        ctx.response.httpCode = Http200
        ctx.response.headers.add("Content-Type", "text/plain")
        # make sure index.html file exist
        ctx.response.body.write(newFileStream("index.html").readAll())
    # http(s)://localhost/home
    of "/home":
        ctx.response.httpCode = Http200
        ctx.response.headers.add("Content-Type", "text/html")
        # make sure index.html file exist
        ctx.response.body.write(newFileStream("index.html").readAll())
    # http(s)://localhost/api/home
    of "/api/home":
        ctx.response.httpCode = Http200
        ctx.response.headers.add("Content-Type", "application/json")
        ctx.response.body.write("""{"version" : "0.1.0"}""")
    # will return 404 not found if route not defined
    else:
        ctx.response.httpCode = Http404
        ctx.response.body.write("not found")
    await ctx.resp
)
```

TODO:
- websocket
- upgrade to HTTP 2.0 (Future roadmap)
