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
import nativesockets, strutils, os, base64, math, streams, net, threadpool, locks, sequtils, times
export nativesockets, strutils, os, base64, math, streams, net

import httpcontext, websocket, constants
export httpcontext, websocket, constants

type
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
    # trace mode
    trace*: bool
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
    server: Socket
    # serve secure (https)
    sslServer: Socket
    # max body length server can handle
    # can be vary on seting
    # value in bytes
    maxBodyLength*: int
    tmpDir*: string
    readBodyBuffer*: int
    tmpBodyDir*: string

  ClientsPool = object
    clients: seq[tuple[client: Socket, callback: proc (ctx: HttpContext) {.gcsafe.}]]
    clientsInProcess: seq[tuple[client: Socket, callback: proc (ctx: HttpContext) {.gcsafe.}]]
    clientsSecure: seq[tuple[client: Socket, callback: proc (ctx: HttpContext) {.gcsafe.}]]
    clientsSecureInProcess: seq[tuple[client: Socket, callback: proc (ctx: HttpContext) {.gcsafe.}]]
    workerThreadsCount: int

var clientsPool: ptr ClientsPool
var lock: Lock

proc trace*(cb: proc ():void {.gcsafe.}) {.gcsafe.} =
  if not isNil(cb):
    try:
      cb()

    except Exception as ex:
      echo ex.msg

proc getHttpHeaderValues*(httpHeaders: HttpHeaders, key: string): HttpHeaderValues =
  var headers: HttpHeaderValues = httpHeaders.getOrDefault(key)
  if headers == "":
    return httpHeaders.getOrDefault(key.toLower())

  return headers

#[
    SslSettings type procedures
]#
proc newSslSettings*(
  certFile: string,
  keyFile: string,
  port: Port = Port(8443),
  verify: bool = false): SslSettings {.gcsafe.} =

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
    self.server = newSocket()

  # init https server socket
  when WITH_SSL:
    if not self.sslSettings.isNil and
      self.sslServer.isNil:
      if not self.sslSettings.certFile.fileExists:
        echo "Certificate not found " & self.sslSettings.certFile
      elif not fileExists(self.sslSettings.keyFile):
        echo "Private key not found " & self.sslSettings.keyFile
      else:
        self.sslServer = newSocket()

proc isKeepAlive(
  self: ZFBlast,
  httpContext: HttpContext): bool =

  let keepAliveHeader =
    httpContext.request.headers.getHttpHeaderValues("Connection")
  if keepAliveHeader != "":
    if keepAliveHeader.toLower().find("close") == -1 and
      keepAliveHeader.toLower().find("keep-alive") != -1:
      return true

  return false

# send response to the client
proc send*(
  self: ZFBlast,
  httpContext: HttpContext) {.gcsafe.} =

  let client = httpContext.client
  let request = httpContext.request
  let response = httpContext.response

  var contentBody: string = ""
  let isKeepAlive = self.isKeepAlive(httpContext)

  var headers = ""
  headers &= &"{HTTP_VER} {response.httpCode}{CRLF}"
  headers &= &"Server: {SERVER_ID} {SERVER_VER}{CRLF}"
  headers &= "Date: " &
    now().utc().format("ddd, dd MMM yyyy HH:mm:ss".initTimeFormat) & &" GMT{CRLF}"

  if isKeepAlive:
    if response.headers.getHttpHeaderValues("Connection") == "":
      headers &= &"Connection: keep-alive{CRLF}"

    if response.headers.getHttpHeaderValues("Keep-Alive") == "":
      headers &= "Keep-Alive: " &
        &"timeout={httpContext.keepAliveTimeout}" &
        &", max={httpContext.keepAliveMax}{CRLF}"

  else:
    headers &= &"Connection: close{CRLF}"

  contentBody = response.body

  if response.headers.getHttpHeaderValues("Content-Length") == "":
    headers &= &"Content-Length: {contentBody.len}{CRLF}"

  for k, v in response.headers.pairs:
    headers &= &"{k}: {v}{CRLF}"

  headers &= CRLF

  try:
    if not client.isNil:
      if request.httpMethod == HttpHead:
        client.send(headers)
      else:
        client.send(headers & contentBody)
  except Exception:
    discard
  
  if not isKeepAlive and not client.isNil:
    client.close

  # clean up all string stream request and response
  httpContext.clear()

# handle websocket client
proc webSocketHandler(
  self: ZFBlast,
  httpContext: HttpContext,
  callback: proc (ctx: HttpContext) {.gcsafe.}) {.gcsafe.} =

  let client = httpContext.client
  let webSocket = httpContext.webSocket
  webSocket.client = client
  webSocket.handShakeReqHeaders = httpContext.request.headers

  case webSocket.state
  of WSState.Open:
    # if web socket
    # then handle the message and the connection
    # the fin = 1 indicate that the message from the client already sent
    # but if fin = 0 indicate that the message has another part until fin = 1

    # get the first 2 byte and define
    # fin flag (1 bit)
    # rsv 1 - rsv 3 (1 bit each)
    # opcode (4 bit)
    # mask flag (1 bit), 1 meaning message is masked
    # payload length (7 bit)

    # set default status code to Ok
    webSocket.statusCode = WSStatusCode.Ok
    let frame = WSFrame()
    # set websocket input frame
    httpContext.webSocket.inFrame = frame

    # get header first 2 bytes
    let header = client.recv(2)
    # make sure header containt 2 bytes (string with len 2)
    if header.len == 2 and header.strip() != "":
      # parse the headers frame
      frame.parseHeaders(header)

      if frame.payloadLen == 0x7e:
        # if payload len 126 (0x7e)
        # get the length of the data from the
        # next 2 bytes
        # get extended payload length next 2 bytes
        frame.parsePayloadLen(client.recv(2))

      elif frame.payloadLen == 0x7f:
        # if payload len 127 (0x7f)
        # get the length of the data from the
        # next 8 bytes
        # get extended payload length next 8 bytes
        frame.parsePayloadLen(client.recv(8))

      # check if the payload len is not larget than allowed max
      # max is maxBodyLength
      if frame.payloadLen <= self.maxBodyLength.uint64:
        # if payloadLen larget than max int then
        # send error and

        # if isMasked then get the mask key
        # next 4 bytes (uint32)
        if frame.mask != 0x0:
          frame.maskKey = client.recv(4)

        # get payload data
        if frame.payloadLen != 0:
          # asyncnet .recv(int32) only accept int32
          # payloadLen is uint64, we need to retrieve in part of int32
          frame.payloadData = ""
          var retrieveCount = (frame.payloadLen div high(int32).uint64).uint64
          if retrieveCount == 0:
            frame.payloadData = client.recv(frame.payloadLen.int32)

          else:
            let restToRetrieve = frame.payloadLen mod high(int32).uint64
            for i in 0..retrieveCount:
              frame.payloadData &= client.recv(high(int32))

            if restToRetrieve != 0:
              frame.payloadData &= client.recv(restToRetrieve.int32)

      else:
        webSocket.state = WSState.Close
        webSocket.statusCode = WSStatusCode.PayloadToBig
        client.close

    case frame.opCode
    of WSOpCode.Ping.uint8:
      # response the ping with same message buat change the opcode to pong
      webSocket.outFrame = deepCopy(webSocket.inFrame)
      webSocket.outFrame.opCode = WSOpCode.Pong.uint8
      webSocket.send()
      # if ping dont call the callback
      return

    of WSOpCode.Pong.uint8:
      # check if pong message same with socket hash id
      if frame.encodeDecode() != webSocket.hashId:
        # close the connection if not valid
        webSocket.state = WSState.Close
        webSocket.statusCode = WSStatusCode.Refused
        client.close
      else:
        # if valid just return and wait next message
        return

    of WSOpCode.ConnectionClose.uint8:
      webSocket.state = WSState.Close
      webSocket.statusCode = WSStatusCode.GoingAway
      client.close

    else:
      # show trace
      if self.trace:
        trace proc (): void {.gcsafe.} =
          echo ""
          echo "#== start"
          echo "Websocket opcode not handled."
          echo frame.opCode
          echo "#== end"
          echo ""

  else:
    discard

  # call callback
  # on data received
  if not callback.isNil:
    httpContext.callback

    # if State handshake
    # then send header handshake
    # send ping
    # set state to open
    if webSocket.state == WSState.HandShake:
      # do handshake process
      let handshakeKey =
        httpContext.request.headers.getHttpHeaderValues("Sec-WebSocket-Key")
        .strip()

      webSocket.handShake(handshakeKey)

      # send ping after handshake
      webSocket.state = WSState.Open
      webSocket.statusCode = WSStatusCode.Ok

      # send ping with hashId
      # make sure the connection is created
      webSocket.outFrame = newWSFrame(
        webSocket.hashId,
        1,
        WSOpCode.Ping.uint8)
      webSocket.send()

# handle client connections
proc clientHandler(
  self: ZFBlast,
  httpContext: HttpContext,
  callback: proc (ctx: HttpContext) {.gcsafe.}) {.gcsafe.} =

  let client = httpContext.client

  var isRequestHeaderValid = true
  # only parse the header if websocket not initilaized
  # if nitialized indicate that websicket already connected
  if httpContext.webSocket.isNil:
    let line = client.recvLine()
    if line == "":
      client.close
      return

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
        isRequestHeaderValid = false

      if isRequestHeaderValid:
        var protocol = "http"
        if client.isSsl:
            protocol = "https"

        let (address, port) = client.getLocalAddr
        httpContext.request.url = parseUri3(reqParts[1])
        httpContext.request.url.setScheme(protocol)
        httpContext.request.url.setDomain(address)
        httpContext.request.url.setPort($port)
        httpContext.request.httpVersion = reqParts[2]

    else:
      isRequestHeaderValid = false

  else:
    isRequestHeaderValid = false

  # parse general header
  while isRequestHeaderValid:
    let line = client.recvLine()
    # pull reqeust @@ -430,11 +430,8 @@ proc clientHandler(
    # qbradley
    # https://github.com/zendbit/nim.zfblast/commits?author=qbradley
    let headers = line.strip().parseHeader
    let headerKey = headers.key.strip()
    let headerValue = headers.value
    if headerKey != "" and headerValue.len != 0:
      httpContext.request.headers[headerKey] = headerValue
      if headerKey.toLower() == "host":
        httpContext.request.url.setDomain(headerValue.join(", ").split(":")[0])

      # if header key containts upgrade websocket then the request is websocket
      # websocket only accept get method
      if headerKey.toLower() == "upgrade" and
        join(headerValue, ", ").toLower().find("websocket") != -1 and
        httpContext.request.httpMethod == HttpGet:
        if httpContext.request.url.getScheme() == "http":
          httpContext.request.url.setScheme("ws")

        else:
          httpContext.request.url.setScheme("wss")

        httpContext.webSocket = newWebSocket(
          client = client,
          state = WSState.HandShake)

    if line == CRLF:
      break

  var isErrorBodyContent = false
  # parse body
  if isRequestHeaderValid and
    httpContext.request.httpMethod in [HttpPost, HttpPut, HttpPatch]:

    #httpContext.request.body.writeLine(line)
    let contentLength =
      httpContext.request.headers.getHttpHeaderValues("content-length")

    # check body content
    if contentLength != "":
      let bodyLen = contentLength.parseInt

      # if body content larger than server can handle
      # return 413 code
      if bodyLen > self.maxBodyLength:
          httpContext.response.httpCode = Http413
          httpContext.response.body = &"request larger than {bodyLen div (1024*1024)} MB not allowed."
          isErrorBodyContent = true
      else:
        # if request len is less or equals just save the body
        let bodyCache = self.tmpBodyDir.joinPath(now().utc().format("yyyy-MM-dd HH:mm:ss:fffffffff".initTimeFormat).encode)
        let writeBody = bodyCache.newFileStream(fmWrite)
        if bodyLen <= self.readBodyBuffer:
          #httpContext.request.body = client.recv(bodyLen)
          writeBody.write(client.recv(bodyLen))
        else:
          let remainBodyLen = bodyLen mod self.readBodyBuffer
          let toBuff = floor(bodyLen/self.readBodyBuffer).int
          for i in 1..toBuff:
            #httpContext.request.body &= client.recv(self.readBodyBuffer)
            writeBody.write(client.recv(self.readBodyBuffer))
          if remainBodyLen != 0:
            #httpContext.request.body &= client.recv(remainBodyLen)
            writeBody.write(client.recv(remainBodyLen))

        writeBody.close
        if bodyCache.existsFile:
          httpContext.request.body = bodyCache

    else:
      httpContext.response.httpCode = Http411

  # call the callback
  if not isErrorBodyContent:
    if isRequestHeaderValid and httpContext.webSocket.isNil:
      # if header valid and not web socket
      if not callback.isNil:
        httpContext.callback

    # if websocket and already handshake
    elif not httpContext.webSocket.isNil:
      self.webSocketHandler(httpContext, callback)

  elif not httpContext.client.isNil:
    self.send(httpContext)

# handle client listener
# will listen until the client socket closed
proc clientListener(
  self: ZFBlast,
  client: Socket,
  callback: proc (ctx: HttpContext) {.gcsafe.}) {.gcsafe.} =

  try:
    # setup http context
    #let (clientHost, clientPort) = client.getPeerAddr
    let httpContext = newHttpContext(
      client = client,
      keepAliveTimeout = self.keepAliveTimeout,
      keepAliveMax = self.keepAliveMax)

    httpContext.send = proc (ctx: HttpContext) {.gcsafe.} =
      self.send(ctx)

    while not client.isNil:
      self.clientHandler(httpContext, callback)

    #lock.withLock:
    #  clientsPool.workerThreadsCount.dec

  except Exception as ex:
    # show trace
    if self.trace:
      trace proc (): void {.gcsafe.} =
        echo ""
        echo "#== start"
        echo "Client connection closed, accept new session."
        echo ex.msg
        echo "#== end"
        echo ""

  clientsPool.workerThreadsCount -= 1

proc startClientsPool(self: ZFBlast) {.gcsafe.} =
  #
  # start client pooling process
  # get client from its pool
  #
  while true:
    lock.withLock:
      # only spawn process if worker threads meet with limitation
      if clientsPool.workerThreadsCount < MaxThreadPoolSize - 6:
        # handle non secure request
        if clientsPool.clientsInProcess.len != 0:
          spawn self.clientListener(
            clientsPool.clientsInProcess[0].client.deepCopy,
            clientsPool.clientsInProcess[0].callback.deepCopy)
          clientsPool.clientsInProcess.delete(0)
          clientsPool.workerThreadsCount += 1

        # handle secure request
        if clientsPool.clientsSecureInProcess.len != 0:
          spawn self.clientListener(
            clientsPool.clientsSecureInProcess[0].client.deepCopy,
            clientsPool.clientsSecureInProcess[0].callback.deepCopy)
          clientsPool.clientsSecureInProcess.delete(0)
          clientsPool.workerThreadsCount += 1

proc doServe(
  self: ZFBlast,
  callback: proc (ctx: HttpContext) {.gcsafe.}) {.gcsafe.} =

  if not self.server.isNil:
    self.server.setSockOpt(OptReuseAddr, self.reuseAddress)
    self.server.setSockOpt(OptReusePort, self.reusePort)
    self.server.bindAddr(self.port, self.address)
    self.server.listen

    let (host, port) = self.server.getLocalAddr
    echo &"Listening non secure (plain) on http://{host}:{port}"

    while true:
      try:
        lock.withLock:
          if clientsPool.clientsInProcess.len == 0 and clientsPool.clients.len != 0: 
            clientsPool.clientsInProcess = clientsPool.clientsInProcess & clientsPool.clients.deepCopy
            clientsPool.clients.delete(0, clientsPool.clients.high)
        
        var client: Socket
        self.server.accept(client)
        clientsPool.clients.add((client.deepCopy, callback.deepCopy))

      except Exception as ex:
        # show trace
        if self.trace:
          trace proc (): void {.gcsafe.} =
            echo ""
            echo "#== start"
            echo "Failed to serve."
            echo ex.msg
            echo "#== end"
            echo ""

# serve secure connection (https)
when WITH_SSL:
  proc doServeSecure(
    self: ZFBlast,
    callback: proc (ctx: HttpContext) {.gcsafe.}) {.gcsafe.} =

    if not self.sslServer.isNil:
      self.sslServer.setSockOpt(OptReuseAddr, self.reuseAddress)
      self.sslServer.setSockOpt(OptReusePort, self.reusePort)
      self.sslServer.bindAddr(self.sslSettings.port, self.address)
      self.sslServer.listen

      let (host, port) = self.sslServer.getLocalAddr
      echo &"Listening secure on https://{host}:{port}"

      while true:
        try:
          lock.withLock:
            if clientsPool.clientsSecureInProcess.len == 0 and clientsPool.clientsSecure.len != 0:
              clientsPool.clientsSecureInProcess = clientsPool.clientsSecureInProcess & clientsPool.clientsSecure.deepCopy
              clientsPool.clientsSecure.delete(0, clientsPool.clientsSecure.high)

          var client: Socket
          self.sslServer.accept(client)
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

          clientsPool.clientsSecure.add((client.deepCopy, callback.deepCopy))

        except Exception as ex:
          # show trace
          if self.trace:
            trace proc (): void {.gcsafe.} =
              echo ""
              echo "#== start"
              echo "Failed to serve."
              echo ex.msg
              echo "#== end"
              echo ""

# serve the server
# will have secure and unsecure connection if SslSettings given
proc serve*(
  self: ZFBlast,
  callback: proc (ctx: HttpContext) {.gcsafe.}) {.gcsafe.} =

  clientsPool = cast[ptr ClientsPool](alloc0(sizeof(ClientsPool)))
  lock.initLock

  spawn self.doServe(callback)
  when WITH_SSL:
    spawn self.doServeSecure(callback)

  self.startClientsPool()

# create zfblast server with initial settings
# default value trace is off
# set trace to true if want to trace the data process
proc newZFBlast*(
  address: string,
  port: Port = Port(8000),
  trace: bool = false,
  reuseAddress: bool = true,
  reusePort:bool = false,
  sslSettings: SslSettings = nil,
  maxBodyLength: int = 268435456,
  keepAliveMax: int = 20,
  keepAliveTimeout: int = 10,
  tmpDir: string = getAppDir().joinPath(".tmp"),
  tmpBodyDir: string = getAppDir().joinPath(".tmp", "body"),
  readBodyBuffer: int = 1024): ZFBlast {.gcsafe.} =

  var instance = ZFBlast(
    port: port,
    address: address,
    trace: trace,
    sslSettings: sslSettings,
    reuseAddress: reuseAddress,
    reusePort: reusePort,
    maxBodyLength: maxBodyLength,
    keepAliveTimeout: keepAliveTimeout,
    keepAliveMax: keepAliveMax,
    tmpDir: tmpDir,
    readBodyBuffer: readBodyBuffer,
    tmpBodyDir: tmpBodyDir)

  if not instance.tmpBodyDir.existsDir:
    instance.tmpBodyDir.createDir

  # show traceging output
  if trace:
    trace proc (): void {.gcsafe.} =
      echo ""
      echo "#== start"
      echo "Initialize ZFBlast"
      echo &"Bind address    : {address}"
      echo &"Port            : {port}"
      echo &"Debug           : {trace}"
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
      echo ""

  instance.setupServer

  return instance
###

# test server
if isMainModule:
  #[
  let zfb = newZFBlast(
    "0.0.0.0",
    Port(8000),
    trace = true,
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
    trace = true)

  zfb.serve(proc (ctx: HttpContext) {.gcsafe.} =
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
      if not ctx.client.isSsl:
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

    ctx.resp
  )

