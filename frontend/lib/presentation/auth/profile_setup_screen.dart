import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/core/constants/yemeni_cities.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/merchant_category_service.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/presentation/dashboard/customer_dashboard_screen.dart';
import 'package:she_m_app/presentation/auth/auth_loading_overlay.dart';
import 'package:she_m_app/presentation/auth/platform_policy_screen.dart';
import 'package:she_m_app/presentation/checkout/delivery_address_screen.dart';
import 'package:she_m_app/presentation/common/role_dashboard_router.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String? phone;
  final UserModel? existingProfile;
  final bool returnToCheckout;
  final Set<String>? checkoutProductIds;

  const ProfileSetupScreen({
    super.key,
    this.phone,
    this.existingProfile,
    this.returnToCheckout = false,
    this.checkoutProductIds,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _currentLocationController =
      TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _merchantCategoryController =
      TextEditingController();
  final TextEditingController _merchantNameController = TextEditingController();
  final TextEditingController _merchantLocationController =
      TextEditingController();
  final TextEditingController _vehicleTypeController = TextEditingController();
  final TextEditingController _plateNumberController = TextEditingController();
  final AuthService _authService = AuthService();
  final MerchantCategoryService _merchantCategoryService =
      MerchantCategoryService();
  late Future<List<String>> _merchantCategoriesFuture;
  String _selectedRole = 'customer';
  String _licensePhotoPath = '';
  bool _saved = false;
  bool _isLoading = false;
  bool _isSendingOtp = false;
  bool _isLocating = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _acceptedPlatformAgreement = false;

  @override
  void initState() {
    super.initState();
    _merchantCategoriesFuture = _merchantCategoryService.getActiveCategories();
    _phoneController.text = widget.phone ?? '';
    _fullNameController.text = widget.existingProfile?.fullName ?? '';
    _cityController.text = widget.existingProfile?.city ?? '';
    _addressController.text = widget.existingProfile?.address ?? '';
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _currentLocationController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _merchantCategoryController.dispose();
    _merchantNameController.dispose();
    _merchantLocationController.dispose();
    _vehicleTypeController.dispose();
    _plateNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickLicensePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      _licensePhotoPath = picked.path;
    });
  }

  Future<void> _openPlatformPolicy() async {
    await Navigator.of(context).push(
      slideFadeRoute(page: const PlatformPolicyScreen()),
    );
  }

  Future<void> _useCurrentLocationForController(
    TextEditingController controller,
    String successMessage,
  ) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        final opened = await Geolocator.openLocationSettings();
        if (!opened) {
          throw StateError('يرجى تفعيل خدمة الموقع من إعدادات الجهاز');
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError('يرجى السماح للتطبيق بالوصول إلى موقعك');
      }
      if (permission == LocationPermission.deniedForever) {
        final opened = await Geolocator.openAppSettings();
        if (!opened) {
          throw StateError(
              'تم رفض الوصول إلى الموقع بشكل دائم. افتح الإعدادات يدوياً');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      controller.text =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorMessage.from(error))),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    await _useCurrentLocationForController(
      _merchantLocationController,
      'تم تحديد موقع المتجر الحالي تلقائيًا',
    );
  }

  Future<void> _openGoogleMapsForController(
    TextEditingController controller,
    String fallbackQuery,
  ) async {
    final location = controller.text.trim();
    final query = location.isEmpty ? fallbackQuery : location;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح خرائط Google')),
      );
    }
  }

  Future<void> _openGoogleMaps() async {
    await _openGoogleMapsForController(
      _merchantLocationController,
      'موقعي الحالي',
    );
  }

  Future<bool> _verifyPhoneOwnership(String phone) async {
    setState(() => _isSendingOtp = true);
    late final Map<String, dynamic> request;
    try {
      request = await _authService.requestOtp(
        phone: phone,
        forSignup: true,
      );
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorMessage.from(error))),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
    if (!mounted) return false;
    if (request['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            request['error']?.toString() ?? 'تعذر إرسال رمز التحقق',
          ),
        ),
      );
      return false;
    }

    final codeController = TextEditingController();
    var isVerifying = false;
    var isResending = false;
    var verificationError = '';
    String? resendMessage;
    var resendSucceeded = false;

    try {
      while (true) {
        final verified = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> verifyCode() async {
                final code = codeController.text.trim();
                if (code.isNotEmpty &&
                    (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code))) {
                  setDialogState(() =>
                      verificationError = 'رمز التحقق يجب أن يتكون من 6 أرقام');
                  return;
                }

                setDialogState(() {
                  isVerifying = true;
                  verificationError = '';
                  resendMessage = null;
                });
                final result = await _authService.verifyOtp(
                  phone: phone,
                  otp: code,
                );
                isVerifying = false;
                if (!dialogContext.mounted) return;
                if (result['success'] == true) {
                  Navigator.of(dialogContext).pop(true);
                  return;
                }
                setDialogState(() => verificationError =
                    result['error']?.toString() ?? 'رمز التحقق غير صحيح');
              }

              Future<void> resendCode() async {
                setDialogState(() {
                  isVerifying = true;
                  isResending = true;
                  verificationError = '';
                  resendMessage = null;
                });
                final result = await _authService.requestOtp(
                  phone: phone,
                  forSignup: true,
                );
                isVerifying = false;
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  isVerifying = false;
                  isResending = false;
                  resendSucceeded = result['success'] == true;
                  if (resendSucceeded) {
                    resendMessage = 'تم إرسال رمز جديد إلى واتساب';
                  } else {
                    verificationError =
                        result['error']?.toString() ?? 'تعذر إعادة إرسال الرمز';
                  }
                });
              }

              return AlertDialog(
                title: const Text('تأكيد ملكية رقم الهاتف'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'أرسلنا رمز تحقق عبر واتساب إلى $phone. أدخل الرمز لإكمال التحقق.',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8EA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE8DDD0)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.mark_chat_unread_rounded,
                            color: Color(0xFF8B6A27),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'افتح واتساب وتفقّد الرسائل، وقد يستغرق وصول الرمز لحظات. اترك هذه الشاشة مفتوحة.',
                              style: TextStyle(
                                color: Color(0xFF5F4A24),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeController,
                      autofocus: true,
                      enabled: !isVerifying,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: 'رمز التحقق',
                        counterText: '',
                        errorText: verificationError.isEmpty
                            ? null
                            : verificationError,
                        prefixIcon: const Icon(Icons.verified_user_rounded),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => verifyCode(),
                    ),
                    if (resendMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        resendMessage!,
                        style: TextStyle(
                          color: resendSucceeded
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    TextButton.icon(
                      onPressed: isVerifying ? null : resendCode,
                      icon: isResending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        isResending
                            ? 'جارٍ إعادة إرسال الرمز...'
                            : 'إعادة إرسال الرمز',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isVerifying
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: isVerifying ? null : verifyCode,
                    child: isVerifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('تحقق وتابع'),
                  ),
                ],
              );
            },
          ),
        );
        if (verified != null) return verified;
        if (!mounted) return false;

        final shouldCancel = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('إلغاء التحقق؟'),
            content: const Text(
              'هل تريد إغلاق شاشة إدخال رمز التحقق؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('متابعة إدخال الرمز'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('إغلاق الشاشة'),
              ),
            ],
          ),
        );
        if (shouldCancel == true) return false;
        if (!mounted) return false;
      }
    } finally {
      codeController.dispose();
    }
  }

  Future<void> _saveProfile() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final city = _cityController.text.trim();
    final address = _addressController.text.trim();
    final rawPhone = _phoneController.text.trim();
    String password = _passwordController.text.trim();
    String confirmedPassword = _confirmPasswordController.text.trim();
    final phone = _authService.normalizePhone(rawPhone);

    if (fullName.isEmpty || city.isEmpty || rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('يرجى ملء الاسم والهاتف والمدينة والبيانات المطلوبة')),
      );
      return;
    }

    if (_selectedRole == 'customer' && address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال تفاصيل عنوان التوصيل')),
      );
      return;
    }

    if (_selectedRole == 'merchant' && address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال تفاصيل عنوان المتجر')),
      );
      return;
    }

    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال بريد إلكتروني صحيح')),
      );
      return;
    }

    if (password.isEmpty && confirmedPassword.isEmpty) {
      password = 'SheM@1234';
      confirmedPassword = password;
      _passwordController.text = password;
      _confirmPasswordController.text = password;
    }

    if (!AppConstants.isStrongPassword(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كلمة المرور يجب ألا تقل عن 6 أحرف')),
      );
      return;
    }

    if (password != confirmedPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تأكيد كلمة المرور غير متطابق')),
      );
      return;
    }

    if (!AppConstants.isYemenPhoneValid(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رقم هاتف يمني صحيح')),
      );
      return;
    }

    if (_selectedRole == 'merchant') {
      final storeName = _merchantNameController.text.trim();
      if (storeName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال اسم المتجر')),
        );
        return;
      }
    }

    if (_selectedRole == 'driver') {
      final vehicleType = _vehicleTypeController.text.trim();
      final plate = _plateNumberController.text.trim();
      if (vehicleType.isEmpty || plate.isEmpty || _licensePhotoPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('يرجى إدخال نوع المركبة ورقم اللوحة ورفع صورة الرخصة')),
        );
        return;
      }
    }

    if (!_acceptedPlatformAgreement) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى الموافقة على اتفاقية التعامل مع منصة شيم'),
        ),
      );
      return;
    }

    if (AppConstants.requirePhoneVerificationOnSignup) {
      final phoneVerified = await _verifyPhoneOwnership(phone);
      if (!mounted || !phoneVerified) return;
    }

    setState(() => _isLoading = true);

    final role = _selectedRole;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);

    final result = widget.existingProfile != null
        ? await _authService.completeGoogleProfile(
            profile: widget.existingProfile!,
            phone: phone,
            city: city,
            address: address,
            currentLocation: _currentLocationController.text.trim(),
          )
        : await _authService.registerUser(
            fullName: fullName,
            email: email,
            phone: phone,
            role: role,
            city: city,
            address: address,
            currentLocation: _currentLocationController.text.trim(),
            password: password,
            shopCategory: _merchantCategoryController.text.trim(),
            shopName: _merchantNameController.text.trim(),
            shopLocation: _merchantLocationController.text.trim(),
            vehicleType: _vehicleTypeController.text.trim(),
            plateNumber: _plateNumberController.text.trim(),
            licensePhotoPath: _licensePhotoPath,
          );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result == null) {
      final errorMessage =
          _authService.lastError ?? 'تعذر حفظ الملف الشخصي في قاعدة البيانات';
      messenger?.showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      return;
    }

    if (widget.existingProfile == null && email.isNotEmpty) {
      final verified = await _confirmEmailVerification(email);
      if (!mounted || !verified) return;
    }

    setState(() => _saved = true);

    await _authService.saveSession(result);
    await _authService.rememberCurrentAccount(result);
    await CartService.instance.loadForUser(result.id);

    messenger?.showSnackBar(
      const SnackBar(content: Text('تم إنشاء الحساب بنجاح')),
    );

    if (!mounted) return;

    if (widget.returnToCheckout && result.role == 'customer') {
      navigator.pushReplacement(
        slideFadeRoute(
          page: widget.checkoutProductIds == null
              ? const CustomerDashboardScreen(showCartPrompt: true)
              : DeliveryAddressScreen(
                  selectedProductIds: widget.checkoutProductIds,
                ),
        ),
      );
      return;
    }

    final target = dashboardForRole(result.role);

    navigator.pushAndRemoveUntil(
      slideFadeRoute(page: target),
      (route) => false,
    );
  }

  Future<bool> _confirmEmailVerification(String email) async {
    var isBusy = false;
    var message = 'أرسلنا رسالة تحقق إلى $email';

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> checkVerification() async {
            setDialogState(() => isBusy = true);
            final isVerified = await _authService.isCurrentEmailVerified();
            if (!dialogContext.mounted) return;
            if (isVerified) {
              Navigator.of(dialogContext).pop(true);
              return;
            }
            setDialogState(() {
              isBusy = false;
              message = 'لم يتم تأكيد البريد بعد. افتح الرسالة ثم اضغط تحقق.';
            });
          }

          Future<void> resendVerification() async {
            setDialogState(() => isBusy = true);
            final sent = await _authService.resendEmailVerification();
            if (!dialogContext.mounted) return;
            setDialogState(() {
              isBusy = false;
              message = sent
                  ? 'تم إرسال رسالة تحقق جديدة إلى $email'
                  : 'تعذر إرسال الرسالة، حاول مرة أخرى';
            });
          }

          return AlertDialog(
            title: const Text('تأكيد البريد الإلكتروني'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: isBusy ? null : resendVerification,
                child: const Text('إعادة الإرسال'),
              ),
              FilledButton(
                onPressed: isBusy ? null : checkVerification,
                child: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('تحققت من البريد'),
              ),
            ],
          );
        },
      ),
    );

    if (verified != true) {
      await _authService.signOutFirebaseOnly();
    }
    return verified == true;
  }

  @override
  Widget build(BuildContext context) {
    final isMerchant = _selectedRole == 'merchant';
    final isDriver = _selectedRole == 'driver';
    final roleTitle = switch (_selectedRole) {
      'merchant' => 'حساب تاجر',
      'driver' => 'حساب سائق',
      _ => 'حساب عميل',
    };
    final roleSubtitle = switch (_selectedRole) {
      'merchant' => 'اعرض منتجاتك واستقبل طلبات العملاء بسهولة.',
      'driver' => 'انضم إلى شبكة التوصيل وابدأ باستقبال الطلبات.',
      _ => 'تسوق واكتشف المنتجات التي تناسبك.',
    };

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1B120C),
          foregroundColor: Colors.white,
          title: const Text('الانضمام إلى She M'),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1B120C), Color(0xFF2A1C14)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFB69449)
                                          .withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                      color: Color(0xFFB69449),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'إنشاء حساب جديد',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          roleSubtitle,
                                          style: const TextStyle(
                                            color: Color(0xFFEAD8B8),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'نوع الحساب',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B120C),
                                ),
                              ),
                            ),
                            Text(
                              roleTitle,
                              style: const TextStyle(
                                color: Color(0xFF8B6A27),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const <ButtonSegment<String>>[
                            ButtonSegment<String>(
                              value: 'customer',
                              label: Text('عميل'),
                              icon: Icon(Icons.person_rounded),
                            ),
                            ButtonSegment<String>(
                              value: 'merchant',
                              label: Text('تاجر'),
                              icon: Icon(Icons.storefront_rounded),
                            ),
                            ButtonSegment<String>(
                              value: 'driver',
                              label: Text('سائق'),
                              icon: Icon(Icons.delivery_dining_rounded),
                            ),
                          ],
                          selected: {_selectedRole},
                          onSelectionChanged: (Set<String> selection) {
                            setState(() {
                              _selectedRole = selection.first;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          roleSubtitle,
                          style: const TextStyle(
                            color: Color(0xFF766A60),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _FieldSection(
                          title: 'البيانات الأساسية',
                          icon: Icons.person_rounded,
                          children: [
                            _StyledField(
                              keyName: 'full_name_field',
                              controller: _fullNameController,
                              hint: 'الاسم الكامل',
                              icon: Icons.person_rounded,
                            ),
                            if (widget.existingProfile == null) ...[
                              const SizedBox(height: 12),
                              _StyledField(
                                keyName: 'email_field',
                                controller: _emailController,
                                hint: 'البريد الإلكتروني (اختياري)',
                                icon: Icons.email_rounded,
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ],
                            const SizedBox(height: 12),
                            _StyledField(
                              keyName: 'phone_field',
                              controller: _phoneController,
                              hint: 'رقم الهاتف',
                              icon: Icons.phone_rounded,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 12),
                            _StyledField(
                              keyName: 'city_field',
                              controller: _cityController,
                              hint: 'اختر المدينة',
                              icon: Icons.location_city_rounded,
                              options: yemeniCities,
                            ),
                            if (!isMerchant && !isDriver) ...[
                              const SizedBox(height: 12),
                              _StyledField(
                                keyName: 'address_details_field',
                                controller: _addressController,
                                hint: 'تفاصيل عنوان التوصيل (مطلوب)',
                                icon: Icons.location_on_rounded,
                                maxLines: 3,
                              ),
                              const SizedBox(height: 12),
                              _StyledField(
                                keyName: 'current_location_field',
                                controller: _currentLocationController,
                                hint: 'الموقع الحالي (يُحدد تلقائيًا)',
                                icon: Icons.my_location_rounded,
                                readOnly: true,
                                suffixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF7A6A5C),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isLocating
                                      ? null
                                      : () => _useCurrentLocationForController(
                                            _currentLocationController,
                                            'تم تحديد موقعك الحالي تلقائيًا',
                                          ),
                                  icon: _isLocating
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.my_location_rounded),
                                  label: Text(
                                    _isLocating
                                        ? 'جارٍ تحديد الموقع...'
                                        : 'تحديد موقعي تلقائيًا',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            _StyledField(
                              keyName: 'password_field',
                              controller: _passwordController,
                              hint: 'كلمة المرور',
                              icon: Icons.lock_rounded,
                              obscureText: !_showPassword,
                              suffixIcon: IconButton(
                                tooltip: _showPassword
                                    ? 'إخفاء كلمة المرور'
                                    : 'إظهار كلمة المرور',
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                                icon: Icon(_showPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _StyledField(
                              keyName: 'confirm_password_field',
                              controller: _confirmPasswordController,
                              hint: 'تأكيد كلمة المرور',
                              icon: Icons.lock_reset_rounded,
                              obscureText: !_showConfirmPassword,
                              suffixIcon: IconButton(
                                tooltip: _showConfirmPassword
                                    ? 'إخفاء كلمة المرور'
                                    : 'إظهار كلمة المرور',
                                onPressed: () => setState(() =>
                                    _showConfirmPassword =
                                        !_showConfirmPassword),
                                icon: Icon(_showConfirmPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded),
                              ),
                            ),
                          ],
                        ),
                        if (isMerchant) ...[
                          const SizedBox(height: 20),
                          FutureBuilder<List<String>>(
                            future: _merchantCategoriesFuture,
                            builder: (context, snapshot) {
                              final categories =
                                  snapshot.data ?? const <String>[];
                              final selectedCategory = categories.contains(
                                      _merchantCategoryController.text.trim())
                                  ? _merchantCategoryController.text.trim()
                                  : null;

                              return _FieldSection(
                                title: 'معلومات المتجر',
                                icon: Icons.storefront_rounded,
                                children: [
                                  const Text(
                                    'فئة المتجر',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1B120C),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                        'merchant_category_field'),
                                    initialValue: selectedCategory,
                                    isExpanded: true,
                                    hint: Text(
                                      snapshot.connectionState ==
                                              ConnectionState.waiting
                                          ? 'جاري تحميل فئات المتاجر...'
                                          : categories.isEmpty
                                              ? 'اختر فئة المتجر (اختياري)'
                                              : 'اختر فئة المتجر (اختياري)',
                                    ),
                                    items: categories
                                        .map(
                                          (category) =>
                                              DropdownMenuItem<String>(
                                            value: category,
                                            child: Text(category),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: categories.isEmpty
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              setState(() {
                                                _merchantCategoryController
                                                    .text = value;
                                              });
                                            }
                                          },
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFF7F3EE),
                                      prefixIcon: const Icon(
                                        Icons.category_rounded,
                                        color: Color(0xFF1B120C),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'اسم المتجر',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1B120C),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _StyledField(
                                    keyName: 'merchant_name_field',
                                    controller: _merchantNameController,
                                    hint: 'اسم المتجر',
                                    icon: Icons.store_mall_directory_rounded,
                                  ),
                                  const SizedBox(height: 12),
                                  _StyledField(
                                    keyName: 'address_details_field',
                                    controller: _addressController,
                                    hint: 'تفاصيل عنوان المتجر (مطلوب)',
                                    icon: Icons.location_on_rounded,
                                    maxLines: 3,
                                  ),
                                  const SizedBox(height: 12),
                                  _StyledField(
                                    keyName: 'merchant_location_field',
                                    controller: _merchantLocationController,
                                    hint: 'موقع المتجر الحالي (اختياري)',
                                    icon: Icons.location_on_rounded,
                                    maxLines: 2,
                                    readOnly: true,
                                    onTap: _isLocating
                                        ? null
                                        : _useCurrentLocation,
                                    suffixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: Color(0xFF7A6A5C),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: _isLocating
                                        ? null
                                        : _useCurrentLocation,
                                    icon: _isLocating
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.my_location_rounded,
                                          ),
                                    label: Text(
                                      _isLocating
                                          ? 'جارٍ تحديد الموقع...'
                                          : 'الموقع الحالي',
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                        if (isDriver) ...[
                          const SizedBox(height: 20),
                          _FieldSection(
                            title: 'بيانات السائق',
                            icon: Icons.delivery_dining_rounded,
                            children: [
                              _StyledField(
                                keyName: 'vehicle_type_field',
                                controller: _vehicleTypeController,
                                hint: 'نوع المركبة',
                                icon: Icons.directions_car_rounded,
                              ),
                              const SizedBox(height: 12),
                              _StyledField(
                                keyName: 'plate_number_field',
                                controller: _plateNumberController,
                                hint: 'رقم اللوحة',
                                icon: Icons.confirmation_number_rounded,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _pickLicensePhoto,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1B120C),
                                    side: const BorderSide(
                                      color: Color(0xFFB69449),
                                      width: 1.5,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  icon: const Icon(Icons.upload_file_rounded),
                                  label: Text(
                                    _licensePhotoPath.isEmpty
                                        ? 'رفع صورة الرخصة'
                                        : 'تم اختيار صورة الرخصة',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        Card(
                          key: const ValueKey('platform_agreement_card'),
                          margin: EdgeInsets.zero,
                          color: const Color(0xFFF7F3EE),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFE8DDD0)),
                          ),
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: 8,
                              end: 12,
                              top: 8,
                              bottom: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextButton.icon(
                                  key: const ValueKey('read_platform_policy'),
                                  onPressed: _openPlatformPolicy,
                                  icon: const Icon(Icons.policy_outlined),
                                  label: const Text(
                                    'قراءة سياسة الاستخدام والخصوصية',
                                  ),
                                  style: TextButton.styleFrom(
                                    alignment: AlignmentDirectional.centerStart,
                                    foregroundColor: const Color(0xFF8B6A27),
                                  ),
                                ),
                                CheckboxListTile(
                                  key: const ValueKey(
                                    'platform_agreement_checkbox',
                                  ),
                                  value: _acceptedPlatformAgreement,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: const Color(0xFF1B120C),
                                  onChanged: (accepted) {
                                    setState(() {
                                      _acceptedPlatformAgreement =
                                          accepted ?? false;
                                    });
                                  },
                                  title: const Text(
                                    'أوافق على اتفاقية التعامل مع منصة شيم '
                                    'وأتعهد بالالتزام بجميع الشروط والأحكام '
                                    'الواردة فيها.',
                                    style: TextStyle(
                                      color: Color(0xFF1B120C),
                                      fontSize: 14,
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading || _isSendingOtp
                                ? null
                                : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B120C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              _isLoading
                                  ? 'جاري إنشاء الحساب...'
                                  : 'إنشاء الحساب',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (_saved) ...[
                          const SizedBox(height: 16),
                          const Center(
                            child: Text(
                              'تم حفظ الملف الشخصي بنجاح',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_isLoading || _isSendingOtp)
              AuthLoadingOverlay(
                title: _isSendingOtp ? 'نرسل رمز التحقق' : 'مرحبًا بك في She M',
                subtitle: _isSendingOtp
                    ? 'نرسل الرمز إلى رقمك عبر واتساب. أبقِ الصفحة مفتوحة؛ ستظهر خانة إدخال الرمز فور اكتمال الإرسال.'
                    : 'ننشئ حسابك الآن ونجهز لك بداية مريحة.',
              ),
          ],
        ),
      ),
    );
  }
}

class _FieldSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _FieldSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8DDD0), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFB69449).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFFB69449), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B120C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final String keyName;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool readOnly;
  final int maxLines;
  final Widget? suffixIcon;
  final GestureTapCallback? onTap;
  final List<String>? options;

  const _StyledField({
    required this.keyName,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.suffixIcon,
    this.onTap,
    this.options,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF7A6A5C),
        fontSize: 15,
      ),
      filled: true,
      fillColor: const Color(0xFFF7F3EE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFB69449),
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF1B120C)),
      suffixIcon: suffixIcon,
    );

    if (options != null) {
      return DropdownButtonFormField<String>(
        key: ValueKey(keyName),
        initialValue:
            options!.contains(controller.text) ? controller.text : null,
        isExpanded: true,
        decoration: decoration,
        items: options!
            .map((option) => DropdownMenuItem(
                  value: option,
                  child: Text(option),
                ))
            .toList(),
        onChanged: (value) {
          if (value != null) controller.text = value;
        },
      );
    }

    return TextFormField(
      key: ValueKey(keyName),
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      readOnly: readOnly,
      showCursor: !readOnly,
      onTap: onTap,
      maxLines: maxLines,
      textAlign: TextAlign.right,
      decoration: decoration,
    );
  }
}
