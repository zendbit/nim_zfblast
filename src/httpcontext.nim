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

# std
import net, httpcore
export net, httpcore

# nimble
import uri3
export uri3

# local
import constants, websocket
export constants, websocket

type
  # Request type
  Request* = ref object of RootObj
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
  Response* = ref object of RootObj
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
    client*: Socket
    # Response type instance
    response*: Response
    # send response to client, this is bridge to ZFBlast send()
    send*: proc (ctx: HttpContext) {.gcsafe.}
    # Keep-Alive header max request with given persistent timeout
    # read RFC (https://tools.ietf.org/html/rfc2616)
    # section Keep-Alive and Connection
    # for improving response performance
    keepAliveMax*: int
    # Keep-Alive timeout
    keepAliveTimeout*: int
    # will true if connection is websocket
    webSocket*: WebSocket

#[
  Request type procedures
]#

proc newRequest*(
  httpMethod: HttpMethod = HttpGet,
  httpVersion: string = constants.HTTP_VER,
  url: Uri3 = parseUri3(""),
  headers: HttpHeaders = newHttpHeaders(),
  body: string = ""): Request {.gcsafe.} =
  # create new request
  # in general this will return Request instance with default value
  # and will be valued with request from client

  return Request(
    httpMethod: httpMethod,
    httpVersion: httpVersion,
    url: url,
    headers: headers,
    body: body)
###

#[
    Response type procedures
]#

proc newResponse*(
  httpCode: HttpCode = Http200,
  headers: HttpHeaders = newHttpHeaders(),
  body: string = ""): Response {.gcsafe.} =
  # create Response instance
  # in general this will valued with Response instance with default value

  return Response(
    httpCode: httpCode,
    headers: headers,
    body: body)
###

#[
  HttpContext type procedures
]#

proc newHttpContext*(
  client: Socket,
  request: Request = newRequest(),
  response: Response = newResponse(body = ""),
  keepAliveMax: int = 10,
  keepAliveTimeout: int = 20): HttpContext {.gcsafe.} =
  # create HttpContext instance
  # this will be the main HttpContext
  # will be contain:
  #  client -> is the asyncsocket of connected client
  #  request -> is the request from client
  #  response -> is the response from server
  #  keepAliveMax -> max request can handle by server on persistent connection
  #    default value is 20 persistent request per connection
  #  keepAliveTimeout -> keep alive timeout for persistent connection
  #    default value is 10 seconds

  return HttpContext(
    client: client,
    request: request,
    response: response,
    keepAliveMax: keepAliveMax,
    keepAliveTimeout: keepAliveTimeout)

proc resp*(self: HttpContext) {.gcsafe.} =
  # send response to client
  if not self.send.isNil:
    self.send(self)

proc clear*(self: HttpContext) {.gcsafe.} =
  # clear the context for next persistent connection
  self.request.body = ""
  self.response.body = ""
  clear(self.response.headers)
  clear(self.request.headers)
###
