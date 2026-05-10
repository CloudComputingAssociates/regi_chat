// Non-web stub. The MicLevelService implementation lives in
// mic_level_service_web.dart for web targets; this is the no-op fallback
// for any non-web build.
import 'dart:async';

class MicLevelService {
  final StreamController<String> _errors =
      StreamController<String>.broadcast();

  Stream<double> get levels => const Stream<double>.empty();
  Stream<String> get errors => _errors.stream;

  Future<bool> start() async {
    _errors.add('non-web build: mic level meter unsupported');
    return false;
  }

  Future<void> stop() async {}

  void dispose() {
    _errors.close();
  }
}
