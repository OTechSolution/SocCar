import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

import 'screens/camera_registration_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/guard_dashboard.dart';
import 'screens/resident_dashboard.dart';
import 'screens/vehicle_detection_screen.dart';
import 'screens/plans_screen.dart';
import 'screens/admin_dashboard.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('📩 Background message: ${message.messageId}');
  await NotificationService().showLocalNotification(
    title: message.notification?.title ?? 'SocCar Alert',
    body: message.notification?.body ?? '',
    payload: message.data.toString(),
  );
}

// ─── Global theme notifier ────────────────────────────────────────────────────
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void toggleTheme() {
  themeNotifier.value =
  themeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService().init();
  final RemoteMessage? initialMessage =
  await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('🚀 App launched from notification: ${initialMessage.data}');
  }
  runApp(const SocCarApp());
}

// ─── Shared token constants ───────────────────────────────────────────────────
// All screens pull from this single source of truth so every color, radius,
// and spacing token changes in one place.
abstract class AppTokens {
  // ── Light palette ──────────────────────────────────────────────────────────
  static const Color lightBg         = Color(0xFFF4F6F9); // off-white app bg
  static const Color lightSurface    = Color(0xFFFFFFFF); // card / sheet surface
  static const Color lightBorder     = Color(0xFFCBD5E1); // 1 dp input borders
  static const Color lightBorderFocus= Color(0xFF1565C0); // focused input ring
  static const Color lightTextPrimary= Color(0xFF111827); // headings, active labels
  static const Color lightTextSecond = Color(0xFF4A5568); // body copy ≥4.5:1
  static const Color lightTextHint   = Color(0xFF6B7280); // placeholders ≥4.5:1
  static const Color lightFieldFill  = Color(0xFFFFFFFF); // input fill
  static const Color lightAccent     = Color(0xFF1565C0); // brand blue in light
  static const Color lightDivider    = Color(0xFFE2E8F0);

  // ── Dark palette ───────────────────────────────────────────────────────────
  static const Color darkBg          = Color(0xFF0A0A1A);
  static const Color darkSurface     = Color(0xFF141428);
  static const Color darkCard        = Color(0xFF1A1D35);
  static const Color darkBorder      = Color(0xFF2E3160);
  static const Color darkBorderFocus = Color(0xFF00E5FF);
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecond  = Color(0xFFB0B7D4); // white70 equivalent
  static const Color darkTextHint    = Color(0xFF6B7280);
  static const Color darkFieldFill   = Color(0xFF1A1D35);
  static const Color darkAccent      = Color(0xFF00E5FF); // cyan in dark
  static const Color darkDivider     = Color(0xFF2E3160);

  // ── Modal overlay alphas ───────────────────────────────────────────────────
  // Semi-transparent so the content behind remains visible.
  static const Color lightBarrier    = Color(0x66000000); // rgba(0,0,0,0.40)
  static const Color darkBarrier     = Color(0xB3000000); // rgba(0,0,0,0.70)

  // ── Cyan action button ─────────────────────────────────────────────────────
  // Same bright cyan works in both modes; text is always black for contrast.
  static const Color cyanAction      = Color(0xFF00E5FF);
  static const Color cyanActionText  = Color(0xFF000000);

  // ── Shared radii ───────────────────────────────────────────────────────────
  static const double radiusInput  = 14;
  static const double radiusCard   = 16;
  static const double radiusSheet  = 28;
  static const double radiusButton = 16;
}

class SocCarApp extends StatelessWidget {
  const SocCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'SocCar OS',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          initialRoute: '/',
          routes: {
            '/': (context) => const LandingScreen(),
            '/login': (context) => const LoginScreen(),
            '/guard_dashboard': (context) => const GuardDashboard(),
            '/resident_dashboard': (context) => const ResidentDashboard(),
            '/cameras': (_) => const CameraRegistrationScreen(),
            '/detect_vehicle'   : (context) => const VehicleDetectionScreen(),
            '/plans'            : (context) => const PlansScreen(),
            '/admin_dashboard'  : (context) => const AdminDashboard(),
          },
        );
      },
    );
  }

  // ── LIGHT THEME ─────────────────────────────────────────────────────────────
  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      colorScheme: const ColorScheme(
        brightness     : Brightness.light,
        primary        : AppTokens.lightAccent,
        onPrimary      : Colors.white,
        secondary      : AppTokens.cyanAction,
        onSecondary    : AppTokens.cyanActionText,
        surface        : AppTokens.lightSurface,
        onSurface      : AppTokens.lightTextPrimary,
        error          : Color(0xFFB91C1C),
        onError        : Colors.white,
      ),

      scaffoldBackgroundColor: AppTokens.lightBg,
      cardColor              : AppTokens.lightSurface,
      dividerColor           : AppTokens.lightDivider,

      // ── AppBar ──────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.lightAccent,
        foregroundColor: Colors.white,
        elevation      : 0,
        centerTitle    : true,
        titleTextStyle : TextStyle(
          color     : Colors.white,
          fontSize  : 17,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),

      // ── Cards ───────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color    : AppTokens.lightSurface,
        elevation: 0,
        shape    : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side        : const BorderSide(color: AppTokens.lightBorder),
        ),
      ),

      // ── Inputs ──────────────────────────────────────────────────────────────
      // These apply to any TextField that inherits from the global theme.
      // Screens that override locally still reference AppTokens.
      inputDecorationTheme: InputDecorationTheme(
        filled        : true,
        fillColor     : AppTokens.lightFieldFill,
        hintStyle     : const TextStyle(color: AppTokens.lightTextHint, fontSize: 14),
        labelStyle    : const TextStyle(color: AppTokens.lightTextSecond, fontSize: 14),
        prefixIconColor: AppTokens.lightAccent,
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: AppTokens.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: AppTokens.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: AppTokens.lightBorderFocus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: Color(0xFFB91C1C)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: Color(0xFFB91C1C), width: 2),
        ),
      ),

      // ── Elevated Button ─────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTokens.lightAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusButton)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),

      // ── Chip ────────────────────────────────────────────────────────────────
      chipTheme: const ChipThemeData(
        backgroundColor : AppTokens.lightDivider,
        labelStyle      : TextStyle(color: AppTokens.lightTextPrimary, fontSize: 12),
        selectedColor   : AppTokens.lightAccent,
        secondaryLabelStyle: TextStyle(color: Colors.white),
      ),

      // ── TabBar ──────────────────────────────────────────────────────────────
      tabBarTheme: const TabBarThemeData(
        indicatorColor      : Colors.white,
        labelColor          : Colors.white,
        unselectedLabelColor: Colors.white60,
      ),

      // ── Text ────────────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        bodyLarge  : TextStyle(color: AppTokens.lightTextPrimary, fontSize: 16),
        bodyMedium : TextStyle(color: AppTokens.lightTextPrimary, fontSize: 14),
        bodySmall  : TextStyle(color: AppTokens.lightTextSecond,  fontSize: 12),
        titleLarge : TextStyle(color: AppTokens.lightTextPrimary, fontWeight: FontWeight.bold, fontSize: 20),
        titleMedium: TextStyle(color: AppTokens.lightTextPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        labelMedium: TextStyle(color: AppTokens.lightTextSecond,  fontSize: 12),
        labelSmall : TextStyle(color: AppTokens.lightTextHint,    fontSize: 11),
      ),
    );
  }

  // ── DARK THEME ──────────────────────────────────────────────────────────────
  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      colorScheme: const ColorScheme(
        brightness     : Brightness.dark,
        primary        : AppTokens.darkAccent,
        onPrimary      : Colors.black,
        secondary      : AppTokens.cyanAction,
        onSecondary    : AppTokens.cyanActionText,
        surface        : AppTokens.darkSurface,
        onSurface      : AppTokens.darkTextPrimary,
        error          : Color(0xFFF87171),
        onError        : Colors.black,
      ),

      scaffoldBackgroundColor: AppTokens.darkBg,
      cardColor              : AppTokens.darkSurface,
      dividerColor           : AppTokens.darkDivider,

      // ── AppBar ──────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.darkSurface,
        foregroundColor: Colors.white,
        elevation      : 0,
        centerTitle    : true,
        titleTextStyle : TextStyle(
          color     : Colors.white,
          fontSize  : 17,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),

      // ── Cards ───────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color    : AppTokens.darkSurface,
        elevation: 0,
        shape    : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side        : const BorderSide(color: AppTokens.darkBorder),
        ),
      ),

      // ── Inputs ──────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled        : true,
        fillColor     : AppTokens.darkFieldFill,
        hintStyle     : const TextStyle(color: AppTokens.darkTextHint, fontSize: 14),
        labelStyle    : TextStyle(color: AppTokens.darkTextSecond.withOpacity(0.7), fontSize: 14),
        prefixIconColor: AppTokens.darkAccent,
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: AppTokens.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: AppTokens.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: AppTokens.darkBorderFocus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: Color(0xFFF87171)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : const BorderSide(color: Color(0xFFF87171), width: 2),
        ),
      ),

      // ── Elevated Button ─────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTokens.cyanAction,
          foregroundColor: AppTokens.cyanActionText,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusButton)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),

      // ── Chip ────────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor : AppTokens.darkCard,
        labelStyle      : const TextStyle(color: AppTokens.darkTextSecond, fontSize: 12),
        selectedColor   : AppTokens.darkAccent,
        secondaryLabelStyle: const TextStyle(color: Colors.black),
      ),

      // ── TabBar ──────────────────────────────────────────────────────────────
      tabBarTheme: const TabBarThemeData(
        indicatorColor      : AppTokens.darkAccent,
        labelColor          : AppTokens.darkAccent,
        unselectedLabelColor: Color(0xFF6B7280),
      ),

      // ── Text ────────────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        bodyLarge  : TextStyle(color: AppTokens.darkTextPrimary, fontSize: 16),
        bodyMedium : TextStyle(color: AppTokens.darkTextPrimary, fontSize: 14),
        bodySmall  : TextStyle(color: AppTokens.darkTextSecond,  fontSize: 12),
        titleLarge : TextStyle(color: AppTokens.darkTextPrimary, fontWeight: FontWeight.bold, fontSize: 20),
        titleMedium: TextStyle(color: AppTokens.darkTextPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        labelMedium: TextStyle(color: AppTokens.darkTextSecond,  fontSize: 12),
        labelSmall : TextStyle(color: AppTokens.darkTextHint,    fontSize: 11),
      ),
    );
  }
}
