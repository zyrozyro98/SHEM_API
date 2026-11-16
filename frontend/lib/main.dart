import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/core/theme/app_theme.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/backend_warmup_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/wishlist_service.dart';
import 'package:she_m_app/firebase_options.dart';
import 'package:she_m_app/presentation/auth/profile_setup_screen.dart';
import 'package:she_m_app/presentation/common/app_update_gate.dart';
import 'package:she_m_app/presentation/common/app_startup_screen.dart';
import 'package:she_m_app/presentation/common/keyboard_dismissal_handler.dart';
import 'package:she_m_app/presentation/common/role_dashboard_router.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/presentation/catalog/product_detail_screen_full.dart';
import 'package:she_m_app/presentation/dashboard/customer_dashboard_screen.dart';

final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(BackendWarmupService.instance.ensureReady());
  if (!kDebugMode) {
    ErrorWidget.builder = (details) {
      FlutterError.presentError(details);
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: ColoredBox(
          color: Color(0xFFF8FAFC),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'حدث خطأ غير متوقع في هذه الشاشة. '
                'عد إلى الصفحة السابقة وحاول مرة أخرى.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    };
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error, stackTrace) {
    AppErrorReporter.report(error);
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const SheMApp(restoreSessionOnStart: true));
}

Widget initialScreenForProfile(UserModel? profile) {
  if (profile == null) return const CustomerDashboardScreen();
  if (profile.needsCustomerProfileSetup) {
    return ProfileSetupScreen(existingProfile: profile);
  }

  return dashboardForRole(profile.role);
}

bool canOpenProductLinkForProfile(UserModel? profile) {
  return profile == null || profile.role.trim().toLowerCase() == 'customer';
}

String? productIdFromAppLink(Uri uri) {
  if ((uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host == 'she-m-8d0f5.web.app' &&
      uri.path == '/product_details') {
    final productId = (uri.queryParameters['id'] ?? '').trim();
    return productId.isEmpty || productId.contains('/') ? null : productId;
  }
  if (uri.scheme != 'shem') return null;
  if (uri.host == 'product_details') {
    final productId = (uri.queryParameters['id'] ?? '').trim();
    return productId.isEmpty || productId.contains('/') ? null : productId;
  }
  if (uri.host == 'product' && uri.pathSegments.length == 1) {
    final productId = uri.pathSegments.single.trim();
    return productId.isEmpty || productId.contains('/') ? null : productId;
  }
  return null;
}

class SheMApp extends StatefulWidget {
  final Widget initialScreen;
  final bool restoreSessionOnStart;

  const SheMApp({
    super.key,
    this.initialScreen = const CustomerDashboardScreen(),
    this.restoreSessionOnStart = false,
  });

  @override
  State<SheMApp> createState() => _SheMAppState();
}

class _SheMAppState extends State<SheMApp> {
  StreamSubscription<Uri>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();
    final appLinks = AppLinks();
    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (uri) => unawaited(_openProductFromLink(uri)),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Could not receive app link: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    unawaited(_handleInitialAppLink(appLinks));
    if (kIsWeb) unawaited(_openProductFromLink(Uri.base));
  }

  Future<void> _handleInitialAppLink(AppLinks appLinks) async {
    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) await _openProductFromLink(initialLink);
    } catch (error, stackTrace) {
      debugPrint('Could not read initial app link: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _openProductFromLink(Uri uri) async {
    final productId = productIdFromAppLink(uri);
    if (productId == null) return;

    await WidgetsBinding.instance.endOfFrame;
    final navigator = _appNavigatorKey.currentState;
    if (navigator == null) {
      debugPrint('Cannot open product link before the app navigator is ready');
      return;
    }

    try {
      final authService = AuthService();
      final profile = await authService.loadSession() ??
          await authService.getCurrentProfile();
      if (!canOpenProductLinkForProfile(profile)) {
        AppErrorReporter.scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('روابط المنتجات متاحة للعملاء والضيوف فقط'),
          ),
        );
        return;
      }

      final productData =
          await FirebaseDatabaseService.instance.read('products/$productId');
      if (productData.isEmpty) {
        AppErrorReporter.scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('هذا المنتج غير متوفر')),
        );
        return;
      }
      navigator.push(
        slideFadeRoute(
          page: ProductDetailFullScreen(
            product: ProductModel.fromJson({
              ...productData,
              'id': productId,
            }),
          ),
        ),
      );
    } catch (error, stackTrace) {
      AppErrorReporter.report(error);
      debugPrintStack(stackTrace: stackTrace);
      AppErrorReporter.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('تعذر فتح المنتج من الرابط')),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_deepLinkSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: CartService.instance),
        ChangeNotifierProvider.value(value: WishlistService.instance),
      ],
      child: MaterialApp(
        navigatorKey: _appNavigatorKey,
        scaffoldMessengerKey: AppErrorReporter.scaffoldMessengerKey,
        title: 'She M',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: widget.restoreSessionOnStart
            ? const _AppStartupGate()
            : widget.initialScreen,
        builder: (context, child) => KeyboardDismissalHandler(
          child: AppUpdateGate(
            navigatorKey: _appNavigatorKey,
            child: AppErrorListener(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppStartupGate extends StatefulWidget {
  const _AppStartupGate();

  @override
  State<_AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<_AppStartupGate> {
  late final Future<Widget> _initialScreenFuture;

  @override
  void initState() {
    super.initState();
    _initialScreenFuture = _loadInitialScreen();
  }

  Future<Widget> _loadInitialScreen() async {
    try {
      final authService = AuthService();
      final savedUser = await authService.loadSession() ??
          await authService.getCurrentProfile();
      final activeUserId =
          savedUser == null || savedUser.needsCustomerProfileSetup
              ? null
              : savedUser.id;
      await CartService.instance.loadForUser(activeUserId);
      return initialScreenForProfile(savedUser);
    } catch (error, stackTrace) {
      AppErrorReporter.report(error);
      debugPrintStack(stackTrace: stackTrace);
      return const CustomerDashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _initialScreenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppStartupScreen();
        }
        return snapshot.data ?? const CustomerDashboardScreen();
      },
    );
  }
}
