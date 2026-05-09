import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class ChatException implements Exception {
  ChatException(this.message);
  final String message;
  @override
  String toString() => 'ChatException: $message';
}

class ChatService {
  ChatService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl => Config.apiBaseUrl;

  /// Streams response chunks from `POST {API_BASE_URL}/ai/chat/stream`.
  ///
  /// TODO: confirm wire format on first run. Current parser assumes SSE-style
  /// `data: {...}\n\n` lines with a JSON payload that contains a `delta` or
  /// `content` field. Falls back to yielding raw text if no recognised JSON
  /// envelope is present, so a NDJSON or plaintext server still produces
  /// something visible while we calibrate.
  Stream<String> streamChat({
    required String message,
    required String? sessionId,
    required String jwt,
  }) async* {
    if (_baseUrl.isEmpty) {
      throw ChatException('API_BASE_URL missing — check .env');
    }

    final request = http.Request('POST', Uri.parse('$_baseUrl/ai/chat/stream'));
    request.headers['Authorization'] = 'Bearer $jwt';
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode({'message': message, 'sessionId': sessionId});

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ChatException('${response.statusCode}: $body');
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty) continue;
      final payload = line.startsWith('data:') ? line.substring(5).trim() : line;
      if (payload == '[DONE]') break;

      final extracted = _extractText(payload);
      if (extracted != null && extracted.isNotEmpty) {
        yield extracted;
      }
    }
  }

  String? _extractText(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final delta = decoded['delta'] ?? decoded['content'] ?? decoded['text'];
        if (delta is String) return delta;
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, dynamic>) {
            final inner = first['delta'];
            if (inner is Map<String, dynamic>) {
              final c = inner['content'];
              if (c is String) return c;
            }
          }
        }
      }
      return null;
    } on FormatException {
      return payload;
    }
  }

  void dispose() {
    _client.close();
  }
}
