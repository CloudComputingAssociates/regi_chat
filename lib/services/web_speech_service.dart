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
    // LATEST-FINAL mode: in continuous mode on Chrome (especially Android),
    // a single spoken phrase can produce multiple final results as the
    // recognizer over-segments and revises. Concatenating them gives
    // "whowho holds the who holds the title" gibberish. The latest final
    // result is the recognizer's most complete take and is what the user
    // actually wants for one PTT press = one phrase semantics.
    recog.onresult = ((web.SpeechRecognitionEvent ev) {
      if (controller.isClosed) return;
      final results = ev.results;
      String? latest;
      for (var i = results.length - 1; i >= 0; i--) {
        final result = results.item(i);
        if (!result.isFinal) continue;
        if (result.length > 0) {
          latest = result.item(0).transcript;
          break;
        }
      }
      if (latest != null) controller.add(latest);
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
    final recog = _recog;
    if (recog == null) {
      await _transcripts?.close();
      _transcripts = null;
      return;
    }

    // Web Speech API quirk: recog.stop() signals the recognizer to flush,
    // but trailing onresult events (carrying the last word or two) fire
    // ASYNCHRONOUSLY after this call returns. If we close the subscription
    // immediately we lose the end of speech.
    //
    // Strategy: wire a one-shot completer to the next 'end' event, call
    // stop(), wait for onend (with a hard timeout in case it never fires).
    // By the time onend fires, the recognizer has emitted any pending
    // final result via onresult, which has already updated the consumer.
    final endCompleter = Completer<void>();
    final originalOnEnd = recog.onend;
    recog.onend = ((web.Event ev) {
      if (!endCompleter.isCompleted) endCompleter.complete();
      // Forward to the listen()-installed handler so status events still flow.
      if (originalOnEnd != null) {
        originalOnEnd.callAsFunction(recog as JSAny?, ev as JSAny?);
      }
    }).toJS;

    try {
      recog.stop();
    } catch (e) {
      _errors.add('stop threw: $e');
    }

    // Wait for the recognizer to actually finish flushing. 1.5s is generous;
    // typical flush takes 100-400ms. The timeout guards against onend never
    // firing on quirky browsers.
    try {
      await endCompleter.future.timeout(
        const Duration(milliseconds: 1500),
      );
    } catch (_) {
      // Timed out — proceed anyway; we got whatever the recognizer gave us.
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
