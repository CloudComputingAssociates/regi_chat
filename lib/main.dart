import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // .env is optional. On Netlify it's an empty stub; values come from
  // --dart-define via lib/config.dart. Locally it has the real values.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env on disk — Config will fall through to compile-time defines.
  }
  runApp(const RegiChatApp());
}
