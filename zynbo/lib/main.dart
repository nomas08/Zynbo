import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/chats_list_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'services/auth_service.dart';
import 'services/presence_service.dart';
import 'theme/zynbo_colors.dart';

export 'theme/zynbo_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ZynboColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ZynboApp());
}

class ZynboApp extends StatefulWidget {
  const ZynboApp({super.key});

  // Re-exports so existing call sites keep working.
  static const Color brandTeal = ZynboColors.teal;
  static const Color brandLime = ZynboColors.lime;
  static const Color brandCream = ZynboColors.bg;
  static const Color brandInk = ZynboColors.text;
  static const Color brandSurface = ZynboColors.surface;
  static const Color brandSurfaceHi = ZynboColors.surfaceHi;
  static const Color brandDark = ZynboColors.deepInk;

  @override
  State<ZynboApp> createState() => _ZynboAppState();
}

class _ZynboAppState extends State<ZynboApp> with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) PresenceService.instance.goOnline(user.uid);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        PresenceService.instance.goOnline(uid);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        PresenceService.instance.goOffline(uid);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.spaceGroteskTextTheme(
      ThemeData.dark().textTheme,
    ).apply(
      bodyColor: ZynboColors.text,
      displayColor: ZynboColors.text,
    );
    return MaterialApp(
      title: 'Zynbo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ZynboColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: ZynboColors.lime,
          onPrimary: ZynboColors.deepInk,
          secondary: ZynboColors.teal,
          onSecondary: ZynboColors.text,
          surface: ZynboColors.surface,
          onSurface: ZynboColors.text,
          background: ZynboColors.bg,
          onBackground: ZynboColors.text,
          error: Color(0xFFFF6B6B),
        ),
        textTheme: base,
        appBarTheme: AppBarTheme(
          backgroundColor: ZynboColors.bg,
          elevation: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(color: ZynboColors.text),
          titleTextStyle: GoogleFonts.spaceGrotesk(
            color: ZynboColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: ZynboColors.lime,
            foregroundColor: ZynboColors.deepInk,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            shape: const StadiumBorder(),
            textStyle: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        dialogBackgroundColor: ZynboColors.surface,
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: ZynboColors.surface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: ZynboColors.surface,
          hintStyle: GoogleFonts.spaceGrotesk(
            color: ZynboColors.muted,
            fontSize: 15,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                BorderSide(color: ZynboColors.text.withOpacity(0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                BorderSide(color: ZynboColors.text.withOpacity(0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: ZynboColors.lime, width: 1.6),
          ),
        ),
        dividerColor: ZynboColors.divider,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashLoader();
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen(key: ValueKey('login'));
        }
        return FutureBuilder<bool>(
          key: ValueKey('profile-${user.uid}'),
          future: AuthService.instance.hasCompletedProfile(user.uid),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const _SplashLoader();
            }
            final hasProfile = profileSnap.data ?? false;
            if (!hasProfile) return const ProfileSetupScreen();
            return const ChatsListScreen();
          },
        );
      },
    );
  }
}

class _SplashLoader extends StatelessWidget {
  const _SplashLoader();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZynboColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: ZynboColors.lime,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_rounded,
                  size: 40, color: ZynboColors.deepInk),
            ),
            const SizedBox(height: 22),
            Text(
              'Zynbo',
              style: GoogleFonts.spaceGrotesk(
                color: ZynboColors.text,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(ZynboColors.lime),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
