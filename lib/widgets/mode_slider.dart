import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/input_mode.dart';

const _prefKey = 'input_mode';

class ModeSlider extends StatelessWidget {
  const ModeSlider({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final InputMode mode;
  final ValueChanged<InputMode> onChanged;

  static Future<InputMode> loadPersistedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    return raw == 'voice' ? InputMode.voice : InputMode.text;
  }

  static Future<void> persistMode(InputMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
  }

  @override
  Widget build(BuildContext context) {
    final isVoice = mode == InputMode.voice;
    return GestureDetector(
      onTap: () {
        final next = isVoice ? InputMode.text : InputMode.voice;
        onChanged(next);
        persistMode(next);
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF555555),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(label: 'Text', active: !isVoice),
            _Segment(label: 'Voice', active: isVoice),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFF2B33D) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.black : Colors.white70,
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
