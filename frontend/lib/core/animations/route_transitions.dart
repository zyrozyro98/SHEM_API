import 'package:flutter/material.dart';

class AnimatedIndexedStack extends StatelessWidget {
  const AnimatedIndexedStack({
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 240),
    this.slideOffset = 0.025,
    super.key,
  });

  final int index;
  final List<Widget> children;
  final Duration duration;
  final double slideOffset;

  @override
  Widget build(BuildContext context) {
    final effectiveDuration =
        MediaQuery.of(context).disableAnimations ? Duration.zero : duration;

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var childIndex = 0; childIndex < children.length; childIndex++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: childIndex != index,
              child: ExcludeSemantics(
                excluding: childIndex != index,
                child: AnimatedOpacity(
                  key: ValueKey('animated-indexed-stack-$childIndex'),
                  opacity: childIndex == index ? 1 : 0,
                  duration: effectiveDuration,
                  curve: Curves.easeOutCubic,
                  child: AnimatedSlide(
                    offset: childIndex == index
                        ? Offset.zero
                        : Offset(0, slideOffset),
                    duration: effectiveDuration,
                    curve: Curves.easeOutCubic,
                    child: TickerMode(
                      enabled: childIndex == index,
                      child: children[childIndex],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

PageRouteBuilder<T> slideFadeRoute<T>(
    {required Widget page, Offset begin = const Offset(0.0, 0.08)}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final offsetAnimation =
          Tween<Offset>(begin: begin, end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      );
      final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOut),
      );
      return SlideTransition(
        position: offsetAnimation,
        child: FadeTransition(opacity: fadeAnimation, child: child),
      );
    },
    transitionDuration: const Duration(milliseconds: 280),
  );
}
