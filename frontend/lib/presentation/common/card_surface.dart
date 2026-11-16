import 'package:flutter/material.dart';
import 'package:she_m_app/core/theme/design_tokens.dart';

class CardSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const CardSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(12),
      this.radius = DesignTokens.radiusLarge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: DesignTokens.elevatedShadow,
      ),
      child: child,
    );
  }
}
