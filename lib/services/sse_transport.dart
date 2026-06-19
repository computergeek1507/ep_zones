/// Platform-split Server-Sent-Events transport.
///
/// io/desktop/mobile (`sse_transport_io.dart`) opens a streamed HTTP GET and
/// can set an Authorization header. Web (`sse_transport_web.dart`) uses the
/// browser EventSource, which cannot set headers — there the token must be
/// passed another way (query param) or polling is used instead.
///
/// Mirrors the conditional-import pattern used by fpp_view's discovery
/// transport (discovery_transport.dart + _io/_stub).
library;

import 'sse_transport_stub.dart'
    if (dart.library.io) 'sse_transport_io.dart'
    if (dart.library.js_interop) 'sse_transport_web.dart'
    as impl;

/// An open SSE connection emitting raw `data:` payloads (one per event).
abstract class SseConnection {
  Stream<String> get dataEvents;
  void close();
}

/// Opens an SSE connection to [url]. On platforms that support it, [bearerToken]
/// is sent as an Authorization header.
Future<SseConnection> openSse(String url, {String? bearerToken}) =>
    impl.openSse(url, bearerToken: bearerToken);

/// Whether this platform can attach an auth header to the SSE request.
bool get sseSupportsAuthHeader => impl.sseSupportsAuthHeader;
