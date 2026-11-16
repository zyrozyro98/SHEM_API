import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/services/support_service.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/support/refund_request_form.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportCenterScreen extends StatefulWidget {
  const SupportCenterScreen({
    super.key,
    this.supportService,
    this.loadProfile,
    this.loadOrders,
  });

  final SupportService? supportService;
  final Future<UserModel?> Function()? loadProfile;
  final Future<List<OrderModel>> Function(String customerId)? loadOrders;

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> {
  late final SupportService _supportService =
      widget.supportService ?? SupportService();
  final TextEditingController _searchController = TextEditingController();
  String _selectedTag = 'الكل';
  UserModel? _profile;
  List<OrderModel> _orders = const [];
  List<Map<String, dynamic>> _refundRequests = const [];
  Map<String, dynamic> _supportContact = const {};
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSupportData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSupportData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final contact = await _supportService.getSupportContact();
      final profile = widget.loadProfile != null
          ? await widget.loadProfile!()
          : await AuthService().loadSession();
      var orders = const <OrderModel>[];
      var refunds = const <Map<String, dynamic>>[];
      if (profile?.role == 'customer') {
        final customerId = profile!.id.trim().isNotEmpty
            ? profile.id.trim()
            : profile.phone.trim();
        orders = widget.loadOrders != null
            ? await widget.loadOrders!(customerId)
            : await OrderService().getOrdersByCustomer(customerId);
        refunds =
            await _supportService.getRefundRequestsForCustomer(customerId);
      }
      if (!mounted) return;
      setState(() {
        _supportContact = contact;
        _profile = profile;
        _orders = orders;
        _refundRequests = refunds;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = AppErrorMessage.from(error);
        _isLoading = false;
      });
    }
  }

  Future<void> _openRefundRequest() async {
    final profile = _profile;
    if (profile == null || profile.role != 'customer') {
      await Navigator.of(context).push(
        slideFadeRoute(page: const PhoneLoginScreen()),
      );
      await _loadSupportData();
      return;
    }
    if (_orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد طلبات متاحة لطلب استردادها')),
      );
      return;
    }

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => RefundRequestForm(
        customer: profile,
        orders: _orders,
        supportService: _supportService,
      ),
    );
    if (submitted == true) {
      await _loadSupportData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب الاسترداد للمراجعة')),
      );
    }
  }

  Future<void> _openWhatsApp() async {
    final number =
        (_supportContact['whatsapp_phone'] ?? _supportContact['phone'] ?? '')
            .toString()
            .replaceAll(RegExp(r'[^0-9]'), '');
    if (number.isEmpty) return;
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent('مرحبًا، أحتاج إلى مساعدة بخصوص طلبي')}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openCall() async {
    final phone = _supportContact['phone']?.toString().trim() ?? '';
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openEmail() async {
    final email = _supportContact['email']?.toString().trim() ?? '';
    if (email.isEmpty) return;
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'طلب مساعدة من مركز الدعم'},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  List<_SupportArticle> get _allTopics {
    switch (_profile?.role) {
      case 'merchant':
        return _merchantArticles;
      case 'driver':
        return _driverArticles;
      default:
        return _customerArticles;
    }
  }

  List<String> get _categories => [
        'الكل',
        ..._allTopics.map((topic) => topic.category).toSet(),
      ];

  String get _roleName => switch (_profile?.role) {
        'merchant' => 'التاجر',
        'driver' => 'السائق',
        _ => 'العميل',
      };

  List<_SupportArticle> get _visibleTopics {
    final query = _searchController.text.trim().toLowerCase();
    return _allTopics.where((topic) {
      final matchesCategory =
          _selectedTag == 'الكل' || topic.category == _selectedTag;
      final searchText =
          '${topic.question} ${topic.answer} ${topic.category} ${topic.keywords}'
              .toLowerCase();
      return matchesCategory && (query.isEmpty || searchText.contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: CustomAppBar(
          title: 'مركز المساعدة',
          icon: Icons.support_agent_rounded,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: const CustomAppBar(
          title: 'مركز المساعدة',
          icon: Icons.support_agent_rounded,
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 42),
                  const SizedBox(height: 12),
                  const Text('تعذر تحميل بيانات المساعدة.'),
                  const SizedBox(height: 6),
                  Text(_loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadSupportData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final visibleTopics = _visibleTopics;

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'مركز المساعدة',
        icon: Icons.support_agent_rounded,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF8F2E7), Color(0xFFFFFFFF)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE7DCC3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'مركز المساعدة',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'دعم مخصص لدور $_roleName. ابحث عن إجابة أو تواصل معنا.',
                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: Color(0xFFD4AF37),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('support_search'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ابحث في الأسئلة الشائعة',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._categories,
              ].map((tag) {
                final isSelected = _selectedTag == tag;
                return InkWell(
                  onTap: () => setState(() => _selectedTag = tag),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? const Color(0xFF1B120C) : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF1B120C)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color:
                            isSelected ? Colors.white : const Color(0xFF111827),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_profile?.role == 'customer') ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('create_refund_request'),
                onPressed: _openRefundRequest,
                icon: const Icon(Icons.assignment_return_rounded),
                label: const Text('طلب استرداد منتج'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: const Color(0xFF1B120C),
                  foregroundColor: Colors.white,
                ),
              ),
              if (_refundRequests.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'طلبات الاسترداد',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ..._refundRequests.map(_buildRefundSummary),
              ],
            ],
            const SizedBox(height: 18),
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.support_agent_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'قنوات التواصل مع الدعم',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (_supportContact['response_time']
                                      ?.toString()
                                      .isNotEmpty ??
                                  false)
                              ? 'متوسط الرد: ${_supportContact['response_time']}'
                              : 'تواصل مع فريق الدعم لمتابعة طلبك',
                          style: const TextStyle(
                            color: Color(0xFFE5E7EB),
                            fontSize: 12,
                          ),
                        ),
                        if (_supportContact['working_hours']
                                ?.toString()
                                .isNotEmpty ??
                            false) ...[
                          const SizedBox(height: 4),
                          Text(
                            'ساعات العمل: ${_supportContact['working_hours']}',
                            style: const TextStyle(
                              color: Color(0xFFE5E7EB),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 16),
                ],
              ),
            ),
            ...visibleTopics.map((topic) => _SupportTopic(
                  key: ValueKey('support_faq_${topic.question}'),
                  question: topic.question,
                  answer: topic.answer,
                  category: topic.category,
                  icon: topic.icon,
                )),
            if (visibleTopics.isEmpty)
              Container(
                key: const ValueKey('support_no_results'),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.search_off_rounded, size: 32),
                    SizedBox(height: 8),
                    Text(
                      'لا توجد إجابات مطابقة. جرّب كلمات أخرى أو تواصل مع الدعم.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تحتاج إلى دعم مباشر؟',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اختر قناة التواصل المناسبة، وستجد بيانات الدعم المحدثة أدناه.',
                    style: TextStyle(color: Color(0xFFEDE9FE)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_supportContact['whatsapp_phone']
                                          ?.toString()
                                          .isNotEmpty ??
                                      false) ||
                                  (_supportContact['phone']
                                          ?.toString()
                                          .isNotEmpty ??
                                      false)
                              ? _openWhatsApp
                              : null,
                          icon: const Icon(Icons.chat_rounded),
                          label: const Text('واتساب'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              _supportContact['phone']?.toString().isNotEmpty ==
                                      true
                                  ? _openCall
                                  : null,
                          icon: const Icon(Icons.call_rounded),
                          label: const Text('اتصال'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF111827),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _supportContact['email']?.toString().isNotEmpty ==
                                  true
                              ? _openEmail
                              : null,
                      icon: const Icon(Icons.email_rounded),
                      label: const Text('البريد الإلكتروني'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEDE9FE),
                        foregroundColor: const Color(0xFF111827),
                      ),
                    ),
                  ),
                  if ((_supportContact['phone']?.toString().isNotEmpty ??
                          false) ||
                      (_supportContact['whatsapp_phone']
                              ?.toString()
                              .isNotEmpty ??
                          false) ||
                      (_supportContact['email']?.toString().isNotEmpty ??
                          false)) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        _supportContact['phone']?.toString(),
                        _supportContact['whatsapp_phone']?.toString(),
                        _supportContact['email']?.toString(),
                      ]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join(' · '),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildRefundSummary(Map<String, dynamic> request) {
  final product = request['product_snapshot'] is Map
      ? Map<String, dynamic>.from(request['product_snapshot'] as Map)
      : const <String, dynamic>{};
  final status = request['status']?.toString() ?? 'pending';
  final statusLabel = switch (status) {
    'under_review' => 'قيد المراجعة',
    'approved' => 'تمت الموافقة',
    'rejected' => 'مرفوض',
    _ => 'بانتظار المراجعة',
  };
  final amount =
      request['approved_amount'] ?? request['customer_claimed_amount'] ?? 0;

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE8DDD0)),
    ),
    child: Row(
      children: [
        const Icon(Icons.assignment_return_outlined, color: Color(0xFF8B6A27)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product['name']?.toString() ?? 'طلب استرداد',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                '$statusLabel · ${request['id'] ?? ''}',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$amount ${request['currency_symbol'] ?? 'ر.س'}',
          style: const TextStyle(
            color: Color(0xFF1B120C),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _SupportArticle {
  final String question;
  final String answer;
  final String category;
  final String keywords;
  final IconData icon;

  const _SupportArticle({
    required this.question,
    required this.answer,
    required this.category,
    required this.keywords,
    required this.icon,
  });
}

const _customerArticles = [
  _SupportArticle(
    question: 'كيف أتابع حالة طلبي؟',
    answer:
        'افتح «طلباتي» من حسابك لعرض حالة الطلب وتفاصيله. عند تسليم الطلب لشركة التوصيل ستظهر لك معلومات التتبع المتاحة.',
    category: 'الطلبات',
    keywords: 'تتبع شحنة حالة الطلب',
    icon: Icons.local_shipping_rounded,
  ),
  _SupportArticle(
    question: 'كيف أطلب استرداد منتج؟',
    answer:
        'من مركز المساعدة اختر «طلب استرداد منتج»، ثم حدد الطلب والمنتج وسبب الاسترداد واكتب تفاصيل المشكلة. يمكنك متابعة حالة الطلب هنا بعد إرساله.',
    category: 'الاسترداد',
    keywords: 'إرجاع استرجاع تعويض منتج تالف',
    icon: Icons.assignment_return_rounded,
  ),
  _SupportArticle(
    question: 'متى يصلني رد على طلب الاسترداد؟',
    answer:
        'تظهر حالة الطلب ضمن «طلبات الاسترداد». إذا احتجت إلى توضيح إضافي، تواصل مع الدعم وأرسل رقم طلب الاسترداد.',
    category: 'الاسترداد',
    keywords: 'مراجعة موافقة رفض مدة',
    icon: Icons.hourglass_top_rounded,
  ),
  _SupportArticle(
    question: 'ما طرق الدفع المتاحة؟',
    answer:
        'تظهر طرق الدفع المتاحة عند إتمام الطلب. إذا تعذّر تأكيد الدفع أو ظهرت مشكلة، احتفظ برقم الطلب وتواصل مع فريق الدعم.',
    category: 'الدفع',
    keywords: 'دفع سداد فاتورة نقدي',
    icon: Icons.payment_rounded,
  ),
  _SupportArticle(
    question: 'كيف أغيّر بيانات حسابي؟',
    answer:
        'افتح صفحة «حسابي» ثم اختر «تحديث البيانات». تأكد من حفظ رقم الهاتف والعنوان الصحيحين قبل إنشاء طلب جديد.',
    category: 'الحساب',
    keywords: 'تعديل الاسم الهاتف العنوان الملف الشخصي',
    icon: Icons.person_outline_rounded,
  ),
  _SupportArticle(
    question: 'ماذا أفعل إذا تأخر التوصيل؟',
    answer:
        'تحقق أولًا من حالة الطلب وعنوان التسليم. إذا تجاوز موعد التوصيل المتوقع، تواصل مع الدعم واذكر رقم الطلب.',
    category: 'التوصيل',
    keywords: 'تأخير شحنة عنوان السائق',
    icon: Icons.delivery_dining_rounded,
  ),
];

const _merchantArticles = [
  _SupportArticle(
    question: 'كيف أتابع الطلبات الجديدة؟',
    answer:
        'راجع قائمة الطلبات في لوحة متجرك بانتظام، وحدّث حالة كل طلب بعد بدء التجهيز أو التسليم حتى تظهر للعميل معلومات دقيقة.',
    category: 'الطلبات',
    keywords: 'طلب جديد تجهيز حالة شحنة',
    icon: Icons.receipt_long_rounded,
  ),
  _SupportArticle(
    question: 'كيف أضيف منتجًا أو أعدّل بياناته؟',
    answer:
        'استخدم إدارة المنتجات في لوحة التاجر لإضافة المنتج أو تحديث وصفه وصوره وسعره ومخزونه. راجع البيانات قبل حفظها لتجنب عرض معلومات غير دقيقة.',
    category: 'المنتجات',
    keywords: 'مخزون سعر صورة وصف',
    icon: Icons.inventory_2_rounded,
  ),
  _SupportArticle(
    question: 'كيف أتابع مستحقاتي؟',
    answer:
        'راجع قسم المحفظة أو التقارير المالية في لوحة التاجر لمعرفة المستحقات والحركات المسجلة. إذا وجدت فرقًا، أرسل رقم الطلب وفترة التسوية إلى الدعم.',
    category: 'المدفوعات',
    keywords: 'مبيعات رصيد محفظة تحويل تسوية',
    icon: Icons.account_balance_wallet_rounded,
  ),
  _SupportArticle(
    question: 'كيف أتعامل مع طلب استرداد؟',
    answer:
        'تابع إشعارات الطلب وراجع تفاصيل المنتج والطلب عند ورود استفسار أو طلب استرداد. أرسل للدعم رقم الطلب وأي معلومات تساعد على مراجعة الحالة.',
    category: 'الطلبات',
    keywords: 'إرجاع استرجاع شكوى منتج',
    icon: Icons.assignment_return_rounded,
  ),
  _SupportArticle(
    question: 'كيف أغيّر بيانات المتجر؟',
    answer:
        'افتح إعدادات الملف أو المتجر وحدّث الاسم وبيانات التواصل وموقع المتجر. احرص على أن تكون أرقام التواصل محدثة لاستقبال استفسارات التشغيل.',
    category: 'الحساب',
    keywords: 'متجر هاتف عنوان موقع بيانات',
    icon: Icons.storefront_rounded,
  ),
  _SupportArticle(
    question: 'ماذا أفعل إذا تعذّر عليّ الدخول إلى لوحة التاجر؟',
    answer:
        'تحقق من رقم الهاتف وبيانات الدخول، ثم جرّب تسجيل الدخول مجددًا. إذا استمرت المشكلة، تواصل مع الدعم وأرسل رقم حسابك ورسالة الخطأ.',
    category: 'الحساب',
    keywords: 'تسجيل الدخول كلمة المرور حساب',
    icon: Icons.login_rounded,
  ),
];

const _driverArticles = [
  _SupportArticle(
    question: 'كيف أستلم مهمة توصيل؟',
    answer:
        'تابع المهام المسندة إليك في التطبيق، واقبل المهمة المتاحة وفق آلية التشغيل. حدّث الحالة عند الاستلام ثم بعد إتمام التسليم.',
    category: 'التوصيل',
    keywords: 'مهمة طلب استلام توصيل',
    icon: Icons.delivery_dining_rounded,
  ),
  _SupportArticle(
    question: 'كيف أُحدّث حالة الطلب؟',
    answer:
        'استخدم إجراءات الطلب في التطبيق لتسجيل الاستلام والتسليم في الوقت الصحيح. إذا تعذّر تحديث الحالة، تواصل مع الدعم وأرسل رقم الطلب.',
    category: 'الطلبات',
    keywords: 'استلام تسليم حالة تحديث',
    icon: Icons.sync_rounded,
  ),
  _SupportArticle(
    question: 'ماذا أفعل إذا تعذّر الوصول إلى العميل؟',
    answer:
        'تحقق من تفاصيل العنوان ورقم التواصل، وحاول الاتصال بالعميل. إذا لم تتمكن من إتمام التسليم، أبلغ الدعم قبل تغيير حالة الطلب.',
    category: 'التوصيل',
    keywords: 'عنوان هاتف عميل تعذر الوصول',
    icon: Icons.phone_in_talk_rounded,
  ),
  _SupportArticle(
    question: 'كيف أبلغ عن مشكلة أثناء التوصيل؟',
    answer:
        'تواصل مع فريق الدعم واشرح المشكلة مع ذكر رقم الطلب وموقعك التقريبي. لا تُسلّم الطلب لشخص آخر أو تغيّر حالته دون اتباع التعليمات.',
    category: 'التوصيل',
    keywords: 'حادث تأخير مشكلة طارئ',
    icon: Icons.report_problem_outlined,
  ),
  _SupportArticle(
    question: 'أين أراجع مستحقات التوصيل؟',
    answer:
        'راجع قسم الأرباح أو سجل المهام في حساب السائق. إذا كان هناك مبلغ غير ظاهر، أرسل للدعم أرقام المهام وتواريخها.',
    category: 'المستحقات',
    keywords: 'راتب أرباح رصيد محفظة دفعة',
    icon: Icons.account_balance_wallet_rounded,
  ),
  _SupportArticle(
    question: 'كيف أُحدّث بيانات حساب السائق؟',
    answer:
        'حدّث بيانات التواصل ومعلومات المركبة من صفحة الحساب إن كانت متاحة. إذا احتاج التعديل إلى مراجعة، أرسل البيانات المطلوبة إلى الدعم.',
    category: 'الحساب',
    keywords: 'مركبة رقم هاتف ملف شخصي',
    icon: Icons.person_outline_rounded,
  ),
];

class _SupportTopic extends StatelessWidget {
  final String question;
  final String answer;
  final String category;
  final IconData icon;

  const _SupportTopic({
    super.key,
    required this.question,
    required this.answer,
    required this.category,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        key: key,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(category),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              answer,
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
