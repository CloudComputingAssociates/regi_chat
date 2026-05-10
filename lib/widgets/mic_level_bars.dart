import 'dart:async';

import 'package:flutter/material.dart';

/// Audio-level bars shown while the user is recording.
///
/// If [levels] is provided, bar heights are driven from real mic volume
/// (one normalized 0..1 sample per event). Each bar gets a stable bias
/// based on its distance from the row's center, producing a pyramid-style
/// meter rather than identical lockstep movement.
///
/// If [levels] is null, the widget falls back to a self-animating
/// "looks-alive" loop (each bar bouncing on its own period). Used when
/// audio sampling isn't available (e.g., non-web platform without native
/// soundLevel hooked up yet, or mic permission denied).
class MicLevelBars extends StatefulWidget {
  const MicLevelBars({
    super.key,
    this.levels,
    this.barCount = 5,
    this.color = const Color(0xFFF2B33D),
    this.minHeight = 6,
    this.maxHeight = 22,
    this.barWidth = 3,
    this.spacing = 3,
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
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  StreamSubscription<double>? _sub;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.barCount, (i) {
      final ms = 280 + ((i * 137) % 320);
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: ms),
      )..repeat(reverse: true);
      ctrl.value = ((i * 0.37) % 1.0);
      return ctrl;
    });
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
    for (final c in _controllers) {
      c.dispose();
    }
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
            isStreamed ? _buildStreamedBar(i) : _buildSelfAnimBar(i),
          ],
        ],
      ),
    );
  }

  // Pyramid bias: center bar reacts at full level, edge bars dampened.
  // For 5 bars: 0.76, 0.88, 1.0, 0.88, 0.76.
  double _biasFor(int i) {
    final dist = (i - (widget.barCount - 1) / 2).abs();
    return (1.0 - (dist / widget.barCount) * 0.6).clamp(0.0, 1.0);
  }

  Widget _buildStreamedBar(int i) {
    final bias = _biasFor(i);
    final h = widget.minHeight +
        (widget.maxHeight - widget.minHeight) *
            (_level * bias).clamp(0.0, 1.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      curve: Curves.easeOut,
      width: widget.barWidth,
      height: h,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(widget.barWidth / 2),
      ),
    );
  }

  Widget _buildSelfAnimBar(int i) {
    return AnimatedBuilder(
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
    );
  }
}
