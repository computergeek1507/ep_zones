import 'sse_transport.dart';

/// Fallback used when neither dart:io nor web is available. SSE is unsupported;
/// callers should fall back to polling.
bool get sseSupportsAuthHeader => false;

Future<SseConnection> openSse(String url, {String? bearerToken}) {
  throw UnsupportedError('SSE is not supported on this platform');
}
