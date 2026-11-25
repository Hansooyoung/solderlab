import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Kit animasi SolderLab (murni Flutter native, tanpa dependensi tambahan).
/// Semua widget menghormati pengaturan "kurangi animasi" perangkat (MediaQuery.disableAnimations).

bool _reduceMotion(BuildContext context) => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Masuk bertahap: fade + geser naik. [index] menentukan urutan (stagger) tanpa Timer.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration base;
  final Duration step;
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.base = const Duration(milliseconds: 420),
    this.step = const Duration(milliseconds: 70),
    this.offsetY = 18,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final delayMs = (widget.step.inMilliseconds * widget.index).clamp(0, 700);
    final total = widget.base.inMilliseconds + delayMs;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: total));
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(delayMs / total, 1.0, curve: Curves.easeOutCubic),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offsetY), child: child),
      ),
    );
  }
}

/// Angka yang menghitung naik dari 0 (atau nilai sebelumnya) ke [value].
class CountUpText extends StatelessWidget {
  final double value;
  final int decimals;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  const CountUpText({
    super.key,
    required this.value,
    this.decimals = 0,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) {
      return Text('$prefix${value.toStringAsFixed(decimals)}$suffix', style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$prefix${v.toStringAsFixed(decimals)}$suffix', style: style),
    );
  }
}

/// Umpan balik sentuh: mengecil saat ditekan + haptic ringan.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptic;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.haptic = true,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Denyut cincin lembut berulang (untuk tombol aksi utama). Jangan dipakai di layar yang diuji pumpAndSettle.
class PulseGlow extends StatefulWidget {
  final Widget child;
  final Color color;
  final double maxSpread;

  const PulseGlow({super.key, required this.child, this.color = AppTheme.softSky, this.maxSpread = 14});

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: (1 - t) * 0.55),
                blurRadius: 6,
                spreadRadius: t * widget.maxSpread,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// Batang progres yang tumbuh dari kiri saat pertama tampil / nilai berubah.
class AnimatedBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final double height;
  final Color trackColor;

  const AnimatedBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 8,
    this.trackColor = const Color(0xFFF1F5F9),
  });

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(color: trackColor, borderRadius: BorderRadius.circular(height)),
      child: LayoutBuilder(
        builder: (context, c) {
          final target = math.max(f * c.maxWidth, f > 0 ? height : 0.0);
          return Align(
            alignment: Alignment.centerLeft,
            child: _reduceMotion(context)
                ? Container(
                    width: target,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
                  )
                : TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: target),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, w, _) => Container(
                      width: w,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// Pop-in dengan efek membal (untuk ikon status / lencana hasil).
class PopIn extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const PopIn({super.key, required this.child, this.duration = const Duration(milliseconds: 600)});

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.elasticOut,
      builder: (context, v, c) => Transform.scale(scale: v.clamp(0.0, 1.4), child: c),
      child: child,
    );
  }
}

/// Transisi halaman halus: fade + geser dari kanan (dipakai untuk semua navigasi aplikasi).
class SolderPageRoute<T> extends PageRouteBuilder<T> {
  SolderPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (context, _, _) => builder(context),
          transitionsBuilder: (context, animation, _, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// Garis pemindai yang menyapu naik-turun di atas area (untuk status "sedang menganalisis").
class ScanSweep extends StatefulWidget {
  final Color color;
  const ScanSweep({super.key, this.color = AppTheme.accentBlue});

  @override
  State<ScanSweep> createState() => _ScanSweepState();
}

class _ScanSweepState extends State<ScanSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _SweepPainter(Curves.easeInOut.transform(_c.value), widget.color),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  final double t;
  final Color color;
  _SweepPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * t;
    final rect = Rect.fromLTWH(0, y - 36, size.width, 72);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..color = color..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) => old.t != t || old.color != color;
}

/// Sparkline tren (garis menggambar dirinya sendiri saat tampil).
class AnimatedSparkline extends StatelessWidget {
  final List<double> values; // 0..100
  final Color color;
  final double height;

  const AnimatedSparkline({super.key, required this.values, this.color = AppTheme.slateBlue, this.height = 56});

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Butuh minimal 2 hari data untuk tren', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ),
      );
    }
    final reduce = _reduceMotion(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: reduce ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (context, p, _) => CustomPaint(painter: _SparkPainter(values, color, p)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  final Color color;
  final double progress;
  _SparkPainter(this.v, this.color, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final pts = <Offset>[
      for (int i = 0; i < v.length; i++) Offset(pad + w * i / (v.length - 1), pad + h * (1 - (v[i].clamp(0, 100)) / 100)),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final mid = (pts[i - 1].dx + pts[i].dx) / 2;
      path.cubicTo(mid, pts[i - 1].dy, mid, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);

    final fill = Path.from(drawn);
    final tip = metric.getTangentForOffset(metric.length * progress)?.position ?? pts.last;
    fill.lineTo(tip.dx, size.height);
    fill.lineTo(pts.first.dx, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tip, 4, Paint()..color = color);
    canvas.drawCircle(tip, 7, Paint()..color = color.withValues(alpha: 0.2));
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.progress != progress || old.v != v || old.color != color;
}
