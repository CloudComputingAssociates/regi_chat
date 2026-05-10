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

/// One parsed event from the SSE stream of `POST /ai/chat/stream`.
/// Mirrors regi-api's `models.StreamEvent` ([regi-api/models/ai.go]).
///
/// Any field can be null on a given event:
///   - content events: delta + sessionId
///   - done events:    sessionId, sessionStatus, tokensRemaining
///   - error events:   error + sessionId
class ChatStreamChunk {
  const ChatStreamChunk({
    this.type,
    this.delta,
    this.sessionId,
    this.sessionStatus,
    this.tokensRemaining,
    this.contextWarning,
    this.error,
  });

  final String? type;
  final String? delta;
  final String? sessionId;
  final String? sessionStatus;
  final int? tokensRemaining;
  final String? contextWarning;
  final String? error;

  bool get hasError => error != null && error!.isNotEmpty;
  bool get hasDelta => delta != null && delta!.isNotEmpty;
}

class ChatService {
  ChatService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl => Config.apiBaseUrl;

  /// Streams parsed events from `POST {API_BASE_URL}/ai/chat/stream`.
  /// Caller appends [ChatStreamChunk.delta] to the visible message and
  /// captures [ChatStreamChunk.sessionId] to enable session continuity.
  Stream<ChatStreamChunk> streamChat({
    required String message,
    required String? sessionId,
    required String jwt,
  }) async* {
    if (_baseUrl.isEmpty) {
      throw ChatException(
        'API_BASE_URL missing — pass via --dart-define',
      );
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

      final chunk = _parseEvent(payload);
      if (chunk != null) yield chunk;
    }
  }

  ChatStreamChunk? _parseEvent(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        // Fallback: treat raw text as a content delta so a non-JSON server
        // still produces something visible.
        return ChatStreamChunk(delta: payload);
      }

      // Pull regi-api StreamEvent fields (models/ai.go):
      //   type, delta, content, sessionId, sessionStatus, tokensRemaining,
      //   contextWarning, error.
      final delta = decoded['delta'] as String? ??
          decoded['content'] as String? ??
          decoded['text'] as String?;

      // OpenAI-style nested envelope, in case some upstream uses it.
      String? nestedDelta;
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final inner = first['delta'];
          if (inner is Map<String, dynamic>) {
            final c = inner['content'];
            if (c is String) nestedDelta = c;
          }
        }
      }

      return ChatStreamChunk(
        type: decoded['type'] as String?,
        delta: delta ?? nestedDelta,
        sessionId: decoded['sessionId'] as String?,
        sessionStatus: decoded['sessionStatus'] as String?,
        tokensRemaining: decoded['tokensRemaining'] as int?,
        contextWarning: decoded['contextWarning'] as String?,
        error: decoded['error'] as String?,
      );
    } on FormatException {
      return ChatStreamChunk(delta: payload);
    }
  }

  /// Marks the server-side session as CLOSED via
  /// `DELETE /api/ai/chat/sessions/{sessionId}`. Best-effort — failures are
  /// swallowed because the visible UI has already moved on and the server
  /// will idle-time-out the session anyway.
  Future<void> closeSession({
    required String sessionId,
    required String jwt,
  }) async {
    if (_baseUrl.isEmpty || sessionId.isEmpty) return;
    try {
      await _client.delete(
        Uri.parse('$_baseUrl/ai/chat/sessions/$sessionId'),
        headers: {'Authorization': 'Bearer $jwt'},
      );
      // 204 on success, 404 if the session doesn't exist. Either is fine.
    } catch (_) {
      // Network error, 401, etc. Cleanup is best-effort by design.
    }
  }

  void dispose() {
    _client.close();
  }
}
