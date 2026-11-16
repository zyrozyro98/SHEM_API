import 'package:flutter/material.dart';

class AuthLoadingOverlay extends StatelessWidget {
  final String title;
  final String subtitle;

  const AuthLoadingOverlay({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.white,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.92, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) => Transform.scale(
                        scale: scale,
                        child: child,
                      ),
                      child: Container(
                        width: 152,
                        height: 152,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.all(
                            const Radius.circular(42),
                          ),
                          border: Border.all(
                            color: Color(0xFFB69449).withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF1B120C).withValues(alpha: 0.12),
                              blurRadius: 26,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.all(
                            const Radius.circular(34),
                          ),
                          child: const Image(
                            image: AssetImage('assets/icon/app_icon.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1B120C),
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6D6259),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SizedBox(
                      width: 124,
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(
                          Radius.circular(99),
                        ),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          backgroundColor: Color(0xFFE3D8CA),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFB69449),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'لحظات ونكون معك',
                      style: TextStyle(
                        color: Color(0xFF8D8074),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
