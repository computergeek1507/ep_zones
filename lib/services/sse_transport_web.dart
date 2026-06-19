import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'sse_transport.dart';

// Browser EventSource cannot set request headers, so the openHAB API token is
// appended as an `?accessToken=` query parameter instead.
bool get sseSupportsAuthHeader => false;

Future<SseConnection> openSse(String url, {String? bearerToken}) async {
  var u = url;
  if (bearerToken != null && bearerToken.isNotEmpty) {
    final sep = u.contains('?') ? '&' : '?';
    u = '$u${sep}accessToken=${Uri.encodeComponent(bearerToken)}';
  }
  return _WebSseConnection(web.EventSource(u));
}

class _WebSseConnection implements SseConnection {
  final web.EventSource _es;
  final _out = StreamController<String>();
  late final JSFunction _onMsg;
  late final JSFunction _onErr;

  _WebSseConnection(this._es) {
    _onMsg = ((web.MessageEvent e) {
      final data = e.data;
      if (data != null && data.isA<JSString>()) {
        _out.add((data as JSString).toDart);
      }
    }).toJS;
    _onErr = ((web.Event _) {
      if (!_out.isClosed) _out.addError('SSE connection error');
    }).toJS;
    _es.addEventListener('message', _onMsg);
    _es.addEventListener('error', _onErr);
  }

  @override
  Stream<String> get dataEvents => _out.stream;

  @override
  void close() {
    _es.removeEventListener('message', _onMsg);
    _es.removeEventListener('error', _onErr);
    _es.close();
    if (!_out.isClosed) _out.close();
  }
}
