// Public re-export. Web build picks the dart:html-backed impl; everything
// else gets a no-op stub. Caller imports this file as the single entry.
export 'mic_level_service_io.dart'
    if (dart.library.html) 'mic_level_service_web.dart';
