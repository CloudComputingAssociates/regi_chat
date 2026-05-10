// Web Audio API tap to drive real audio-reactive UI.
//
// Opens its own getUserMedia stream parallel to speech_to_text's
// webkitSpeechRecognition. The browser dedupes the mic permission grant
// so the user is not prompted twice. AnalyserNode samples the frequency
// bins at 20Hz (50ms timer) and emits a normalized [0..1] volume.
//
// Lifecycle: start() must be called from inside a user gesture (the PTT
// button press) so AudioContext can resume past the autoplay policy.
//
// Uses package:web + dart:js_interop (the modern, non-deprecated stack).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class MicLevelService {
  StreamController<double>? _controller;
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  web.AudioContext? _ctx;
  web.MediaStream? _stream;
  Timer? _timer;
  JSUint8Array? _buffer;

  Stream<double> get levels =>
      _controller?.stream ?? const Stream<double>.empty();

  /// Emits any failure during start/run as a human-readable string.
  Stream<String> get errors => _errors.stream;

  Future<bool> start() async {
    if (_controller != null) return true; // already running

    try {
      final mediaDevices = web.window.navigator.mediaDevices;

      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
        video: false.toJS,
      );

      try {
        _stream = await mediaDevices.getUserMedia(constraints).toDart;
      } catch (e) {
        _errors.add('getUserMedia rejected: $e');
        rethrow;
      }

      _ctx = web.AudioContext();
      // Some browsers start the AudioContext suspended; resume explicitly
      // while the user gesture is still fresh.
      if (_ctx!.state == 'suspended') {
        try {
          await _ctx!.resume().toDart;
        } catch (e) {
          _errors.add('AudioContext.resume failed: $e');
          rethrow;
        }
      }

      final source = _ctx!.createMediaStreamSource(_stream!);
      final analyser = _ctx!.createAnalyser();
      analyser.fftSize = 256;
      analyser.smoothingTimeConstant = 0.7;
      source.connect(analyser);

      final bufferLength = analyser.frequencyBinCount;
      // Pre-allocate the JS-side typed array so each frame doesn't allocate.
      _buffer = Uint8List(bufferLength).toJS;

      final controller = StreamController<double>.broadcast();
      _controller = controller;

      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (controller.isClosed) return;
        final buf = _buffer;
        if (buf == null) return;
        analyser.getByteFrequencyData(buf);
        final bytes = buf.toDart;
        var sum = 0;
        for (final b in bytes) {
          sum += b;
        }
        final avg = (sum / bytes.length) / 255.0;
        // Noise gate: silence reads as zero so bars rest, not jitter.
        final gated = avg < 0.04 ? 0.0 : avg;
        controller.add(gated);
      });

      return true;
    } catch (e) {
      _errors.add('mic level start failed: $e');
      await stop();
      return false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;

    final tracks = _stream?.getTracks().toDart;
    if (tracks != null) {
      for (final t in tracks) {
        t.stop();
      }
    }
    _stream = null;

    if (_ctx != null) {
      try {
        await _ctx!.close().toDart;
      } catch (_) {}
      _ctx = null;
    }

    _buffer = null;

    final c = _controller;
    _controller = null;
    await c?.close();
  }

  void dispose() {
    stop();
    _errors.close();
  }
}
