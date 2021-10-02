About
=====

High performance http server (https://tools.ietf.org/html/rfc2616) with persistent connection for nim language.
Serving in 1-2 miliseconds for persistent connection.

read persistent connection RFC (https://tools.ietf.org/html/rfc2616)

From version 0.1.6 already support websocket
***Support websocket*** RFC (https://tools.ietf.org/html/rfc6455)

Nimble installation
===================

```
nimble install zfblast@#head
```

Examples
========

```
need to compiled with -d:ssl and make sure openssl installed
```

```nim
import zfblast/server

let zfb = newZFBlast(
    "0.0.0.0",
    Port(8000),
    # default value for debug is false
    # if want to know about tracing the data process set to true
    debug = false,
    sslSettings = newSslSettings(
        certFile = joinPath("ssl", "certificate.pem"),
        keyFile = joinPath("ssl", "key.pem"),
        #verifyMode = SslCVerifyMode.CVerifyNone,
        #changed verifyMode to verify
        verify = false,
        port = Port(8443)
    ))
    
waitfor zfb.serve(proc (ctx: HttpContext): Future[void] {.async.} =
    case ctx.request.url.getPath
    # web socket example
    # ws(s)://localhost/ws
    of "/ws":
        let ws = ctx.webSocket
        if not isNil(ws):
            case ws.state:
            of WSState.HandShake:
                echo "HandShake state"
                # this state will evaluate
                # right before handshake process
                # in here we can add the additionals response headers
                # normaly we can skip this step
                # about the handshake:
                # handshake is using http headers
                # this process is only happen 1 time
                # after handshake success then the protocol will be switch to the websocket
                # you can check the handshake header request in
                # -> ws.handShakeReqHeaders this is the HtttpHeaders type
                # and you also can add the additional headers information in the response handshake
                # by adding the:
                # -> ws.handShakeResHeaders
            of WSState.Open:
                echo "Open state"
                # in this state all swaping process will accur
                # like send or received message
                case ws.statusCode:
                of WSStatusCode.Ok:
                    case ws.inFrame.opCode:
                    of WSOpCode.TextFrame.uint8:
                        echo "Text frame received"
                        echo &"Fin {ws.inFrame.fin}"
                        echo &"Rsv1 {ws.inFrame.rsv1}"
                        echo &"Rsv2 {ws.inFrame.rsv2}"
                        echo &"Rsv3 {ws.inFrame.rsv3}"
                        echo &"OpCode {ws.inFrame.opCode}"
                        echo &"Mask {ws.inFrame.mask}"
                        echo &"Mask Key {ws.inFrame.maskKey}"
                        echo &"PayloadData {ws.inFrame.payloadData}"
                        echo &"PayloadLen {ws.inFrame.payloadLen}"

                        # how to show decoded data
                        # we can use the encodeDecode
                        echo ""
                        echo "Received data (decoded):"
                        echo ws.inFrame.encodeDecode()

                        # let send the data to the client
                        # set fin to 1 if this is independent message
                        # 1 meaning for read and finish
                        # if you want to use continues frame
                        # set it to 0
                        # for more information about web socket frame and protocol
                        # refer to the web socket documentation ro the RFC document
                        #
                        # WSOpCodeEnum:
                        # WSOpCode* = enum
                        #    ContinuationFrame = 0x0
                        #    TextFrame = 0x1
                        #    BinaryFrame = 0x2
                        #    ConnectionClose = 0x8
                        ws.outFrame = newWSFrame(
                            1,
                            WSOpCode.TextFrame.uint8,
                            "This is from the endpoint :-)")

                        await ws.send()

                    of WSOpCode.BinaryFrame.uint8:
                        echo "Binary frame received"

                    of WSOpCode.ContinuationFrame.uint8:
                        # the frame continues from previous frame
                        echo "Continuation frame received"

                    of WSOpCode.ConnectionClose.uint8:
                        echo "Connection close frame received"

                    else:
                        discard
                else:
                    echo &"Failed status code {ws.statusCode}"

            of WSState.Close:
                echo "Close state"
                # this state will execute if the connection close
    # http(s)://localhost
    of "/":
        ctx.response.httpCode = Http200
        ctx.response.headers.add("Content-Type", "text/plain")
        # make sure index.html file exist
        ctx.response.body = newFileStream("index.html").readAll()
    # http(s)://localhost/home
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
            
    of "/home":
        ctx.response.httpCode = Http200
        ctx.response.headers.add("Content-Type", "text/html")
        # make sure index.html file exist
        ctx.response.body = newFileStream("index.html").readAll()
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
```
