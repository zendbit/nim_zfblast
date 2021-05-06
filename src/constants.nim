##
##  zfcore web framework for nim language
##  This framework if free to use and to modify
##  License: BSD
##  Author: Amru Rosyada
##  Email: amru.rosyada@gmail.com
##  Git: https://github.com/zendbit/nim.zfblast
##

const
  # http version header
  HTTP_VER* = "HTTP/1.1"
  # server header identifier
  SERVER_ID* = "ZFBlast (Nim)"
  # server build version
  SERVER_VER* = "V0.1.17"
  # CRLF header token
  CRLF* = "\c\L"
  # websocket magic string
  WS_MAGIC_STRING* = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

const WITH_SSL* = defined(ssl) or defined(nimdoc)
