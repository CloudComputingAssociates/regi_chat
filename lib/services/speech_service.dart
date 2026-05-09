import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  SpeechService();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  StreamController<String>? _controller;

  bool get isAvailable => _speech.isAvailable;

  Future<bool> initialize() async {
    if (_initialized) return _speech.isAvailable;
    _initialized = await _speech.initialize(
      onStatus: (_) {},
      onError: (_) {},
    );
    return _initialized;
  }

  /// Begins listening; emits partial + final transcripts as they arrive.
  /// Caller should await `stop()` to release resources.
  Stream<String> listen() {
    _controller?.close();
    final controller = StreamController<String>.broadcast();
    _controller = controller;

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
    return controller.stream;
  }

  Future<void> stop() async {
    await _speech.stop();
    await _controller?.close();
    _controller = null;
  }
}
