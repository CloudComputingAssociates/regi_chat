import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/input_mode.dart';
import '../state/chat_state.dart';
import 'mic_level_bars.dart';
import 'mode_slider.dart';

const _promptMeColor = Color(0xFF8B1A2B);
const _talkActiveColor = Color(0xFFF2B33D);
const _barColor = Color(0xFF3A3A3A);

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.onPromptMe,
    required this.onTalkStart,
    required this.onTalkEnd,
  });

  final void Function(String text) onSend;
  final VoidCallback onPromptMe;
  final VoidCallback onTalkStart;
  final VoidCallback onTalkEnd;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final state = context.read<ChatState>();
      if (_controller.text != state.currentInput) {
        state.setCurrentInput(_controller.text);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    context.read<ChatState>().clearCurrentInput();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChatState>();
    final isVoice = state.mode == InputMode.voice;

    // Sync external transcript updates (from STT) into the controller
    // when in voice mode. Defer to post-frame so we don't mutate the
    // controller during build.
    if (isVoice && _controller.text != state.currentInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_controller.text == state.currentInput) return;
        _controller.value = TextEditingValue(
          text: state.currentInput,
          selection:
              TextSelection.collapsed(offset: state.currentInput.length),
        );
      });
    }

    return SafeArea(
      top: false,
      child: Container(
        color: _barColor,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            _PromptMeButton(
              isOn: state.isPromptMeOn,
              onTap: () {
                state.togglePromptMe();
                if (state.isPromptMeOn) widget.onPromptMe();
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                readOnly: isVoice,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: isVoice
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFF555555),
                  hintText: isVoice
                      ? 'Hold the button and speak...'
                      : 'Type a message...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: state.isTalkActive
                      ? const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: MicLevelBars(),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SquareButton(
              icon: Icons.send,
              tooltip: 'Send',
              onTap: _handleSend,
            ),
            const SizedBox(width: 8),
            ModeSlider(
              mode: state.mode,
              onChanged: state.setMode,
            ),
            const SizedBox(width: 8),
            _TalkButton(
              enabled: isVoice,
              active: state.isTalkActive,
              onPressStart: widget.onTalkStart,
              onPressEnd: widget.onTalkEnd,
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptMeButton extends StatelessWidget {
  const _PromptMeButton({required this.isOn, required this.onTap});

  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isOn ? _promptMeColor : const Color(0xFF555555),
          shape: BoxShape.circle,
          boxShadow: isOn
              ? [
                  const BoxShadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.auto_awesome,
          color: isOn ? Colors.white : Colors.white70,
          size: 20,
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF555555),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _TalkButton extends StatelessWidget {
  const _TalkButton({
    required this.enabled,
    required this.active,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final bool enabled;
  final bool active;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? const Color(0xFF333333)
        : active
            ? _talkActiveColor
            : const Color(0xFF555555);
    return GestureDetector(
      onLongPressStart: enabled ? (_) => onPressStart() : null,
      onLongPressEnd: enabled ? (_) => onPressEnd() : null,
      onLongPressCancel: enabled ? onPressEnd : null,
      onTapDown: enabled ? (_) => onPressStart() : null,
      onTapUp: enabled ? (_) => onPressEnd() : null,
      onTapCancel: enabled ? onPressEnd : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.mic,
          color: enabled ? Colors.white : Colors.white24,
          size: 20,
        ),
      ),
    );
  }
}
