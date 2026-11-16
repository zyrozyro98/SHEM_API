import 'dart:async';

import 'package:flutter/material.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';
import 'package:she_m_app/presentation/support/notifications_screen.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({
    this.compactBadge = false,
    this.prominent = false,
    this.onAdminOrderTap,
    super.key,
  });

  final bool compactBadge;
  final bool prominent;
  final Future<void> Function(String orderId)? onAdminOrderTap;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  final NotificationService _service = NotificationService();
  int _unreadCount = 0;
  Timer? _refreshTimer;
  Timer? _toastTimer;
  OverlayEntry? _toastEntry;
  final Set<String> _knownNotificationIds = {};
  String? _activeProfileId;
  bool _hasLoadedNotifications = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshUnreadCount();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshUnreadCount(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUnreadCount();
  }

  Future<void> _refreshUnreadCount() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final auth = AuthService();
      final profile =
          await auth.loadSession() ?? await auth.getCurrentProfile();
      if (profile == null) return;
      final profileId = profile.id.trim().isNotEmpty
          ? profile.id.trim()
          : profile.phone.trim();
      if (profileId.isEmpty) return;
      final notifications = await _service.getForProfile(
        profileId,
        role: profile.role,
      );
      if (!mounted) return;
      final profileChanged = _activeProfileId != profileId;
      if (profileChanged) {
        _activeProfileId = profileId;
        _knownNotificationIds.clear();
        _hasLoadedNotifications = false;
        _dismissToast();
      }
      CustomerNotification? newestNotification;
      for (final notification in notifications) {
        if (!_knownNotificationIds.contains(notification.id) &&
            !notification.isRead &&
            profile.role == 'merchant') {
          newestNotification ??= notification;
        }
        _knownNotificationIds.add(notification.id);
      }
      if (_hasLoadedNotifications && newestNotification != null) {
        _showNotificationToast(newestNotification);
      }
      _hasLoadedNotifications = true;
      setState(() {
        _unreadCount =
            notifications.where((notification) => !notification.isRead).length;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh notification badge: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      slideFadeRoute(
        page: NotificationsScreen(
          onAdminOrderTap: widget.onAdminOrderTap,
        ),
      ),
    );
    if (mounted) await _refreshUnreadCount();
  }

  void _showNotificationToast(CustomerNotification notification) {
    _dismissToast();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 12,
        right: 12,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MerchantNotificationToast(
              notification: notification,
              onTap: () {
                _dismissToast();
                Navigator.of(this.context).push(
                  slideFadeRoute(
                    page: NotificationsScreen(
                      initialNotificationId: notification.id,
                      onAdminOrderTap: widget.onAdminOrderTap,
                    ),
                  ),
                );
              },
              onDismissed: () {
                if (identical(_toastEntry, entry)) _dismissToast();
              },
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _toastTimer = Timer(
      const Duration(seconds: 7),
      _dismissToast,
    );
  }

  void _dismissToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    _toastEntry?.remove();
    _toastEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final badgeSize = widget.compactBadge ? 15.0 : 18.0;
    final buttonSize = widget.prominent ? 56.0 : 48.0;
    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: _openNotifications,
            constraints: BoxConstraints.tightFor(
              width: buttonSize,
              height: buttonSize,
            ),
            padding: EdgeInsets.zero,
            iconSize: widget.prominent ? 30 : 24,
            style: widget.prominent
                ? IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF1B120C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  )
                : null,
            icon: Icon(
              widget.prominent
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
            ),
          ),
          if (_unreadCount > 0)
            Positioned(
              right: widget.prominent ? 0 : 4,
              top: widget.prominent ? 0 : 4,
              child: IgnorePointer(
                child: Container(
                  constraints: BoxConstraints(
                    minWidth: badgeSize,
                    minHeight: badgeSize,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compactBadge ? 3 : 4,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB91C1C),
                    shape: BoxShape.circle,
                    border: widget.prominent
                        ? Border.all(color: Colors.white, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compactBadge ? 8 : 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MerchantNotificationToast extends StatelessWidget {
  const MerchantNotificationToast({
    required this.notification,
    required this.onTap,
    required this.onDismissed,
    super.key,
  });

  final CustomerNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onDismissed(),
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B120C),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFB69449), width: 1.2),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0x33B69449),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFFEAD8B8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        notification.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (notification.body.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          notification.body,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF3EBDD),
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'اضغط لعرض التفاصيل • اسحب للإغلاق',
                        style: TextStyle(
                          color: Color(0xFFE0C98C),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.close_rounded,
                  color: Color(0xFFEAD8B8),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
