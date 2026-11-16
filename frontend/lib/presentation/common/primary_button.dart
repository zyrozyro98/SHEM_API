import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:she_m_app/core/theme/design_tokens.dart';

class PrimaryButton extends StatefulWidget {
  final String label;
  final FutureOr<void> Function() onPressed;
  final Widget? leading;

  const PrimaryButton(
      {super.key, required this.label, required this.onPressed, this.leading});

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  bool _isProcessing = false;

  void _onTapDown(TapDownDetails _) {
    setState(() => _scale = 0.97);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _scale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  Future<void> _handlePressed() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = kIsWeb ||
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
              gradient: const LinearGradient(
                colors: [Color(0xFFD4AF37), Color(0xFFE8C967)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: _scale < 1.0
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDesktop ? 0.12 : 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
            ),
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _handlePressed,
              icon: widget.leading ?? const SizedBox.shrink(),
              label: Text(widget.label),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.black,
                shadowColor: Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusMedium)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
