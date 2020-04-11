#[
    ZendFlow web framework for nim language
    This framework if free to use and to modify
    License: BSD
    Author: Amru Rosyada
    Email: amru.rosyada@gmail.com
    Git: https://github.com/zendbit

    HTTP/1.1 implementation in nim lang depend on RFC (https://tools.ietf.org/html/rfc2616)
    Supporting Keep Alive to maintain persistent connection.
]#
import
    asyncnet,
    asyncdispatch,
    os,
    net,
    strformat,
    strutils,
    httpcore,
    uri3,
    streams,
    times,
    nativesockets

const
    # http version header
    HTTP_VERSION* = "HTTP/1.1"
    # server header identifier
    SERVER_ID* = "ZFBlast (Nim)"
    # server build version
    SERVER_VERSION* = "V0.1.4"
    # CRLF header token
    CRLF* = "\c\L"


const defineSsl = defined(ssl) or defined(nimdoc)

type
    # header request parser step
    ContentParseStep* = enum
        ReqMethod,
        Header,
        Body

    # Request type
    Request* = ref object
        # containt request header from client
        httpVersion*: string
        # request http method from client
        httpMethod*: HttpMethod
        # containt url object from client
        # read uri3 nimble package
        url*: Uri3
        # containt request headers from client
        headers*: HttpHeaders
        # contain request body from client
        body*: string

    # Response type
    Response* = ref object
        # httpcode response to client
        httpCode*: HttpCode
        # headers response to client
        headers*: HttpHeaders
        # body response to client
        body*: string

    # HttpContext type
    HttpContext* = ref object of RootObj
        # Request type instance
        request*: Request
        # client asyncsocket for communicating to client
        client*: AsyncSocket
        # Response type instance
        response*: Response
        # send response to client, this is bridge to ZFBlast send()
        send*: proc (ctx: HttpContext): Future[void]
        # Keep-Alive header max request with given persistent timeout
        # read RFC (https://tools.ietf.org/html/rfc2616)
        # section Keep-Alive and Connection
        # for improving response performance
        keepAliveMax*: int
        # Keep-Alive timeout
        keepAliveTimeout*: int

    # SslSettings type for secure connection
    SslSettings* = ref object
        # path to certificate file (.pem)
        certFile*: string
        # path to private key file (.pem)
        keyFile*: string
        # verify mode
        # verify = false -> use SslCVerifyMode.CVerifyNone for self signed certificate
        # verify = true -> use SslCVerifyMode.CVerifyPeer for valid certificate
        verify*: bool
        # port for ssl
        port*: Port

    # ZFBlast type
    ZFBlast* = ref object
        # port for unsecure connection (http)
        port*: Port
        # address to bind
        address*: string
        # resuse address
        reuseAddress*: bool
        # reuser port
        reusePort*: bool
        # debug mode
        debug*: bool
        # SslSettings instance type
        sslSettings*: SslSettings
        # Keep-Alive header max request with given persistent timeout
        # read RFC (https://tools.ietf.org/html/rfc2616)
        # section Keep-Alive and Connection
        # for improving response performance
        keepAliveMax*: int
        # Keep-Alive timeout
        keepAliveTimeout*: int
        # serve unsecure (http)
        server: AsyncSocket
        # serve secure (https)
        sslServer: AsyncSocket
        # max body length server can handle
        # can be vary on seting
        # value in bytes
        maxBodyLength*: int

proc dbg*(cb: proc ()): Future[void] {.async.} =
    if not isNil(cb):
        try:
            cb()

        except Exception as ex:
            echo ex.msg
#[
    Response type procedures
]#

#[
    create new request
    in general this will return Request instance with default value
    and will be valued with request from client
]#
proc newRequest*(
    httpMethod: HttpMethod = HttpGet,
    httpVersion: string = HTTP_VERSION,
    url: Uri3 = parseUri3(""),
    headers: HttpHeaders = newHttpHeaders(),
    body: string = ""): Request =

    return Request(
        httpMethod: httpMethod,
        httpVersion: httpVersion,
        url: url,
        headers: headers,
        body: body)

proc getHttpHeaderValues*(key: string, httpHeaders: HttpHeaders): HttpHeaderValues =
    var headers: HttpHeaderValues = httpHeaders.getOrDefault(key)
    if headers == "":
        return httpHeaders.getOrDefault(key.toLower())

    return headers
###

#[
    Response type procedures
]#

#[
    create Response instance
    in general this will valued with Response instance with default value
]#
proc newResponse*(
    httpCode: HttpCode = Http200,
    headers: HttpHeaders = newHttpHeaders(),
    body: string = ""): Response =

    return Response(
        httpCode: httpCode,
        headers: headers,
        body: body)
###

#[
    HttpContext type procedures
]#

#[
    create HttpContext instance
    this will be the main HttpContext
    will be contain:
        client -> is the asyncsocket of connected client
        request -> is the request from client
        response -> is the response from server
        keepAliveMax -> max request can handle by server on persistent connection
            default value is 20 persistent request per connection
        keepAliveTimeout -> keep alive timeout for persistent connection
            default value is 10 seconds
]#
proc newHttpContext*(
    client: AsyncSocket,
    request: Request = newRequest(),
    response: Response = newResponse(body = ""),
    keepAliveMax: int = 10,
    keepAliveTimeout: int = 20): HttpContext =

    return HttpContext(
        client: client,
        request: request,
        response: response,
        keepAliveMax: keepAliveMax,
        keepAliveTimeout: keepAliveTimeout)

# response to the client
proc resp*(self: HttpContext): Future[void] {.async.} =
    if not isNil(self.send):
        await self.send(self)

# clear the context for next persistent connection
proc clear*(self: HttpContext) =
    self.request.body = ""
    self.response.body = ""
    clear(self.response.headers)
    clear(self.request.headers)

# return secure or not of the client request
# is secure flag, the idea from qbradley
# https://github.com/zendbit/nim.zfblast/commits?author=qbradley
# we will keep it private, because this is the readonly flaq
proc isSecure*(self: HttpContext): bool =
    return self.client.isSsl

###

#[
    SslSettings type procedures
]#
proc newSslSettings*(
    certFile: string,
    keyFile: string,
    port: Port = Port(8443),
    verify: bool = false): SslSettings =

    return SslSettings(
        certFile: certFile,
        keyFile: keyFile,
        verify: verify,
        port: port)
###

#[
    ZFBlast type procedures
]#
proc setupServer(self: ZFBlast) =

    # init http server socket
    if isNil(self.server):
        self.server = newAsyncSocket()

    # init https server socket
    when defineSsl:
        if not isNil(self.sslSettings) and
            isNil(self.sslServer):
            if not fileExists(self.sslSettings.certFile):
                echo "Certificate not found " & self.sslSettings.certFile
            elif not fileExists(self.sslSettings.keyFile):
                echo "Private key not found " & self.sslSettings.keyFile
            else:
                self.sslServer = newAsyncSocket()

proc isKeepAlive(
    self: ZFBlast,
    httpContext: HttpContext): bool =

    let keepAliveHeader = getHttpHeaderValues(
        "Connection",
        httpContext.request.headers)
    if keepAliveHeader != "":
        if keepAliveHeader.toLower().find("close") == -1:
            return true

    return false

# send response to the client
proc send*(
    self: ZFBlast,
    httpContext: HttpContext): Future[void] {.async.} =

    echo isNil(httpContext.client)
    if httpContext.request.headers.len == 0:
        if not httpContext.client.isClosed():
            httpContext.client.close()
        return

    var contentBody: string = ""
    let isKeepAlive = self.isKeepAlive(httpContext)

    var headers = ""
    headers &= &"{HTTP_VERSION} {httpContext.response.httpCode}\n"
    headers &= &"Server: {SERVER_ID} {SERVER_VERSION}\n"
    headers &= "Date: " &
        format(now().utc, "ddd, dd MMM yyyy HH:mm:ss") & " GMT\n"

    if isKeepAlive:
        if not (httpContext.response.headers.hasKey("Connection") or
            httpContext.response.headers.hasKey("connection")):
            headers &= "Connection: keep-alive\n"

        if not (httpContext.response.headers.hasKey("Keep-Alive") or
            httpContext.response.headers.hasKey("keep-alive")):
            headers &= "Keep-Alive: " &
                &"timeout={httpContext.keepAliveTimeout}" &
                &", max={httpContext.keepAliveMax}\n"

    else:
        headers &= "Connection: close\n"

    if httpContext.request.httpMethod != HttpHead:
        contentBody = httpContext.response.body
        headers &= &"Content-Length: {contentBody.len}\n"

    for k, v in httpContext.response.headers.pairs:
        headers &= &"{k}: {v}\n"

    headers &= CRLF

    if isNil(httpContext.client) or
        httpContext.client.isClosed(): return

    if httpContext.request.httpMethod == HttpHead:
        await httpContext.client.send(headers)

    else:
        await httpContext.client.send(headers & contentBody)

    # clean up all string stream request and response
    httpContext.clear()

    if not isKeepAlive and (not httpContext.client.isClosed()):
        httpContext.client.close()

    # show debug
    if self.debug:
        asyncCheck dbg(proc () =
            echo ""
            echo "#== start"
            echo "Response to client"
            echo headers
            echo "#== end"
            echo "")

# handle client connections
proc clientHandler(
    self: ZFBlast, httpContext: HttpContext,
    callback: proc (ctx: HttpContext): Future[void]): Future[void] {.async.} =

    let client = httpContext.client

    # show debug
    if self.debug:
        let (clientHost, clientPort) = client.getPeerAddr
        asyncCheck dbg(proc () =
            echo ""
            echo "#== start"
            echo "Process incoming request from client"
            echo &"Client address  : {clientHost}"
            echo &"Client port     : {clientPort}"
            echo &"Date            : " &
                format(now().utc, "ddd, dd MMM yyyy HH:mm:ss") & " GMT"
            echo "")

    # parse step
    var parseStep = ContentParseStep.ReqMethod
    while true:
        let line = await client.recvLine()
        
        case parseStep
        of ContentParseStep.ReqMethod:
            let reqParts = line.strip().split(" ")
            if reqParts.len == 3:
                case reqParts[0]
                of "GET":
                    httpContext.request.httpMethod = HttpGet

                of "POST":
                    httpContext.request.httpMethod = HttpPost

                of "PATCH":
                    httpContext.request.httpMethod = HttpPatch

                of "PUT":
                    httpContext.request.httpMethod = HttpPut

                of "DELETE":
                    httpContext.request.httpMethod = HttpDelete

                of "OPTIONS":
                    httpContext.request.httpMethod = HttpOptions

                of "TRACE":
                    httpContext.request.httpMethod = HttpTrace

                of "HEAD":
                    httpContext.request.httpMethod = HttpHead

                of "CONNECT":
                    httpContext.request.httpMethod = HttpConnect

                else:
                    # show debug
                    if self.debug:
                        asyncCheck dbg(proc () =
                            echo "Bad request cannot process request."
                            echo &"{reqParts[0]} not implemented.")

                    #httpContext.response.httpCode = Http501
                    #await self.send(httpContext)
                    if not client.isClosed():
                        client.close()
                    return

                var protocol = "http"
                if client.isSsl:
                    protocol = "https"
                
                let (peerAddr, _) = client.getLocalAddr
                httpContext.request.url = parseUri3(reqParts[1])
                httpContext.request.url.setScheme(protocol)
                httpContext.request.url.setDomain(peerAddr)
                httpContext.request.httpVersion = reqParts[2]

            else:
                # show debug
                if self.debug:
                    asyncCheck dbg(proc () =
                        echo "Bad request cannot process request."
                        echo &"Wrong request header format.")

                #httpContext.response.httpCode = Http400
                #await self.send(httpContext)
                if not client.isClosed():
                    client.close()
                return

            parseStep = ContentParseStep.Header

            #show debug
            if self.debug:
                asyncCheck dbg(proc () =
                    echo line)

        of ContentParseStep.Header:
            # pull reqeust @@ -430,11 +430,8 @@ proc clientHandler(
            # qbradley
            # https://github.com/zendbit/nim.zfblast/commits?author=qbradley
            let headers = parseHeader(line.strip())
            if headers.key.strip() != "" and headers.value.len != 0:
                httpContext.request.headers[headers.key] = headers.value
                if headers.key.toLower() == "host":
                    httpContext.request.url.setDomain(headers.value.join(", ").split(":")[0])

            #show debug
            if self.debug:
                asyncCheck dbg(proc () =
                    echo line)

            if line == CRLF:
                # if in post, put and patch simply set parse body step
                if httpContext.request.httpMethod in
                        [HttpPost, HttpPut, HttpPatch]:
                    parseStep = ContentParseStep.Body

                break

        else:
            break

    if parseStep == ContentParseStep.Body:
        #if bodyBoundary == "":
        #    bodyBoundary = line

        #httpContext.request.body.writeLine(line)
        let contentLength = getHttpHeaderValues(
            "content-length",
            httpContext.request.headers)

        # check body content
        if contentLength != "":
            let bodyLen = parseInt(contentLength)

            # if body content larger than server can handle
            # return 413 code
            if bodyLen > self.maxBodyLength:
                # show debug
                if self.debug:
                    asyncCheck dbg(proc () =
                        echo "Body request to large server cannot handle."
                        echo &"Only {self.maxBodyLength} bytes allowed."
                        echo "Should change maxBodyLength value in settings.")

                httpContext.response.httpCode = Http413
                await self.send(httpContext)
                return

            httpContext.request.body = await client.recv(bodyLen)

            #show debug
            #[
            if self.debug:
                let bodySeq = httpContext.request.readBody.split("\n")
                let contentType = httpContext.request.headers
                    .getOrDefault("Content-Type")
                var bodyBoundary = ""
                var isAttachment = false
                for bodyLine in bodySeq:
                    let bodyLineStrip = bodyLine.strip
                    if contentType.startsWith("multipart/form-data"):
                        if bodyBoundary == "" and bodyLineStrip != "":
                            bodyBoundary = bodyLineStrip

                    if bodyLineStrip.startsWith("Content-Disposition") and
                            bodyLineStrip.contains("name=") and
                            bodyLineStrip.contains("filename="):
                        isAttachment = true

                    elif bodyLineStrip.startsWith(bodyBoundary):
                        isAttachment = false

                    if bodyLineStrip.startsWith(bodyBoundary) or
                            bodyLineStrip.startsWith("Content-Disposition") or
                            bodyLineStrip.startsWith("Content-Type") or
                            bodyLineStrip == "" or
                            (bodyLineStrip != "" and (not isAttachment)):
                        echo bodyLineStrip
            ]#

        else:
            #httpContext.response.httpCode = Http411
            #await self.send(httpContext)
            if not client.isClosed():
                client.close()
            return

    if self.debug:
        asyncCheck dbg(proc () =
            echo "#== end"
            echo "")

    # call the callback
    if not isNil(callback):
        await callback(httpContext)

    elif not httpContext.client.isClosed():
        httpContext.response.httpCode = Http200
        await self.send(httpContext)

# handle client listener
# will listen until the client socket closed
proc clientListener(
    self: ZFBlast,
    client: AsyncSocket,
    callback: proc (ctx: HttpContext): Future[void]): Future[void] {.async.} =

    try:
        # setup http context
        #let (clientHost, clientPort) = client.getPeerAddr
        let httpContext = newHttpContext(
            client = client,
            keepAliveTimeout = self.keepAliveTimeout,
            keepAliveMax = self.keepAliveMax)
        
        httpContext.send = proc (ctx: HttpContext): Future[void] {.async.} =
            await self.send(ctx)

        while not httpContext.client.isClosed():
            await self.clientHandler(httpContext, callback)

    except Exception as ex:
        # show debug
        if self.debug:
            asyncCheck dbg(proc () =
                echo ""
                echo "#== start"
                echo "Client connection closed, accept new session."
                echo ex.msg
                echo "#== end"
                echo "")

# serve unscure connection (http)
proc doServe(
    self: ZFBlast,
    callback: proc (ctx: HttpContext): Future[void]): Future[void] {.async.} =

    if not isNil(self.server):
        self.server.setSockOpt(OptReuseAddr, self.reuseAddress)
        self.server.setSockOpt(OptReusePort, self.reusePort)
        self.server.bindAddr(self.port, self.address)
        self.server.listen

        let (host, port) = self.server.getLocalAddr
        echo &"Listening non secure (plain) on http://{host}:{port}"

        while true:
            try:
                let client = await self.server.accept()
                asyncCheck self.clientListener(client, callback)

            except Exception as ex:
                # show debug
                if self.debug:
                    asyncCheck dbg(proc () =
                        echo ""
                        echo "#== start"
                        echo "Failed to serve."
                        echo ex.msg
                        echo "#== end"
                        echo "")

# serve secure connection (https)
when defineSsl:
    proc doServeSecure(
        self: ZFBlast,
        callback: proc (ctx: HttpContext): Future[void]): Future[void] {.async.} =

        if not isNil(self.sslServer):
            self.sslServer.setSockOpt(OptReuseAddr, self.reuseAddress)
            self.sslServer.setSockOpt(OptReusePort, self.reusePort)
            self.sslServer.bindAddr(self.sslSettings.port, self.address)
            self.sslServer.listen

            let (host, port) = self.sslServer.getLocalAddr
            echo &"Listening secure on https://{host}:{port}"

            while true:
                try:
                    let client = await self.sslServer.accept()
                    let (host, port) = self.sslServer.getLocalAddr()

                    var verifyMode = SslCVerifyMode.CVerifyNone
                    if self.sslSettings.verify:
                        verifyMode = SslCVerifyMode.CVerifyPeer

                    let sslContext = newContext(
                        verifyMode = verifyMode,
                        certFile = self.sslSettings.certFile,
                        keyFile = self.sslSettings.keyFile)

                    wrapConnectedSocket(sslContext, client,
                        SslHandshakeType.handshakeAsServer, &"{host}:{port}")

                    asyncCheck self.clientListener(client, callback)

                except Exception as ex:
                    # show debug
                    if self.debug:
                        asyncCheck dbg(proc () =
                            echo ""
                            echo "#== start"
                            echo "Failed to serve."
                            echo ex.msg
                            echo "#== end"
                            echo "")

# serve the server
# will have secure and unsecure connection if SslSettings given
proc serve*(
    self: ZFBlast,
    callback: proc (ctx: HttpContext): Future[void]): Future[void] {.async.} =

    asyncCheck self.doServe(callback)
    when defineSsl:
        asyncCheck self.doServeSecure(callback)
    runForever()

# create zfblast server with initial settings
# default value debug is off
# set debug to true if want to trace the data process
proc newZFBlast*(
    address: string,
    port: Port = Port(8000),
    debug: bool = false,
    reuseAddress: bool = true,
    reusePort:bool = false,
    sslSettings: SslSettings = nil,
    maxBodyLength: int = 268435456,
    keepAliveMax: int = 20,
    keepAliveTimeout: int = 10): ZFBlast =

    var instance = ZFBlast(
        port: port,
        address: address,
        debug: debug,
        sslSettings: sslSettings,
        reuseAddress: reuseAddress,
        reusePort: reusePort,
        maxBodyLength: maxBodyLength,
        keepAliveTimeout: keepAliveTimeout,
        keepAliveMax: keepAliveMax)

    # show debugging output
    if debug:
        asyncCheck dbg(proc () =
            echo ""
            echo "#== start"
            echo "Initialize ZFBlast"
            echo &"Bind address    : {address}"
            echo &"Port            : {port}"
            echo &"Debug           : {debug}"
            echo &"Reuse address   : {reuseAddress}"
            echo &"Reuse port      : {reusePort}"
            if isNil(sslSettings):
                echo &"Ssl             : {false}"
            else:
                echo &"Ssl             : {true}"
                echo &"Ssl Cert        : {sslSettings.certFile}"
                echo &"Ssl Key         : {sslSettings.keyFile}"
                echo &"Ssl Verify Peer : {sslSettings.verify}"
            echo "#== end"
            echo "")

    instance.setupServer

    return instance
###

# test server
if isMainModule:
    #[
    let zfb = newZFBlast(
        "0.0.0.0",
        Port(8000),
        debug = true,
        sslSettings = newSslSettings(
            certFile = joinPath("ssl", "certificate.pem"),
            keyFile = joinPath("ssl", "key.pem"),
            verify = false,
            port = Port(8443)
        ))
    ]#

    let zfb = newZFBlast(
        "0.0.0.0",
        Port(8000),
        debug = true)

    waitfor zfb.serve(proc (ctx: HttpContext): Future[void] {.async.} =
        case ctx.request.url.getPath
        # http(s)://localhost
        of "/":
            ctx.response.httpCode = Http200
            ctx.response.headers.add("Content-Type", "text/plain")
            ctx.response.body = "Halo"
        of "/secureflag":
            # is secure flag, the idea from qbradley
            # https://github.com/zendbit/nim.zfblast/commits?author=qbradley
            # the alternative we can check the client socket is ssl or not
            # if not ctx.client.isSsl:
            #   ctx.response.httpCode = Http301
            #   ctx.response.headers.add("Location", "https://127.0.0.1:8443")
            #   ctx.response.body = "Use secure website only"
            # also we can check the flag as qbradley request
            if not ctx.isSecure:
                ctx.response.httpCode = Http301
                ctx.response.headers.add("Location", "https://127.0.0.1:8443")
                ctx.response.body = "Use secure website only"
        # http(s)://localhost/secureflag
        of "/home":
            ctx.response.httpCode = Http200
            ctx.response.headers.add("Content-Type", "text/html")
            ctx.response.body = "<html><body>Hello</body></html>"
        # http(s)://localhost/api/home
        of "/api/home":
            ctx.response.httpCode = Http200
            ctx.response.headers.add("Content-Type", "application/json")
            ctx.response.body = """{"version" : "0.1.0"}"""
        # will return 404 not found if route not defined
        else:
            ctx.response.httpCode = Http404
            ctx.response.body = "not found"

        await ctx.resp
    )

export
    asyncnet,
    asyncdispatch,
    os,
    net,
    strformat,
    strutils,
    httpcore,
    uri3,
    streams,
    times,
    nativesockets,
    Request,
    Response,
    HttpContext,
    SslSettings,
    ZFBlast

