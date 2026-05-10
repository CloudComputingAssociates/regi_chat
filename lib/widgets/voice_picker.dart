import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/chat_state.dart';

/// Voice catalog row — fetched from `GET /api/tts/voices`. The selected
/// voice ID is sent in the body of `POST /api/tts` for assistant replies.
/// Speed and mute live in the chat input bar; this row is just selection.
class VoicePicker extends StatelessWidget {
  const VoicePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChatState>();
    final voices = state.availableVoices;
    if (voices.isEmpty) {
      return const SizedBox.shrink();
    }
    final selectedId = state.selectedVoice?.id;

    return Container(
      width: double.infinity,
      color: const Color(0xFF252525),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(
              Icons.record_voice_over,
              size: 16,
              color: Colors.white54,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final v in voices) ...[
                    _VoiceChip(
                      label: v.displayName,
                      selected: v.id == selectedId,
                      onTap: () => context.read<ChatState>().setSelectedVoice(v),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceChip extends StatelessWidget {
  const _VoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF2B33D) : const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
