import 'package:flutter/material.dart';

/// Simulated audio-level bars shown while the user is actively recording.
/// Each bar bounces independently for a "live mic" feel.
///
/// POC: not driven by real audio levels. To upgrade later, drive each bar's
/// height from a live sample stream — speech_to_text's `soundLevel` callback
/// on Android, or a parallel Web Audio API AnalyserNode on web.
class MicLevelBars extends StatefulWidget {
  const MicLevelBars({
    super.key,
    this.barCount = 5,
    this.color = const Color(0xFFF2B33D),
    this.minHeight = 6,
    this.maxHeight = 22,
    this.barWidth = 3,
    this.spacing = 3,
  });

  final int barCount;
  final Color color;
  final double minHeight;
  final double maxHeight;
  final double barWidth;
  final double spacing;

  @override
  State<MicLevelBars> createState() => _MicLevelBarsState();
}

class _MicLevelBarsState extends State<MicLevelBars>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.barCount, (i) {
      // Stagger durations so each bar runs at a different period — no two
      // bars peak at the same moment, gives the "live" jitter.
      final ms = 280 + ((i * 137) % 320);
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: ms),
      )..repeat(reverse: true);
      // Offset each controller's starting phase so they don't all begin at 0.
      ctrl.value = ((i * 0.37) % 1.0);
      return ctrl;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.maxHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < widget.barCount; i++) ...[
            if (i > 0) SizedBox(width: widget.spacing),
            AnimatedBuilder(
              animation: _controllers[i],
              builder: (_, __) {
                final t = Curves.easeInOut.transform(_controllers[i].value);
                final h = widget.minHeight +
                    (widget.maxHeight - widget.minHeight) * t;
                return Container(
                  width: widget.barWidth,
                  height: h,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.barWidth / 2),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
