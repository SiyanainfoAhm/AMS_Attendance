import "package:flutter/material.dart";
import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:provider/provider.dart";
import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";

import "src/auth/auth_controller.dart";
import "src/config/app_config.dart";
import "src/ui/design/ams_theme.dart";
import "src/ui/screens/company_select_screen.dart";
import "src/ui/screens/home_screen.dart";
import "src/ui/screens/login_screen.dart";
import "src/ui/screens/splash_screen.dart";
import "src/ui/screens/stubs.dart";
import "src/ui/screens/support_screen.dart";

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma("vm:entry-point")
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep this lightweight; no UI available here.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // ignore
  }
}

void routeFromRemoteMessage(RemoteMessage message) {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;

  final data = message.data;
  final type = (data["type"] ?? data["notif_type"] ?? "").toString().trim();

  // Basic routing: extend as we add more notification types.
  if (type.startsWith("support")) {
    final ticketId = (data["ticketId"] ?? data["ticket_id"] ?? "").toString().trim();
    nav.push(
      MaterialPageRoute(
        builder: (_) => SupportScreen(focusTicketId: ticketId.isEmpty ? null : ticketId),
      ),
    );
    return;
  }
  if (type.startsWith("audit")) {
    nav.push(MaterialPageRoute(builder: (_) => const AuditResponseScreen()));
    return;
  }

  nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  AppConfig.validate();
  // Firebase init is required for push notifications. If not configured yet,
  // keep the app usable (in-app inbox will still work once backend is ready).
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // ignore
  }

  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {
    // ignore
  }
  runApp(const AmsStaffApp());
}

class AmsStaffApp extends StatelessWidget {
  const AmsStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthController()..init(),
      child: MaterialApp(
        title: "AMS Staff",
        theme: AmsTheme.light(),
        navigatorKey: appNavigatorKey,
        scaffoldMessengerKey: appMessengerKey,
        home: const _Gate(),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return switch (auth.stage) {
      AuthStage.loading => const SplashScreen(),
      AuthStage.loggedOut => const LoginScreen(),
      AuthStage.needsCompany => const CompanySelectScreen(),
      AuthStage.ready => const HomeScreen(),
    };
  }
}
