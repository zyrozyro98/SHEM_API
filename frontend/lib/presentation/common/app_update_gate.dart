import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/services/app_update_service.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/presentation/common/app_startup_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    required this.child,
    required this.navigatorKey,
    this.updateService,
    this.authService,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final AppUpdateService? updateService;
  final AuthService? authService;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  late final AppUpdateService _updateService;
  late final AuthService _authService;
  bool _hasCompletedInitialCheck = false;
  bool _isChecking = true;
  bool _dialogShowing = false;
  bool _dialogPending = false;
  Object? _loadError;
  AppUpdateNotice? _notice;
  int _checkGeneration = 0;

  @override
  void initState() {
    super.initState();
    _updateService = widget.updateService ?? AppUpdateService();
    _authService = widget.authService ?? AuthService();
    WidgetsBinding.instance.addObserver(this);
    AuthService.profileUpdated.addListener(_onProfileUpdated);
    _checkUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AuthService.profileUpdated.removeListener(_onProfileUpdated);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkUpdate();
  }

  void _onProfileUpdated() => _checkUpdate();

  Future<void> _checkUpdate() async {
    final isInitialCheck = !_hasCompletedInitialCheck;
    final generation = ++_checkGeneration;
    if (mounted && isInitialCheck) {
      setState(() {
        if (!_dialogShowing) _isChecking = true;
        _loadError = null;
      });
    }

    try {
      final profile = await _authService.loadSession();
      if (profile == null) {
        if (!mounted || generation != _checkGeneration) return;
        void applySignedOutResult() {
          _notice = null;
          _loadError = null;
          _isChecking = false;
          _hasCompletedInitialCheck = true;
        }

        if (isInitialCheck || _notice != null || _loadError != null) {
          setState(applySignedOutResult);
        } else {
          applySignedOutResult();
        }
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final updateNotice = await _updateService.getNotice();
      AppUpdateNotice? applicableNotice;
      if (updateNotice.active &&
          updateNotice.targetsRole(profile.role) &&
          AppUpdateNotice.compareVersions(
                packageInfo.version,
                updateNotice.latestVersion,
              ) <
              0) {
        final dismissed =
            updateNotice.importance == AppUpdateImportance.optional &&
                await _updateService.wasDismissed(updateNotice.latestVersion);
        if (!dismissed) applicableNotice = updateNotice;
      }

      if (!mounted || generation != _checkGeneration) return;
      final noticeChanged = !_sameNotice(_notice, applicableNotice);
      void applyResult() {
        _notice = applicableNotice;
        _isChecking = false;
        _hasCompletedInitialCheck = true;
      }

      if (isInitialCheck || noticeChanged) {
        setState(applyResult);
      } else {
        applyResult();
      }
      if (applicableNotice != null &&
          applicableNotice.importance != AppUpdateImportance.mandatory) {
        _scheduleNoticeDialog(applicableNotice);
      }
    } catch (error) {
      if (!mounted || generation != _checkGeneration) return;
      debugPrint('App update policy check failed: $error');
      final shouldShowError = !_hasCompletedInitialCheck;
      void applyError() {
        _loadError = shouldShowError ? error : null;
        _isChecking = false;
        if (shouldShowError) _notice = null;
      }

      if (shouldShowError) {
        setState(applyError);
      } else {
        applyError();
      }
    }
  }

  bool _sameNotice(AppUpdateNotice? first, AppUpdateNotice? second) {
    if (first == null || second == null) return first == second;
    return first.active == second.active &&
        first.latestVersion == second.latestVersion &&
        first.title == second.title &&
        first.message == second.message &&
        first.downloadUrl == second.downloadUrl &&
        first.importance == second.importance &&
        first.targetRoles.length == second.targetRoles.length &&
        first.targetRoles
            .asMap()
            .entries
            .every((entry) => second.targetRoles[entry.key] == entry.value);
  }

  void _scheduleNoticeDialog(AppUpdateNotice notice) {
    if (_dialogShowing || _dialogPending || !mounted) return;
    _dialogPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogPending = false;
      final currentNotice = _notice;
      if (!mounted ||
          _dialogShowing ||
          currentNotice == null ||
          currentNotice.importance == AppUpdateImportance.mandatory ||
          currentNotice.latestVersion != notice.latestVersion) {
        return;
      }
      final navigatorContext = widget.navigatorKey.currentContext;
      if (navigatorContext == null) {
        setState(() {
          _loadError = StateError('تعذر فتح نافذة تحديث التطبيق');
        });
        return;
      }
      _showNoticeDialog(currentNotice, navigatorContext);
    });
  }

  Future<void> _showNoticeDialog(
    AppUpdateNotice notice,
    BuildContext navigatorContext,
  ) async {
    if (_dialogShowing || !mounted) return;
    _dialogShowing = true;
    final dismissed = await showDialog<bool>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogContext) => _UpdateNoticeDialog(
        notice: notice,
        onUpdate: () => _openDownload(notice.downloadUrl, dialogContext),
      ),
    );
    _dialogShowing = false;
    if (dismissed != false &&
        notice.importance == AppUpdateImportance.optional) {
      try {
        await _updateService.saveDismissedVersion(notice.latestVersion);
      } catch (error) {
        debugPrint('Could not save dismissed app update: $error');
        AppErrorReporter.scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('تعذر حفظ حالة إغلاق التنبيه على هذا الجهاز'),
          ),
        );
      }
    }
  }

  Future<void> _openDownload(String downloadUrl, BuildContext context) async {
    try {
      final uri = Uri.parse(downloadUrl);
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (opened || !context.mounted) return;
      AppErrorReporter.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('تعذر فتح رابط التحميل في المتصفح')),
      );
    } catch (error) {
      AppErrorReporter.scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(AppErrorMessage.from(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCompletedInitialCheck && _isChecking && !_dialogShowing) {
      return const AppStartupScreen();
    }
    if (!_hasCompletedInitialCheck && _loadError != null) {
      return _UpdateCheckScreen(
        title: 'تعذر التحقق من تحديث التطبيق',
        message: AppErrorMessage.from(_loadError!),
        child: FilledButton.icon(
          onPressed: _checkUpdate,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('إعادة المحاولة'),
        ),
      );
    }
    if (_notice?.importance == AppUpdateImportance.mandatory) {
      return _MandatoryUpdateScreen(
        notice: _notice!,
        onUpdate: () => _openDownload(_notice!.downloadUrl, context),
        onRetry: _checkUpdate,
      );
    }
    return widget.child;
  }
}

class _UpdateCheckScreen extends StatelessWidget {
  const _UpdateCheckScreen({
    required this.child,
    this.title = 'جارٍ التحقق من تحديث التطبيق',
    this.message,
  });

  final Widget child;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(message!, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MandatoryUpdateScreen extends StatelessWidget {
  const _MandatoryUpdateScreen({
    required this.notice,
    required this.onUpdate,
    required this.onRetry,
  });

  final AppUpdateNotice notice;
  final VoidCallback onUpdate;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.system_update_alt_rounded,
                        size: 72,
                        color: Color(0xFF9A7B2F),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        notice.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(notice.message, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(
                        'الإصدار المطلوب: ${notice.latestVersion}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onUpdate,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('تحديث التطبيق'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('تم التحديث؟ أعد التحقق'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateNoticeDialog extends StatelessWidget {
  const _UpdateNoticeDialog({
    required this.notice,
    required this.onUpdate,
  });

  final AppUpdateNotice notice;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        icon: const Icon(
          Icons.system_update_alt_rounded,
          size: 40,
          color: Color(0xFF9A7B2F),
        ),
        title: Text(notice.title, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(notice.message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text('الإصدار الجديد: ${notice.latestVersion}'),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            onPressed: onUpdate,
            icon: const Icon(Icons.download_rounded),
            label: const Text('تحديث'),
          ),
        ],
      ),
    );
  }
}
