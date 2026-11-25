# Classic (blocking) HTTP/1.1 connections terminate a chunked message whose body was never fully written

Module: `httpcore5`, classic I/O connections (`org.apache.hc.core5.http.impl.io`).

## Observed

When a message is sent with `Transfer-Encoding: chunked` through the blocking connection classes and the
entity cannot be written completely, the bytes on the wire still end with the last-chunk marker
(`0\r\n\r\n`). The peer therefore sees a well-formed, *complete* chunked message that is in fact truncated,
and the connection stays open as if nothing had happened, so it can be reused or kept alive.

This happens in two situations:

1. **The entity fails while it is being written** (client request or server response). For example the
   entity copies from a source stream that throws an `IOException` (say an `EOFException`) half way through:

   ```java
   // client side, conn is a DefaultBHttpClientConnection bound to a socket
   ClassicHttpRequest request = new BasicClassicHttpRequest(Method.POST, "/stuff");
   request.addHeader("Transfer-Encoding", "chunked");
   request.setEntity(entityWhoseWriteToWritesSomeBytesAndThenThrowsEOFException);
   conn.sendRequestHeader(request);
   conn.sendRequestEntity(request);   // throws the EOFException, as it should
   ```

   After the exception the socket output ends with the partial body followed by a regular terminating
   chunk (`0\r\n\r\n`), `conn.isOpen()` is still `true` and the client connection still reports
   `isConsistent() == true`. The same is observed with `DefaultBHttpServerConnection#sendResponseEntity` for
   a chunked response whose entity fails: the truncated response is terminated cleanly and the connection
   remains open.

2. **The client stops sending the request body because the server answered early** (the configured
   `ResponseOutOfOrderStrategy` reports an early response while a chunked request entity is being written,
   e.g. the server replied `400 Bad Request` before the body was sent). Sending the entity returns without an
   exception, which is right, but the connection still reports `isConsistent() == true`, although a chunked
   request body was abandoned mid-message and the stream is closed as if the body had been finished. (For a
   request with a `Content-Length` body the connection is correctly reported as inconsistent.)

## Expected

- A chunked message whose entity was not written completely must never be finished with the terminating
  chunk; the peer must be able to tell that the message is incomplete.
- If writing the entity fails, the original exception still propagates to the caller, and the connection is
  no longer usable: it is closed (`isOpen()` is `false`) and, on the client side, flagged as inconsistent.
- If the client abandons a chunked (or otherwise non-empty) request body because of an early response, no
  exception is thrown, the connection stays open so the early response can still be read from it
  (`receiveResponseHeader()` returns the `400`), no terminating chunk is written, and the connection reports
  `isConsistent() == false` so that it is not reused.
- Messages whose entity is written completely behave exactly as before.
