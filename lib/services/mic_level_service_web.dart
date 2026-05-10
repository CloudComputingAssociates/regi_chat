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
  // Permanent broadcast controller — created once at construction and kept
  // open until dispose(). Consumers (e.g., MicLevelBars) capture this
  // stream reference at subscribe time, so it must survive start/stop
  // cycles. Recreating it per start() leaves any pre-subscribed widget
  // listening to a closed/empty stream and the bars sit dead.
  final StreamController<double> _levels =
      StreamController<double>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  web.AudioContext? _ctx;
  web.MediaStream? _stream;
  Timer? _timer;
  JSUint8Array? _buffer;
  bool _running = false;

  Stream<double> get levels => _levels.stream;

  /// Emits any failure during start/run as a human-readable string.
  Stream<String> get errors => _errors.stream;

  Future<bool> start() async {
    if (_running) return true;

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

      _running = true;

      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (_levels.isClosed || !_running) return;
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
        _levels.add(gated);
      });

      return true;
    } catch (e) {
      _errors.add('mic level start failed: $e');
      await stop();
      return false;
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;

    // Emit one zero so any subscribed visualizer drops to rest immediately
    // instead of holding the last live sample as its frozen height.
    if (!_levels.isClosed) _levels.add(0);

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
  }

  void dispose() {
    stop();
    _levels.close();
    _errors.close();
  }
}
