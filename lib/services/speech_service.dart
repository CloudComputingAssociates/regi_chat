import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Wraps the speech_to_text package and surfaces any failures via an
/// [errors] stream. Status events are surfaced too so callers can show
/// "listening / not listening / done" if useful.
class SpeechService {
  SpeechService();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  StreamController<String>? _transcripts;
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  final StreamController<String> _statuses =
      StreamController<String>.broadcast();

  bool get isAvailable => _speech.isAvailable;

  /// Emits human-readable error messages whenever STT init or recognition
  /// fails. Caller surfaces these in the chat output as debug lines.
  Stream<String> get errors => _errors.stream;

  /// Emits status updates ('listening', 'notListening', 'done', etc.).
  Stream<String> get statuses => _statuses.stream;

  Future<bool> initialize() async {
    if (_initialized) return _speech.isAvailable;
    try {
      _initialized = await _speech.initialize(
        onStatus: (s) {
          if (!_statuses.isClosed) _statuses.add(s);
        },
        onError: (e) {
          if (!_errors.isClosed) _errors.add(e.errorMsg);
        },
      );
    } catch (e) {
      _errors.add('initialize threw: $e');
      _initialized = false;
    }
    if (!_initialized) {
      _errors.add('initialize returned false (mic permission? https? '
          'browser support? speech_to_text says isAvailable=${_speech.isAvailable})');
    }
    return _initialized;
  }

  /// Begins listening; emits partial + final transcripts as they arrive.
  Stream<String> listen() {
    _transcripts?.close();
    final controller = StreamController<String>.broadcast();
    _transcripts = controller;

    try {
      _speech.listen(
        onResult: (result) {
          if (controller.isClosed) return;
          controller.add(result.recognizedWords);
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      _errors.add('listen threw: $e');
    }
    return controller.stream;
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (e) {
      _errors.add('stop threw: $e');
    }
    await _transcripts?.close();
    _transcripts = null;
  }

  void dispose() {
    _transcripts?.close();
    _errors.close();
    _statuses.close();
  }
}
