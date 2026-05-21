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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ZynboApp());
}

class ZynboApp extends StatelessWidget {
  const ZynboApp({super.key});

  // Brand palette — distinctive teal/lime aesthetic (avoids generic purple gradient)
  static const Color brandTeal = Color(0xFF0B3D3A);
  static const Color brandLime = Color(0xFFB6FF3D);
  static const Color brandCream = Color(0xFFF5F0E1);
  static const Color brandInk = Color(0xFF0A0F0E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zynbo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: brandCream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandTeal,
          primary: brandTeal,
          secondary: brandLime,
          background: brandCream,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: brandInk,
        ),
        textTheme: GoogleFonts.spaceGroteskTextTheme().apply(
          bodyColor: brandInk,
          displayColor: brandInk,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: brandCream,
          elevation: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(color: brandInk),
          titleTextStyle: GoogleFonts.spaceGrotesk(
            color: brandInk,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: brandInk,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            shape: const StadiumBorder(),
            textStyle: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: brandInk.withOpacity(0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: brandInk.withOpacity(0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: brandTeal, width: 1.6),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Routes the user between Login → Profile Setup → Home based on auth + profile state.
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
            if (!hasProfile) {
              return const ProfileSetupScreen();
            }
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
      backgroundColor: ZynboApp.brandTeal,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: ZynboApp.brandLime,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_rounded,
                  size: 40, color: ZynboApp.brandInk),
            ),
            const SizedBox(height: 22),
            Text(
              'Zynbo',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
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
                valueColor: AlwaysStoppedAnimation(ZynboApp.brandLime),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
