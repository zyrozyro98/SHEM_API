import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/services/app_update_service.dart';

class AppUpdateManagementScreen extends StatefulWidget {
  const AppUpdateManagementScreen({super.key});

  @override
  State<AppUpdateManagementScreen> createState() =>
      _AppUpdateManagementScreenState();
}

class _AppUpdateManagementScreenState extends State<AppUpdateManagementScreen> {
  final AppUpdateService _service = AppUpdateService();
  final TextEditingController _versionController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final Set<String> _selectedRoles = {};
  AppUpdateImportance _importance = AppUpdateImportance.optional;
  bool _active = false;
  bool _isLoading = true;
  bool _isSaving = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadNotice();
  }

  @override
  void dispose() {
    _versionController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadNotice() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final notice = await _service.getNotice();
      if (!mounted) return;
      setState(() {
        _active = notice.active;
        _versionController.text = notice.latestVersion;
        _titleController.text = notice.title;
        _messageController.text = notice.message;
        _urlController.text = notice.downloadUrl;
        _selectedRoles
          ..clear()
          ..addAll(notice.targetRoles);
        _importance = notice.importance;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    final notice = AppUpdateNotice(
      active: _active,
      latestVersion: _versionController.text.trim(),
      title: _titleController.text.trim(),
      message: _messageController.text.trim(),
      downloadUrl: _urlController.text.trim(),
      targetRoles: _selectedRoles.toList(),
      importance: _importance,
    );
    try {
      notice.validate();
      setState(() => _isSaving = true);
      await _service.saveNotice(notice);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات تحديث التطبيق')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ArgumentError
                ? error.message?.toString() ?? AppErrorMessage.invalidData
                : AppErrorMessage.from(error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _roleLabel(String role) => switch (role) {
        'customer' => 'العملاء',
        'merchant' => 'التجار',
        'driver' => 'السائقون',
        'central_dispatcher' => 'مسؤولو التوصيل',
        'manager' => 'المديرون',
        'admin' => 'المسؤولون',
        _ => role,
      };

  String _importanceLabel(AppUpdateImportance importance) =>
      switch (importance) {
        AppUpdateImportance.optional => 'إشعار فقط - يمكن إغلاقه',
        AppUpdateImportance.mandatory => 'إجباري - يمنع استخدام التطبيق',
        AppUpdateImportance.repeat => 'تنبيه متكرر عند كل فتح للتطبيق',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة تحديث التطبيق')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppErrorMessage.from(_loadError!),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _loadNotice,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text(
                        'حدد إصدار التطبيق ورابطه، ومن تظهر له رسالة التحديث.',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('تفعيل إشعار التحديث'),
                        value: _active,
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() => _active = value),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _versionController,
                        enabled: !_isSaving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'أحدث إصدار متاح',
                          hintText: 'مثال: 1.2.3',
                          prefixIcon: Icon(Icons.tag_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _titleController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                          labelText: 'عنوان التنبيه',
                          prefixIcon: Icon(Icons.title_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _messageController,
                        enabled: !_isSaving,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'نص التنبيه',
                          prefixIcon: Icon(Icons.message_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _urlController,
                        enabled: !_isSaving,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'رابط التحميل الآمن (HTTPS)',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'أهمية التنبيه',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<AppUpdateImportance>(
                        initialValue: _importance,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: AppUpdateImportance.values
                            .map(
                              (importance) =>
                                  DropdownMenuItem<AppUpdateImportance>(
                                value: importance,
                                child: Text(_importanceLabel(importance)),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _importance = value);
                                }
                              },
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'أنواع المستخدمين المستهدفين',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: AppUpdateNotice.supportedRoles.map((role) {
                          return FilterChip(
                            label: Text(_roleLabel(role)),
                            selected: _selectedRoles.contains(role),
                            onSelected: _isSaving
                                ? null
                                : (selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedRoles.add(role);
                                      } else {
                                        _selectedRoles.remove(role);
                                      }
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_rounded),
                        label: const Text('حفظ إعدادات التحديث'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
