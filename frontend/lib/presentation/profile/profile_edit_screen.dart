import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/presentation/common/delivery_address_book.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    this.initialProfile,
    this.authService,
  });

  final UserModel? initialProfile;
  final AuthService? authService;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  String? _profileImageData;
  String _profileFullName = '';
  UserModel? _profile;
  List<DeliveryAddress> _deliveryAddresses = [];
  String? _selectedDeliveryAddressId;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _currentPasswordController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (pickedFile == null) return;

      final bytes = await File(pickedFile.path).readAsBytes();
      final compressed = await MediaUploadService.compactImageBytes(
        bytes,
        maxWidth: 512,
        maxHeight: 512,
        targetSizeBytes: 180000,
        quality: 68,
      );

      if (!mounted) return;
      if (compressed == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('تعذر ضغط الصورة المحددة')),
        );
        return;
      }

      final imageUrl = await MediaUploadService.uploadImage(
        compressed,
        fileName: pickedFile.name,
        mediaType: 'profiles',
      );
      if (!mounted) return;
      if (imageUrl == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('تعذر رفع صورة الملف الشخصي')),
        );
        return;
      }
      setState(() => _profileImageData = imageUrl);
    } catch (_) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('تعذر اختيار صورة الملف الشخصي')),
      );
    }
  }

  Future<void> _loadProfile() async {
    final profile = widget.initialProfile ??
        await _authService.loadSession() ??
        await _authService.getCurrentProfile();
    if (!mounted) return;

    if (profile == null) {
      setState(() => _isLoading = false);
      return;
    }

    _profileFullName = profile.fullName;
    _profile = profile;
    _deliveryAddresses = profile.savedDeliveryAddresses;
    _selectedDeliveryAddressId = profile.selectedDeliveryAddress?.id;
    _emailController.text = profile.email ?? '';
    _phoneController.text = profile.phone;
    _cityController.text = profile.city ?? '';
    _addressController.text = profile.address ?? '';
    _profileImageData = profile.profileImageData;

    setState(() => _isLoading = false);
  }

  Future<bool> _verifyPhoneChange(String phone) async {
    final request = await _authService.requestOtp(
      phone: phone,
      updatePhoneOnCurrentUser: true,
    );
    if (!mounted) return false;
    if (request['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(request['error']?.toString() ?? 'تعذر إرسال الرمز')),
      );
      return false;
    }
    final codeController = TextEditingController();
    var isVerifying = false;
    var errorMessage = '';
    try {
      final verified = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> verifyCode() async {
              if (codeController.text.trim().length != 6) {
                setDialogState(
                    () => errorMessage = 'أدخل رمز التحقق المكوّن من 6 أرقام');
                return;
              }
              setDialogState(() {
                isVerifying = true;
                errorMessage = '';
              });
              final result = await _authService.verifyOtp(
                phone: phone,
                otp: codeController.text,
              );
              if (!dialogContext.mounted) return;
              if (result['success'] == true) {
                Navigator.of(dialogContext).pop(true);
              } else {
                setDialogState(() {
                  isVerifying = false;
                  errorMessage =
                      result['error']?.toString() ?? 'رمز التحقق غير صحيح';
                });
              }
            }

            Future<void> resendCode() async {
              setDialogState(() {
                isVerifying = true;
                errorMessage = '';
              });
              codeController.clear();
              final result = await _authService.requestOtp(
                phone: phone,
                updatePhoneOnCurrentUser: true,
              );
              if (!dialogContext.mounted) return;
              setDialogState(() {
                isVerifying = false;
                errorMessage = result['success'] == true
                    ? 'تم إرسال رمز جديد'
                    : result['error']?.toString() ?? 'تعذر إرسال الرمز';
              });
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('تأكيد رقم الهاتف'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('أدخل رمز التحقق المرسل عبر واتساب إلى $phone'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      enabled: !isVerifying,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: 'رمز OTP',
                        errorText: errorMessage.isEmpty ? null : errorMessage,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: isVerifying ? null : resendCode,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة إرسال الرمز'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isVerifying ? null : () => Navigator.pop(dialogContext),
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
                        : const Text('تأكيد الرقم'),
                  ),
                ],
              ),
            );
          },
        ),
      );
      return verified == true;
    } finally {
      codeController.dispose();
    }
  }

  Future<void> _saveProfile() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final profile = _profile ??
        widget.initialProfile ??
        await _authService.loadSession() ??
        await _authService.getCurrentProfile();
    if (profile == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على حساب مسجل')),
      );
      return;
    }

    final email = _emailController.text.trim();
    final phone = _authService.normalizePhone(_phoneController.text.trim());
    final selectedAddress = _deliveryAddresses
        .where((item) => item.id == _selectedDeliveryAddressId)
        .firstOrNull;
    final city = selectedAddress?.city ?? _cityController.text.trim();
    final address = selectedAddress?.address ?? _addressController.text.trim();
    final password = _passwordController.text.trim();
    final confirmedPassword = _confirmPasswordController.text.trim();

    if (phone.isEmpty || city.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال الهاتف والمدينة')),
      );
      return;
    }

    if (!AppConstants.isYemenPhoneValid(phone)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رقم هاتف يمني صحيح')),
      );
      return;
    }

    if (password.isNotEmpty || confirmedPassword.isNotEmpty) {
      if (_currentPasswordController.text.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('أدخل كلمة المرور الحالية لتأكيد تغييرها'),
          ),
        );
        return;
      }
      if (!AppConstants.isStrongPassword(password)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('كلمة المرور يجب ألا تقل عن 6 أحرف'),
          ),
        );
        return;
      }

      if (password != confirmedPassword) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تأكيد كلمة المرور غير متطابق')),
        );
        return;
      }
    }

    final phoneChanged = phone != _authService.normalizePhone(profile.phone);
    if (phoneChanged &&
        !await _authService.isPhoneAvailableForProfile(
          profile: profile,
          phone: phone,
        )) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم الهاتف غير صالح أو مرتبط بحساب آخر')),
      );
      return;
    }

    setState(() => _isSaving = true);
    if (phoneChanged && !await _verifyPhoneChange(phone)) {
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    final emailChanged = (profile.email ?? '').trim().toLowerCase() !=
        email.trim().toLowerCase();
    final updated = await _authService.updateProfileDetails(
      profile: profile,
      email: email,
      phone: phone,
      city: city,
      address: address,
      profileImageData: _profileImageData,
      currentPassword: _currentPasswordController.text,
      newPassword: password.isEmpty ? null : password,
    );

    if (!mounted) return;
    if (updated == null) {
      setState(() => _isSaving = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(_authService.lastError ?? 'تعذر تحديث البيانات')),
      );
      return;
    }

    if (_deliveryAddresses.isNotEmpty && selectedAddress != null) {
      final savedProfile = await _authService.updateDeliveryAddresses(
        profile: updated,
        addresses: _deliveryAddresses,
        selectedAddressId: selectedAddress.id,
      );
      if (!mounted) return;
      if (savedProfile == null) {
        setState(() => _isSaving = false);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(_authService.lastError ?? 'تعذر حفظ عناوين التوصيل'),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = false);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(emailChanged
            ? 'تم تحديث البيانات. أكّد البريد الجديد من رسالة Firebase.'
            : 'تم تحديث بيانات الحساب بنجاح'),
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'تحديث البيانات',
        icon: Icons.manage_accounts_rounded,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تحديث الملف الشخصي',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Column(
                          children: [
                            InkWell(
                              onTap: _pickProfileImage,
                              borderRadius: BorderRadius.circular(30),
                              child: Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.4),
                                    width: 2,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _profileImageData != null &&
                                        _profileImageData!.trim().isNotEmpty
                                    ? Image(
                                        image: MediaUploadService.imageProvider(
                                          _profileImageData,
                                        )!,
                                        fit: BoxFit.cover,
                                        width: 110,
                                        height: 110,
                                      )
                                    : Center(
                                        child: Text(
                                          (_profileFullName.trim().isNotEmpty
                                                  ? _profileFullName
                                                      .trim()[0]
                                                      .toUpperCase()
                                                  : 'S')
                                              .toString(),
                                          style: const TextStyle(
                                            fontSize: 38,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton.icon(
                                  onPressed: _pickProfileImage,
                                  icon: const Icon(Icons.photo_camera_rounded),
                                  label: const Text('تغيير الصورة'),
                                ),
                                if (_profileImageData != null)
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() => _profileImageData = null);
                                    },
                                    icon: const Icon(
                                        Icons.delete_outline_rounded),
                                    label: const Text('إزالة'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'اسم المستخدم',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(_profileFullName),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        enabled: !_isSaving,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          helperText: 'سيُرسل رابط تأكيد عند تغيير البريد',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _currentPasswordController,
                        enabled: !_isSaving,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText:
                              'كلمة المرور الحالية لتأكيد تغيير البريد أو كلمة المرور',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phoneController,
                        enabled: !_isSaving,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          helperText: 'سيُطلب رمز OTP عند تغيير الرقم',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'عناوين التوصيل',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      DeliveryAddressBook(
                        addresses: _deliveryAddresses,
                        selectedId: _selectedDeliveryAddressId,
                        onSelect: (id) => setState(() {
                          _selectedDeliveryAddressId = id;
                        }),
                        onAdd: () async {
                          final address =
                              await showDeliveryAddressEditor(context);
                          if (address == null || !mounted) return;
                          setState(() {
                            _deliveryAddresses = [
                              ..._deliveryAddresses,
                              address
                            ];
                            _selectedDeliveryAddressId = address.id;
                          });
                        },
                        onEdit: (existing) async {
                          final address = await showDeliveryAddressEditor(
                            context,
                            initial: existing,
                          );
                          if (address == null || !mounted) return;
                          setState(() {
                            _deliveryAddresses = _deliveryAddresses
                                .map((item) =>
                                    item.id == address.id ? address : item)
                                .toList();
                          });
                        },
                        onDelete: (address) async {
                          if (_deliveryAddresses.length == 1) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'يجب الاحتفاظ بعنوان توصيل واحد على الأقل'),
                              ),
                            );
                            return;
                          }
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('حذف عنوان التوصيل'),
                              content: Text('هل تريد حذف «${address.label}»؟'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('إلغاء'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('حذف'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true || !mounted) return;
                          setState(() {
                            _deliveryAddresses.removeWhere(
                              (item) => item.id == address.id,
                            );
                            if (_selectedDeliveryAddressId == address.id) {
                              _selectedDeliveryAddressId =
                                  _deliveryAddresses.firstOrNull?.id;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'تغيير كلمة المرور (اختياري)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        enabled: !_isSaving,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور الجديدة',
                          helperText:
                              'أدخل كلمة المرور الحالية أعلاه لتأكيد التغيير',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmPasswordController,
                        enabled: !_isSaving,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد كلمة المرور',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _saveProfile,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            _isSaving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
