import 'package:flutter/material.dart';

/// PillowyCard: Soft neu-skeuomorphic tactile container styled after Loop app
/// Features:
/// - Beveled top edge white highlight (inset-like look)
/// - Diffused soft sky ambient drop shadow
/// - Tactile scale micro-interaction on tap
class PillowyCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;
  final double borderRadius;
  final VoidCallback? onTap;

  const PillowyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor = Colors.white,
    this.borderColor = const Color(0xFFCBE2F4),
    this.borderRadius = 18,
    this.onTap,
  });

  @override
  State<PillowyCard> createState() => _PillowyCardState();
}

class _PillowyCardState extends State<PillowyCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: widget.onTap != null ? (_) => setState(() => _isPressed = false) : null,
      onTapCancel: widget.onTap != null ? () => setState(() => _isPressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.borderColor,
              width: 1.5,
            ),
            boxShadow: _isPressed
                ? [
                    const BoxShadow(
                      color: Color(0x1F52738D),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ]
                : [
                    const BoxShadow(
                      color: Color(0x1A52738D),
                      blurRadius: 14,
                      spreadRadius: 0,
                      offset: Offset(0, 6),
                    ),
                    const BoxShadow(
                      color: Color(0x0D52738D),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
