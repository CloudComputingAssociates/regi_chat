// Non-web stub. The MicLevelService implementation lives in
// mic_level_service_web.dart for web targets; this is the no-op fallback
// for any non-web build (Android/iOS/desktop). When you wire native, swap
// this for a speech_to_text onSoundLevelChange-driven impl.
import 'dart:async';

class MicLevelService {
  Stream<double> get levels => const Stream<double>.empty();
  Future<bool> start() async => false;
  Future<void> stop() async {}
  void dispose() {}
}
