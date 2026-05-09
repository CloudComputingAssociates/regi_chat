import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PttButton extends StatefulWidget {
  const PttButton({
    super.key,
    required this.onPressStart,
    required this.onPressEnd,
    this.size = 120,
  });

  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final double size;

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> {
  bool _pressed = false;

  void _handleStart() {
    setState(() => _pressed = true);
    HapticFeedback.lightImpact();
    widget.onPressStart();
  }

  void _handleEnd() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onPressEnd();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _handleStart(),
      onLongPressEnd: (_) => _handleEnd(),
      onLongPressCancel: _handleEnd,
      onTapDown: (_) => _handleStart(),
      onTapUp: (_) => _handleEnd(),
      onTapCancel: _handleEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.size,
        height: widget.size,
        transform: Matrix4.identity()..scale(_pressed ? 0.95 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            if (_pressed)
              BoxShadow(
                color: const Color(0xFFF2B33D).withValues(alpha: 0.85),
                blurRadius: 24,
                spreadRadius: 4,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
          border: Border.all(
            color: _pressed
                ? const Color(0xFFF2B33D)
                : Colors.white,
            width: 3,
          ),
        ),
        alignment: Alignment.center,
        child: ClipOval(
          child: Padding(
            padding: EdgeInsets.all(widget.size * 0.1),
            child: Image.asset(
              'assets/images/ptt_fingerprint.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
