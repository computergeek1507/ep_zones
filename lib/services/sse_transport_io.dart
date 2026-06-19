import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sse_transport.dart';

bool get sseSupportsAuthHeader => true;

Future<SseConnection> openSse(String url, {String? bearerToken}) async {
  final client = http.Client();
  final request = http.Request('GET', Uri.parse(url));
  request.headers['Accept'] = 'text/event-stream';
  request.headers['Cache-Control'] = 'no-cache';
  if (bearerToken != null && bearerToken.isNotEmpty) {
    request.headers['Authorization'] = 'Bearer $bearerToken';
  }
  final response = await client.send(request);
  if (response.statusCode != 200) {
    client.close();
    throw http.ClientException(
        'SSE connect failed: HTTP ${response.statusCode}', Uri.parse(url));
  }
  return _IoSseConnection(client, response);
}

class _IoSseConnection implements SseConnection {
  final http.Client _client;
  final http.StreamedResponse _response;
  final _out = StreamController<String>();
  final _buffer = StringBuffer();
  StreamSubscription<String>? _sub;

  _IoSseConnection(this._client, this._response) {
    _sub = _response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: _out.addError, onDone: _out.close);
  }

  void _onLine(String line) {
    if (line.isEmpty) {
      // End of one event: flush accumulated data.
      final data = _buffer.toString();
      _buffer.clear();
      if (data.isNotEmpty) _out.add(data);
      return;
    }
    if (line.startsWith('data:')) {
      var v = line.substring(5);
      if (v.startsWith(' ')) v = v.substring(1);
      if (_buffer.isNotEmpty) _buffer.write('\n');
      _buffer.write(v);
    }
    // Ignore other SSE fields (event:, id:, retry:, comments).
  }

  @override
  Stream<String> get dataEvents => _out.stream;

  @override
  void close() {
    _sub?.cancel();
    _client.close();
    if (!_out.isClosed) _out.close();
  }
}
