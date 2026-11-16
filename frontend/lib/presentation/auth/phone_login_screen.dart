import 'package:flutter/material.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/presentation/auth/profile_setup_screen.dart';
import 'package:she_m_app/presentation/auth/auth_loading_overlay.dart';
import 'package:she_m_app/presentation/dashboard/customer_dashboard_screen.dart';
import 'package:she_m_app/presentation/common/role_dashboard_router.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/presentation/checkout/delivery_address_screen.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({
    super.key,
    this.returnToCheckout = false,
    this.checkoutProductIds,
  });

  final bool returnToCheckout;
  final Set<String>? checkoutProductIds;

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _phoneFocusNode.addListener(_handlePhoneFocusChanged);
    _passwordFocusNode.addListener(_handlePasswordFocusChanged);
  }

  void _handlePhoneFocusChanged() =>
      _moveCursorToEndWhenFocused(_phoneFocusNode, _phoneController);

  void _handlePasswordFocusChanged() =>
      _moveCursorToEndWhenFocused(_passwordFocusNode, _passwordController);

  void _moveCursorToEndWhenFocused(
    FocusNode focusNode,
    TextEditingController controller,
  ) {
    if (focusNode.hasFocus) {
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }
  }

  Widget _checkoutDestination() {
    final productIds = widget.checkoutProductIds;
    if (productIds != null) {
      return DeliveryAddressScreen(selectedProductIds: productIds);
    }
    return const CustomerDashboardScreen(showCartPrompt: true);
  }

  @override
  void dispose() {
    _phoneFocusNode
      ..removeListener(_handlePhoneFocusChanged)
      ..dispose();
    _passwordFocusNode
      ..removeListener(_handlePasswordFocusChanged)
      ..dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithPassword() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    if (phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رقم الهاتف وكلمة المرور')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await _authService.loginWithEmailOrPhone(
      identifier: phone,
      password: password,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authService.lastError ??
                'بيانات الدخول غير صحيحة أو الحساب غير موجود',
          ),
        ),
      );
      return;
    }

    final savedProfile = await _authService.loadSession();
    if (!mounted) return;
    await CartService.instance.loadForUser(savedProfile?.id);
    if (!mounted) return;

    if (widget.returnToCheckout) {
      if (savedProfile?.role == 'customer') {
        Navigator.of(context).pushReplacement(
          slideFadeRoute(page: _checkoutDestination()),
        );
        return;
      }
    }

    final target = dashboardForRole(savedProfile?.role ?? 'customer');

    Navigator.of(context).pushAndRemoveUntil(
      slideFadeRoute(page: target),
      (route) => false,
    );
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    final profile = await _authService.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authService.lastError ?? 'تعذر تسجيل الدخول عبر Google',
          ),
        ),
      );
      return;
    }

    if (profile.needsCustomerProfileSetup) {
      Navigator.of(context).pushReplacement(
        slideFadeRoute(
          page: ProfileSetupScreen(
            existingProfile: profile,
            returnToCheckout: widget.returnToCheckout,
            checkoutProductIds: widget.checkoutProductIds,
          ),
        ),
      );
      return;
    }

    await CartService.instance.loadForUser(profile.id);
    if (!mounted) return;

    if (widget.returnToCheckout) {
      if (profile.role == 'customer') {
        Navigator.of(context).pushReplacement(
          slideFadeRoute(page: _checkoutDestination()),
        );
        return;
      }
    }

    final target = dashboardForRole(profile.role);

    Navigator.of(context).pushAndRemoveUntil(
      slideFadeRoute(page: target),
      (route) => false,
    );
  }

  Future<void> _continueWithoutOtp() async {
    final phone = _phoneController.text.trim();

    if (phone.isNotEmpty) {
      final normalizedPhone = _authService.normalizePhone(phone);
      Navigator.of(context).push(
        slideFadeRoute(
          page: ProfileSetupScreen(
            phone: normalizedPhone,
            returnToCheckout: widget.returnToCheckout,
            checkoutProductIds: widget.checkoutProductIds,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      slideFadeRoute(
        page: ProfileSetupScreen(
          returnToCheckout: widget.returnToCheckout,
          checkoutProductIds: widget.checkoutProductIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const darkBrown = Color(0xFF1B120C);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.08),
                            blurRadius: 22,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                'assets/icon/app_icon.png',
                                width: 170,
                                height: 170,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'مرحباً بعودتك',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: darkBrown,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'سجل دخولك للوصول إلى حسابك وطلبك الخاص',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF62584F),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _LoginField(
                            keyName: 'phone_number_field',
                            controller: _phoneController,
                            focusNode: _phoneFocusNode,
                            hint: 'رقم الهاتف',
                            icon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          _LoginField(
                            keyName: 'password_field',
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                            hint: 'كلمة المرور',
                            icon: Icons.lock_rounded,
                            obscureText: true,
                          ),
                          const SizedBox(height: 22),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _showPasswordReset,
                              child: const Text('نسيت كلمة المرور؟'),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 64,
                            child: ElevatedButton(
                              key: const ValueKey('send_otp_button'),
                              onPressed: _isLoading ? null : _loginWithPassword,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: darkBrown,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'تسجيل الدخول',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 64,
                            child: OutlinedButton(
                              key: const ValueKey('confirm_otp_button'),
                              onPressed:
                                  _isLoading ? null : _continueWithoutOtp,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: darkBrown,
                                side: const BorderSide(
                                    color: Color(0xFFB69449), width: 1.5),
                                backgroundColor: const Color(0xFFFFF8EA),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                'إنشاء حساب جديد',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 64,
                            child: OutlinedButton.icon(
                              key: const ValueKey('google_sign_in_button'),
                              onPressed: _isLoading ? null : _loginWithGoogle,
                              icon: const Text(
                                'G',
                                style: TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              label: const Text(
                                'المتابعة باستخدام Google',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: darkBrown,
                                side:
                                    const BorderSide(color: Color(0xFFD5D0CA)),
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const AuthLoadingOverlay(
                title: 'أهلًا بك في She M',
                subtitle: 'نجهز لك مساحتك الخاصة وننقلك إلى حسابك الآن.',
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasswordReset() async {
    final phoneController = TextEditingController(
      text: _phoneController.text.trim(),
    );
    final otpController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var step = 0;
    var isBusy = false;
    String? busyMessage;
    String? feedbackMessage;
    var feedbackIsSuccess = false;

    try {
      final completed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendCode() async {
              if (phoneController.text.trim().isEmpty) {
                setDialogState(() {
                  feedbackMessage = 'أدخل رقم الهاتف أولاً';
                  feedbackIsSuccess = false;
                });
                return;
              }
              setDialogState(() {
                isBusy = true;
                busyMessage = 'جارٍ التحقق من الرقم وإرسال الرمز عبر واتساب...';
                feedbackMessage = null;
              });
              otpController.clear();
              final result = await _authService.requestPasswordResetOtp(
                phone: phoneController.text,
              );
              if (!context.mounted) return;
              setDialogState(() {
                isBusy = false;
                busyMessage = null;
              });
              if (result['success'] == true) {
                otpController.clear();
                setDialogState(() {
                  step = 1;
                  feedbackIsSuccess = true;
                  feedbackMessage = result['message']?.toString() ??
                      'تم إرسال رمز التحقق عبر واتساب';
                });
              } else {
                setDialogState(() {
                  feedbackIsSuccess = false;
                  feedbackMessage =
                      result['error']?.toString() ?? 'تعذر إرسال رمز التحقق';
                });
              }
            }

            Future<void> verifyCode() async {
              setDialogState(() {
                isBusy = true;
                busyMessage = 'جارٍ التحقق من الرمز، يرجى الانتظار...';
                feedbackMessage = null;
              });
              final result = await _authService.verifyPasswordResetOtp(
                phone: phoneController.text,
                otp: otpController.text,
              );
              if (!context.mounted) return;
              setDialogState(() {
                isBusy = false;
                busyMessage = null;
              });
              if (result['success'] == true) {
                setDialogState(() {
                  step = 2;
                  feedbackIsSuccess = true;
                  feedbackMessage =
                      'تم التحقق من الرمز بنجاح. أدخل كلمة المرور الجديدة.';
                });
              } else {
                setDialogState(() {
                  feedbackIsSuccess = false;
                  feedbackMessage =
                      result['error']?.toString() ?? 'رمز التحقق غير صحيح';
                });
              }
            }

            Future<void> resetPassword() async {
              if (passwordController.text != confirmController.text) {
                setDialogState(() {
                  feedbackIsSuccess = false;
                  feedbackMessage = 'كلمتا المرور غير متطابقتين';
                });
                return;
              }
              setDialogState(() {
                isBusy = true;
                busyMessage = 'جارٍ تحديث كلمة المرور بأمان...';
                feedbackMessage = null;
              });
              final result = await _authService.resetPasswordWithOtp(
                phone: phoneController.text,
                newPassword: passwordController.text,
              );
              if (!context.mounted) return;
              setDialogState(() {
                isBusy = false;
                busyMessage = null;
              });
              if (result['success'] == true) {
                Navigator.pop(dialogContext, true);
              } else {
                setDialogState(() {
                  feedbackIsSuccess = false;
                  feedbackMessage =
                      result['error']?.toString() ?? 'تعذر تغيير كلمة المرور';
                });
              }
            }

            return AlertDialog(
              title: Text(
                step == 0 ? 'استعادة كلمة المرور' : 'تغيير كلمة المرور',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBusy && busyMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8EA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE9D9B6)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF8A6A32),
                                semanticsLabel: 'جارٍ تنفيذ الطلب',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                busyMessage!,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: Color(0xFF62584F),
                                  fontWeight: FontWeight.w600,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (feedbackMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: feedbackIsSuccess
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          feedbackMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: feedbackIsSuccess
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (step == 0)
                      TextField(
                        controller: phoneController,
                        enabled: !isBusy,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                      )
                    else if (step == 1) ...[
                      Text(
                        'أدخل الرمز المرسل عبر واتساب إلى '
                        '${phoneController.text.trim()}. قد يستغرق وصوله بضع لحظات.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: otpController,
                        enabled: !isBusy,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'رمز التحقق',
                          prefixIcon: Icon(Icons.verified_user_rounded),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: isBusy ? null : sendCode,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('إعادة إرسال الرمز'),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'تم التحقق من رقم ${phoneController.text.trim()}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        enabled: !isBusy,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور الجديدة',
                          prefixIcon: Icon(Icons.lock_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: confirmController,
                        enabled: !isBusy,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد كلمة المرور الجديدة',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isBusy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: isBusy
                      ? null
                      : (step == 0
                          ? sendCode
                          : step == 1
                              ? verifyCode
                              : resetPassword),
                  child: isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          step == 0
                              ? 'إرسال الرمز'
                              : step == 1
                                  ? 'تحقق من الرمز'
                                  : 'تغيير كلمة المرور',
                        ),
                ),
              ],
            );
          },
        ),
      );
      if (completed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
        );
      }
    } finally {
      phoneController.dispose();
      otpController.dispose();
      passwordController.dispose();
      confirmController.dispose();
    }
  }
}

class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(220, 220),
      painter: _LuxuryBagLogoPainter(),
    );
  }
}

class _LuxuryBagLogoPainter extends CustomPainter {
  const _LuxuryBagLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const gold = Color(0xFFB69449);
    const dark = Color(0xFF171412);
    const white = Color(0xFFF5F5F5);

    final outerPaint = Paint()
      ..color = dark
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bagPaint = Paint()
      ..color = dark
      ..style = PaintingStyle.fill;

    final arcPaint = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(12, 12, size.width - 24, size.height - 24),
      const Radius.circular(36),
    );
    canvas.drawRRect(outer, outerPaint);
    canvas.drawRRect(outer, borderPaint);

    final bagRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(36, 86, size.width - 72, 96),
      const Radius.circular(22),
    );
    canvas.drawRRect(bagRect, bagPaint);
    canvas.drawRRect(bagRect, borderPaint);

    final handle = Path()
      ..moveTo(62, 92)
      ..quadraticBezierTo(34, 48, 86, 34)
      ..quadraticBezierTo(122, 20, 156, 36)
      ..quadraticBezierTo(190, 52, 180, 92);
    canvas.drawPath(handle, borderPaint);

    final lowerBase = Path()
      ..moveTo(44, 176)
      ..lineTo(176, 176);
    canvas.drawPath(lowerBase, borderPaint);

    final motionPath = Path()
      ..moveTo(20, 110)
      ..quadraticBezierTo(0, 110, 0, 92)
      ..moveTo(30, 132)
      ..quadraticBezierTo(4, 132, 4, 116)
      ..moveTo(34, 154)
      ..quadraticBezierTo(14, 154, 14, 146);
    canvas.drawPath(motionPath, arcPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'SHE',
        style: TextStyle(
          color: white,
          fontSize: 40,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    textPainter.paint(
        canvas, Offset((size.width - textPainter.width) / 2, 148));

    final largeM = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(
          color: gold,
          fontSize: 96,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    largeM.paint(canvas, Offset((size.width - largeM.width) / 2, 92));

    final goldStripes = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawLine(
      const Offset(34, 176),
      const Offset(86, 176),
      goldStripes,
    );
    canvas.drawLine(
      const Offset(136, 176),
      const Offset(188, 176),
      goldStripes,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoginField extends StatelessWidget {
  final String? keyName;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;

  const _LoginField({
    this.keyName,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8DDD0), width: 1.2),
      ),
      child: TextFormField(
        key: keyName != null ? ValueKey(keyName) : null,
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: Color(0xFF1B120C),
          fontSize: 18,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0xFF7A6A5C),
            fontSize: 16,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          prefixIcon: Icon(icon, color: const Color(0xFF1B120C)),
        ),
      ),
    );
  }
}
