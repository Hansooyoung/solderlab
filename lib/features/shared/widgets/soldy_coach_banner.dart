import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import 'soldy_avatar_animated.dart';

/// Kartu pendamping interaktif **Soldy AI** yang bisa diketuk pengguna untuk mengganti
/// kiat teknik menyolder, penjelasan kualitas IPC, atau konteks hasil analisis terkini.
class SoldyCoachBanner extends StatefulWidget {
  final SoldyMood mood;
  final String badge;
  final List<String> messages;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final Color? backgroundColor;
  final Color? borderColor;

  const SoldyCoachBanner({
    super.key,
    this.mood = SoldyMood.idle,
    required this.badge,
    required this.messages,
    this.actionLabel,
    this.onActionTap,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  State<SoldyCoachBanner> createState() => _SoldyCoachBannerState();
}

class _SoldyCoachBannerState extends State<SoldyCoachBanner> {
  int _msgIndex = 0;

  void _cycleTip() {
    if (widget.messages.length <= 1) return;
    HapticFeedback.lightImpact();
    setState(() {
      _msgIndex = (_msgIndex + 1) % widget.messages.length;
    });
  }

  @override
  void didUpdateWidget(covariant SoldyCoachBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length) {
      _msgIndex = 0;
    }
  }

  Color _accentForMood() {
    switch (widget.mood) {
      case SoldyMood.happy:
        return AppTheme.passGreen;
      case SoldyMood.warning:
        return const Color(0xFFB45309);
      case SoldyMood.alert:
        return AppTheme.failRed;
      case SoldyMood.inspecting:
        return AppTheme.slateBlue;
      case SoldyMood.idle:
        return AppTheme.slateBlueDark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeMsgs = widget.messages.isEmpty
        ? const ['Soldy AI siap membantu pemeriksaan solder Anda.']
        : widget.messages;
    final currentMsg = safeMsgs[_msgIndex % safeMsgs.length];
    final hasMultiple = safeMsgs.length > 1;
    final accent = _accentForMood();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasMultiple ? _cycleTip : null,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.cardDecoration(
            backgroundColor: widget.backgroundColor ?? AppTheme.softSky,
            borderColor: widget.borderColor ?? AppTheme.softSkyBorder,
            radius: 18,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SoldyAvatarAnimated(
                size: 56,
                mood: widget.mood,
                onTap: _cycleTip,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 11,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        widget.badge,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: accent,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (hasMultiple)
                              Text(
                                'Ketuk tip (${(_msgIndex % safeMsgs.length) + 1}/${safeMsgs.length})',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slateBlue,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        currentMsg,
                        key: ValueKey('msg_${_msgIndex}_${currentMsg.hashCode}'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (widget.actionLabel != null && widget.onActionTap != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onActionTap,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.white,
                            foregroundColor: accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: accent.withValues(alpha: 0.3)),
                            ),
                          ),
                          icon: const Icon(Icons.chevron_right_rounded, size: 15),
                          label: Text(
                            widget.actionLabel!,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
