import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Audio-level bars shown while the user is recording.
///
/// If [levels] is provided, bar heights are driven from real mic volume
/// (one normalized 0..1 sample per event). Each bar gets a stable bias
/// based on its distance from the row's center, producing a pyramid-style
/// meter rather than identical lockstep movement.
///
/// If [levels] is null, the widget falls back to a self-animating "ripple"
/// loop: a wave radiates from center outward and a slower secondary
/// oscillation modulates global intensity, faking speech intonation.
class MicLevelBars extends StatefulWidget {
  const MicLevelBars({
    super.key,
    this.levels,
    this.barCount = 11,
    this.color = const Color(0xFFF2B33D),
    this.minHeight = 3,
    this.maxHeight = 20,
    this.barWidth = 2,
    this.spacing = 2,
  });

  final Stream<double>? levels;
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
    with SingleTickerProviderStateMixin {
  // Single long-running ticker drives every bar — cheaper than one
  // controller per bar and gives the bars a coherent shared time base
  // (essential for the ripple/wave to actually look like a wave).
  late final AnimationController _ctrl;
  StreamSubscription<double>? _sub;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _attach();
  }

  @override
  void didUpdateWidget(covariant MicLevelBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.levels != widget.levels) {
      _detach();
      _attach();
    }
  }

  void _attach() {
    final stream = widget.levels;
    if (stream == null) return;
    _sub = stream.listen((v) {
      if (!mounted) return;
      setState(() => _level = v);
    });
  }

  void _detach() {
    _sub?.cancel();
    _sub = null;
    _level = 0;
  }

  @override
  void dispose() {
    _detach();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isStreamed = widget.levels != null;

    return SizedBox(
      height: widget.maxHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < widget.barCount; i++) ...[
            if (i > 0) SizedBox(width: widget.spacing),
            isStreamed ? _buildStreamedBar(i) : _buildRippleBar(i),
          ],
        ],
      ),
    );
  }

  // Pyramid bias: center bar reacts at full level, edge bars dampened.
  double _biasFor(int i) {
    final dist = (i - (widget.barCount - 1) / 2).abs();
    return (1.0 - (dist / widget.barCount) * 0.6).clamp(0.0, 1.0);
  }

  Widget _buildStreamedBar(int i) {
    // Real-audio mode still rides the ripple — the wave provides motion,
    // the live volume provides the *envelope*. At silence (_level → 0)
    // bars rest at minHeight; speaking up cranks the dance amplitude.
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value * 2 * math.pi;
        final center = (widget.barCount - 1) / 2;
        final distFromCenter = (i - center).abs();
        final ripplePhase = distFromCenter * 0.6;
        final ripple = 0.5 + 0.5 * math.sin(t * 3 - ripplePhase);
        final bias = _biasFor(i);
        final amp = (_level * ripple * bias).clamp(0.0, 1.0);
        final h = widget.minHeight +
            (widget.maxHeight - widget.minHeight) * amp;
        return Container(
          width: widget.barWidth,
          height: h,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(widget.barWidth / 2),
          ),
        );
      },
    );
  }

  Widget _buildRippleBar(int i) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // Two waves overlap so motion never settles into a clean repeat:
        //   - fast wave radiates from center outward (the ripple)
        //   - slower amplitude wave modulates the whole row, faking
        //     the rise-and-fall of speech intensity
        final t = _ctrl.value * 2 * math.pi;
        final center = (widget.barCount - 1) / 2;
        final distFromCenter = (i - center).abs();

        // Ripple: phase grows with distance from center → wave appears
        // to emanate outward. Multiply t by 3 so the ripple cycles
        // ~3× per controller loop (lively but not frenetic).
        final ripplePhase = distFromCenter * 0.6;
        final ripple = 0.5 + 0.5 * math.sin(t * 3 - ripplePhase);

        // Intonation: slow per-bar drift makes adjacent bars decouple
        // slightly so the row doesn't look like a single rigid wave.
        final intonation =
            0.55 + 0.45 * math.sin(t * 0.7 + i * 0.45);

        final bias = _biasFor(i);
        final amp = (ripple * intonation * bias).clamp(0.05, 1.0);
        final h = widget.minHeight +
            (widget.maxHeight - widget.minHeight) * amp;

        return Container(
          width: widget.barWidth,
          height: h,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(widget.barWidth / 2),
          ),
        );
      },
    );
  }
}
