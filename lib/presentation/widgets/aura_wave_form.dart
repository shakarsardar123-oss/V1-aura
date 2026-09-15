/// aura_wave_form.dart
/// AURA Assistant – Wave Form Widget (Reference Image 1)
///
/// Vertical bar wave form matching Reference Image 1 precisely:
/// ~30 vertical parallel bars of varying heights,
/// neon cyan (#00E5FF) on pure AMOLED black (#000000),
/// floating in a translucent pill container at top of screen.
///
/// Five wave states mapped to AURA states:
///   idle       → slow gentle pulse, bars at ~30% height
///   listening  → active bouncing, bars respond to "input"
///   processing → fast cycling, rapid bar height changes
///   speaking   → rhythmic pulse, smooth wave pattern
///   error      → red flicker, bars turn red and jitter
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Wave form states tied to AURA states.
enum AuraWaveFormState {
  idle,
  listening,
  processing,
  speaking,
  error,
}

/// A vertical bar wave form widget matching Reference Image 1.
///
/// Displays ~30 vertical bars of varying heights on pure AMOLED black,
/// with neon cyan glow and state-driven animations.
class AuraWaveForm extends StatefulWidget {
  const AuraWaveForm({
    super.key,
    this.state = AuraWaveFormState.idle,
    this.barCount = 32,
    this.barWidth = 3.0,
    this.barGap = 2.0,
    this.maxBarHeight = 80.0,
    this.minBarHeight = 4.0,
    this.showPill = true,
  });

  /// Current wave state.
  final AuraWaveFormState state;

  /// Number of vertical bars.
  final int barCount;

  /// Width of each bar in logical pixels.
  final double barWidth;

  /// Gap between bars.
  final double barGap;

  /// Maximum bar height.
  final double maxBarHeight;

  /// Minimum bar height.
  final double minBarHeight;

  /// Whether to show the translucent pill container.
  final bool showPill;

  @override
  State<AuraWaveForm> createState() => _AuraWaveFormState();
}

class _AuraWaveFormState extends State<AuraWaveForm>
    with TickerProviderStateMixin {
  late List<double> _barHeights;
  late List<double> _targetHeights;
  late AnimationController _animController;
  late AnimationController _glowController;

  // Per-bar random seed offsets for organic motion
  late List<double> _phaseOffsets;

  @override
  void initState() {
    super.initState();
    _phaseOffsets = List.generate(
      widget.barCount,
      (i) => i * 0.2 + Random().nextDouble() * 0.5,
    );

    _barHeights = List.filled(widget.barCount, widget.minBarHeight);
    _targetHeights = List.filled(widget.barCount, widget.minBarHeight);

    _animController = AnimationController(
      vsync: this,
      duration: _durationForState(widget.state),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _updateTargetsForState(widget.state);
  }

  @override
  void didUpdateWidget(covariant AuraWaveForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _animController.duration = _durationForState(widget.state);
      _animController.repeat();
      _updateTargetsForState(widget.state);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Duration _durationForState(AuraWaveFormState state) {
    switch (state) {
      case AuraWaveFormState.idle:
        return const Duration(milliseconds: 3000);
      case AuraWaveFormState.listening:
        return const Duration(milliseconds: 1200);
      case AuraWaveFormState.processing:
        return const Duration(milliseconds: 600);
      case AuraWaveFormState.speaking:
        return const Duration(milliseconds: 1000);
      case AuraWaveFormState.error:
        return const Duration(milliseconds: 400);
    }
  }

  void _updateTargetsForState(AuraWaveFormState state) {
    final random = Random();
    switch (state) {
      case AuraWaveFormState.idle:
        // Gentle low pulse, bars at 15-35% max height
        for (int i = 0; i < widget.barCount; i++) {
          _targetHeights[i] =
              widget.minBarHeight +
              (widget.maxBarHeight - widget.minBarHeight) *
                  (0.15 + 0.20 * (0.5 + 0.5 * sin(i * 0.3)));
        }
        break;
      case AuraWaveFormState.listening:
        // Active bouncing, 30-90% max height, more variation
        for (int i = 0; i < widget.barCount; i++) {
          _targetHeights[i] =
              widget.minBarHeight +
              (widget.maxBarHeight - widget.minBarHeight) *
                  (0.30 + 0.60 * random.nextDouble());
        }
        break;
      case AuraWaveFormState.processing:
        // Fast cycling, 20-80% max height, wave pattern
        for (int i = 0; i < widget.barCount; i++) {
          _targetHeights[i] =
              widget.minBarHeight +
              (widget.maxBarHeight - widget.minBarHeight) *
                  (0.20 + 0.60 * (0.5 + 0.5 * sin(i * 0.6 + random.nextDouble())));
        }
        break;
      case AuraWaveFormState.speaking:
        // Rhythmic wave, 25-75% max height, smooth sine
        for (int i = 0; i < widget.barCount; i++) {
          final phase = i / widget.barCount * 2 * pi;
          _targetHeights[i] =
              widget.minBarHeight +
              (widget.maxBarHeight - widget.minBarHeight) *
                  (0.25 + 0.50 * (0.5 + 0.5 * sin(phase)));
        }
        break;
      case AuraWaveFormState.error:
        // Erratic, short bars, red
        for (int i = 0; i < widget.barCount; i++) {
          _targetHeights[i] =
              widget.minBarHeight +
              (widget.maxBarHeight - widget.minBarHeight) *
                  (0.05 + 0.15 * random.nextDouble());
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_animController, _glowController]),
      builder: (context, child) {
        final t = _animController.value;
        final glowT = _glowController.value;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        // Compute bar colors based on state
        final Color barColor = widget.state == AuraWaveFormState.error
            ? AppColors.waveFormErrorRed
            : AppColors.waveFormBarColor;

        final Color barDimColor = widget.state == AuraWaveFormState.error
            ? AppColors.waveFormErrorRed.withOpacity(0.4)
            : AppColors.waveFormBarDim;

        // Glow intensity oscillates
        final glowOpacity =
            0.15 + 0.10 * sin(glowT * 2 * pi);

        // Calculate animated bar heights
        final animatedHeights = List<double>.generate(widget.barCount, (i) {
          final offset = _phaseOffsets[i];
          double height;

          switch (widget.state) {
            case AuraWaveFormState.idle:
              // Slow gentle sine wave
              height = widget.minBarHeight +
                  (_targetHeights[i] - widget.minBarHeight) *
                      (0.6 + 0.4 * sin(t * 2 * pi + offset));
              break;
            case AuraWaveFormState.listening:
              // Active bouncing with some randomness
              height = widget.minBarHeight +
                  (_targetHeights[i] - widget.minBarHeight) *
                      (0.3 + 0.7 * sin(t * 2 * pi + offset).abs());
              break;
            case AuraWaveFormState.processing:
              // Fast wave cycling
              height = widget.minBarHeight +
                  (_targetHeights[i] - widget.minBarHeight) *
                      (0.4 + 0.6 * sin(t * 2 * pi + offset));
              break;
            case AuraWaveFormState.speaking:
              // Rhythmic smooth pulse
              height = widget.minBarHeight +
                  (_targetHeights[i] - widget.minBarHeight) *
                      (0.5 + 0.5 * sin(t * 2 * pi + offset));
              break;
            case AuraWaveFormState.error:
              // Jittery erratic
              height = widget.minBarHeight +
                  (_targetHeights[i] - widget.minBarHeight) *
                      (0.2 + 0.8 * (sin(t * 4 * pi + offset * 3)).abs());
              break;
          }

          return height.clamp(widget.minBarHeight, widget.maxBarHeight);
        });

        // Total width of wave form
        final totalWidth =
            widget.barCount * widget.barWidth +
                (widget.barCount - 1) * widget.barGap;

        // Build the bar row
        final waveForm = CustomPaint(
          painter: _WaveFormPainter(
            barHeights: animatedHeights,
            barWidth: widget.barWidth,
            barGap: widget.barGap,
            barColor: barColor,
            barDimColor: barDimColor,
            glowColor: barColor.withOpacity(glowOpacity),
            maxBarHeight: widget.maxBarHeight,
          ),
          size: Size(totalWidth, widget.maxBarHeight),
        );

        // Center content: state label + wave form
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // State label
            Text(
              _stateLabel(widget.state),
              style: TextStyle(
                color: barColor.withOpacity(0.8),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            // Wave form
            waveForm,
          ],
        );

        if (widget.showPill) {
          // Floating pill container (Reference Image 1 style)
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.waveFormPillBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.waveFormPillBorder,
                width: 0.5,
              ),
              // Subtle outer glow
              boxShadow: [
                BoxShadow(
                  color: barColor.withOpacity(0.08 * glowOpacity),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: content,
          );
        }

        return content;
      },
    );
  }

  String _stateLabel(AuraWaveFormState state) {
    switch (state) {
      case AuraWaveFormState.idle:
        return 'AURA';
      case AuraWaveFormState.listening:
        return 'گوێ دەگرێت...';
      case AuraWaveFormState.processing:
        return 'چاوەڕوان بە...';
      case AuraWaveFormState.speaking:
        return 'قسە دەکات';
      case AuraWaveFormState.error:
        return 'هەڵە';
    }
  }
}

/// Custom painter for the vertical bar wave form.
class _WaveFormPainter extends CustomPainter {
  _WaveFormPainter({
    required this.barHeights,
    required this.barWidth,
    required this.barGap,
    required this.barColor,
    required this.barDimColor,
    required this.glowColor,
    required this.maxBarHeight,
  });

  final List<double> barHeights;
  final double barWidth;
  final double barGap;
  final Color barColor;
  final Color barDimColor;
  final Color glowColor;
  final double maxBarHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    for (int i = 0; i < barHeights.length; i++) {
      final x = i * (barWidth + barGap);
      final barHeight = barHeights[i];
      // Center vertically
      final y = (maxBarHeight - barHeight) / 2;

      // Glow behind bar (wider, dimmer)
      glowPaint.color = glowColor;
      final glowRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 1, y - 1, barWidth + 2, barHeight + 2),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(glowRect, glowPaint);

      // Main bar
      // Bars near center are brighter, edges dimmer
      final centerDist = (i - barHeights.length / 2).abs() /
          (barHeights.length / 2);
      paint.color = Color.lerp(barColor, barDimColor, centerDist * 0.5)!;

      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(barRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveFormPainter oldDelegate) {
    return oldDelegate.barHeights != barHeights ||
        oldDelegate.barColor != barColor ||
        oldDelegate.glowColor != glowColor;
  }
}
