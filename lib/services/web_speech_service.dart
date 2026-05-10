// Direct webkitSpeechRecognition wrapper, bypassing the speech_to_text
// package. Same Web Speech API that package was wrapping, but with our
// own listener wiring so any wrapper-layer bug is removed from the
// equation. Works only on web; non-web targets get the stub.
//
// If this file produces transcripts where speech_to_text didn't, the
// package was the problem. If it also produces nothing, the browser-side
// Web Speech API itself is broken in our deployment context, and we have
// to switch to a different STT backend.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class WebSpeechService {
  WebSpeechService();

  web.SpeechRecognition? _recog;
  StreamController<String>? _transcripts;
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  final StreamController<String> _statuses =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool get isAvailable => _initialized;

  Stream<String> get errors => _errors.stream;
  Stream<String> get statuses => _statuses.stream;

  Future<bool> initialize() async {
    if (_initialized) return true;

    // Modern Chrome/Edge expose both `SpeechRecognition` (standardized)
    // and `webkitSpeechRecognition` (legacy prefix). The unprefixed
    // constructor in package:web maps to whichever is present.
    try {
      _recog = web.SpeechRecognition();
    } catch (e) {
      _errors.add('Web Speech API unavailable: $e');
      return false;
    }

    _recog!.continuous = true;
    _recog!.interimResults = true;
    _recog!.maxAlternatives = 1;
    _recog!.lang = 'en-US';

    _initialized = true;
    return true;
  }

  Stream<String> listen() {
    final controller = StreamController<String>.broadcast();
    _transcripts?.close();
    _transcripts = controller;

    final recog = _recog;
    if (recog == null) {
      _errors.add('listen called before initialize');
      controller.close();
      return controller.stream;
    }

    // onresult: cumulative results since this listen() session started.
    // Concatenate all final + interim segments into the running transcript.
    recog.onresult = ((web.SpeechRecognitionEvent ev) {
      if (controller.isClosed) return;
      final buf = StringBuffer();
      final results = ev.results;
      for (var i = 0; i < results.length; i++) {
        final result = results.item(i);
        if (result.length > 0) {
          buf.write(result.item(0).transcript);
        }
      }
      controller.add(buf.toString());
    }).toJS;

    recog.onerror = ((web.SpeechRecognitionErrorEvent ev) {
      _errors.add('webkit error: ${ev.error}'
          '${ev.message.isNotEmpty ? " — ${ev.message}" : ""}');
    }).toJS;

    recog.onstart = ((web.Event _) {
      if (!_statuses.isClosed) _statuses.add('listening');
    }).toJS;

    recog.onend = ((web.Event _) {
      if (!_statuses.isClosed) _statuses.add('done');
    }).toJS;

    recog.onspeechstart = ((web.Event _) {
      if (!_statuses.isClosed) _statuses.add('speech-detected');
    }).toJS;

    recog.onspeechend = ((web.Event _) {
      if (!_statuses.isClosed) _statuses.add('speech-ended');
    }).toJS;

    recog.onnomatch = ((web.Event _) {
      _errors.add('no match (recognizer heard speech but matched nothing)');
    }).toJS;

    try {
      recog.start();
    } catch (e) {
      _errors.add('start threw: $e');
    }

    return controller.stream;
  }

  Future<void> stop() async {
    try {
      _recog?.stop();
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
