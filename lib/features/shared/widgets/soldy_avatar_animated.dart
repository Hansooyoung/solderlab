import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Kondisi ekspresi emosional maskot Soldy berdasarkan konteks halaman/hasil QC.
enum SoldyMood {
  idle,
  inspecting,
  happy,
  warning,
  alert,
}

/// SoldyAvatarAnimated: Maskot hidup SolderLab dengan nafas halus, kedip mata real-time,
/// reaksi ekspresi [SoldyMood], dan pantulan interaktif saat diketuk.
class SoldyAvatarAnimated extends StatefulWidget {
  final double size;
  final bool enableBreathing;
  final bool enableBlinking;
  final SoldyMood mood;
  final VoidCallback? onTap;
  final bool forceAmbientAnimationInTest;

  const SoldyAvatarAnimated({
    super.key,
    this.size = 220,
    this.enableBreathing = true,
    this.enableBlinking = true,
    this.mood = SoldyMood.idle,
    this.onTap,
    this.forceAmbientAnimationInTest = false,
  });

  @override
  State<SoldyAvatarAnimated> createState() => _SoldyAvatarAnimatedState();
}

class _SoldyAvatarAnimatedState extends State<SoldyAvatarAnimated>
    with TickerProviderStateMixin {
  late final AnimationController _breatheController;
  late final AnimationController _blinkController;
  late final AnimationController _tapReactController;
  late final Animation<double> _breatheY;
  late final Animation<double> _breatheScale;
  late final Animation<double> _blinkCurve;
  Timer? _blinkTimer;
  bool _isTapped = false;

  bool get _isAutomatedTest =>
      !widget.forceAmbientAnimationInTest &&
      WidgetsBinding.instance.runtimeType.toString().contains('AutomatedTest');

  @override
  void initState() {
    super.initState();

    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _breatheY = Tween<double>(begin: 0.0, end: -5.5).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOutSine),
    );
    _breatheScale = Tween<double>(begin: 1.0, end: 1.022).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOutSine),
    );

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _blinkCurve = CurvedAnimation(
      parent: _blinkController,
      curve: Curves.easeInOutCubic,
    );

    _tapReactController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _syncAmbientLoops();
  }

  void _syncAmbientLoops() {
    final allowLoop = !_isAutomatedTest;
    if (widget.enableBreathing && allowLoop) {
      if (!_breatheController.isAnimating) {
        _breatheController.repeat(reverse: true);
      }
    } else {
      _breatheController.stop();
      _breatheController.value = 0.0;
    }

    _blinkTimer?.cancel();
    if (widget.enableBlinking && allowLoop) {
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 3600), (_) {
        _triggerSingleBlink();
      });
    }
  }

  @override
  void didUpdateWidget(covariant SoldyAvatarAnimated oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableBreathing != widget.enableBreathing ||
        oldWidget.enableBlinking != widget.enableBlinking ||
        oldWidget.forceAmbientAnimationInTest != widget.forceAmbientAnimationInTest) {
      _syncAmbientLoops();
    }
    if (oldWidget.mood != widget.mood && mounted) {
      _triggerSingleBlink();
    }
  }

  Future<void> _triggerSingleBlink() async {
    if (!mounted) return;
    try {
      await _blinkController.forward();
      if (!mounted) return;
      await _blinkController.reverse();
    } catch (_) {
      // Abaikan jika widget di-dispose di tengah animasi
    }
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    _tapReactController.forward(from: 0.0);
    _triggerSingleBlink();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _breatheController.dispose();
    _blinkController.dispose();
    _tapReactController.dispose();
    super.dispose();
  }

  Color _moodAuraColor() {
    switch (widget.mood) {
      case SoldyMood.happy:
        return const Color(0xFF16A34A);
      case SoldyMood.inspecting:
        return const Color(0xFF38BDF8);
      case SoldyMood.warning:
        return const Color(0xFFD97706);
      case SoldyMood.alert:
        return const Color(0xFFDC2626);
      case SoldyMood.idle:
        return const Color(0xFFA8CCE8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final interactive = widget.onTap != null;

    return GestureDetector(
      onTapDown: interactive ? (_) => setState(() => _isTapped = true) : null,
      onTapUp: interactive
          ? (_) {
              setState(() => _isTapped = false);
              _handleTap();
            }
          : null,
      onTapCancel: interactive ? () => setState(() => _isTapped = false) : null,
      child: AnimatedScale(
        scale: _isTapped ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutQuad,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _breatheController,
            _blinkController,
            _tapReactController,
          ]),
          builder: (context, child) {
            final yOffset = (!reduceMotion && widget.enableBreathing)
                ? _breatheY.value
                : 0.0;
            final scaleVal = (!reduceMotion && widget.enableBreathing)
                ? _breatheScale.value
                : 1.0;
            final hop = math.sin(_tapReactController.value * math.pi) * -6.0;
            final tilt =
                math.sin(_tapReactController.value * math.pi * 2) * 0.05;

            return Transform.translate(
              offset: Offset(0, yOffset + hop),
              child: Transform.rotate(
                angle: tilt,
                child: Transform.scale(
                  scale: scaleVal,
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Mood soft aura halo
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: widget.size * 0.88,
                          height: widget.size * 0.88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _moodAuraColor().withValues(
                                  alpha: widget.mood == SoldyMood.idle ? 0.16 : 0.28,
                                ),
                                blurRadius: widget.size * 0.18,
                                spreadRadius: widget.size * 0.02,
                              ),
                            ],
                          ),
                        ),
                        // Hero SVG Soldy Mascot
                        child!,
                        // Dynamic eyelid blink & mood facial expression overlay aligned to viewBox 512x512
                        CustomPaint(
                          size: Size(widget.size, widget.size),
                          painter: _SoldyExpressionPainter(
                            blinkProgress: _blinkCurve.value,
                            mood: widget.mood,
                            scanProgress: _breatheController.value,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          child: Semantics(
            label: 'Maskot AI Soldy SolderLab',
            child: SvgPicture.asset(
              'assets/branding/app_icon.svg',
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              placeholderBuilder: (context) => Image.asset(
                'assets/branding/app_icon_512.png',
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoldyExpressionPainter extends CustomPainter {
  final double blinkProgress;
  final SoldyMood mood;
  final double scanProgress;

  _SoldyExpressionPainter({
    required this.blinkProgress,
    required this.mood,
    required this.scanProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512.0;

    // 1. Dynamic eyelids sweeping smoothly over SVG eyes at (214, 294) & (298, 294)
    if (blinkProgress > 0.02) {
      final lidPaint = Paint()
        ..color = const Color(0xFF4B6C86)
        ..style = PaintingStyle.fill;
      final lashPaint = Paint()
        ..color = const Color(0xFF182733)
        ..strokeWidth = (4.5 * s).clamp(1.2, 4.5)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (final cx in [214.0, 298.0]) {
        final center = Offset(cx * s, 294.0 * s);
        final rx = 16.5 * s;
        final ry = 26.0 * s;
        final closeH = ry * 2.0 * blinkProgress;
        canvas.save();
        canvas.clipPath(
          Path()
            ..addOval(Rect.fromCenter(center: center, width: rx * 2, height: ry * 2)),
        );
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - rx,
            center.dy - ry,
            rx * 2,
            closeH,
          ),
          lidPaint,
        );
        canvas.restore();
        if (blinkProgress > 0.55) {
          final curveY = center.dy - ry + closeH * 0.85;
          canvas.drawArc(
            Rect.fromCenter(center: Offset(center.dx, curveY), width: rx * 1.8, height: 8 * s),
            0.15,
            math.pi - 0.3,
            false,
            lashPaint,
          );
        }
      }
    }

    // 2. Mood accent indicators (compact badge / brow / tip glow)
    if (mood == SoldyMood.inspecting) {
      final tipPaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.45 + 0.35 * scanProgress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.8 * s).clamp(1.0, 3.0);
      canvas.drawCircle(
        Offset(286 * s, 444 * s),
        (16.0 + 10.0 * scanProgress) * s,
        tipPaint,
      );
    } else if (mood == SoldyMood.happy) {
      final sparkPaint = Paint()..color = const Color(0xFF22C55E);
      canvas.drawCircle(Offset(410 * s, 140 * s), 7.5 * s, sparkPaint);
      canvas.drawCircle(Offset(108 * s, 175 * s), 5.5 * s, sparkPaint);
    } else if (mood == SoldyMood.warning || mood == SoldyMood.alert) {
      final badgeColor = mood == SoldyMood.alert
          ? const Color(0xFFDC2626)
          : const Color(0xFFD97706);
      final bg = Paint()..color = badgeColor;
      final border = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.5 * s).clamp(1.0, 3.0);
      final center = Offset(404 * s, 114 * s);
      canvas.drawCircle(center, 22 * s, bg);
      canvas.drawCircle(center, 22 * s, border);
      final stroke = Paint()
        ..color = Colors.white
        ..strokeWidth = (4.0 * s).clamp(1.4, 4.0)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(center.dx, center.dy - 9 * s), Offset(center.dx, center.dy + 2 * s), stroke);
      canvas.drawCircle(Offset(center.dx, center.dy + 9 * s), (2.2 * s).clamp(1.0, 3.0), Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _SoldyExpressionPainter oldDelegate) {
    return oldDelegate.blinkProgress != blinkProgress ||
        oldDelegate.mood != mood ||
        oldDelegate.scanProgress != scanProgress;
  }
}
