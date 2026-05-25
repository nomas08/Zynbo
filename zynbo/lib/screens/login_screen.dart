import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      await AuthService.instance.signInWithGoogle();
      // AuthGate will react to authStateChanges and navigate.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign in failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZynboApp.brandTeal,
      body: SafeArea(
        child: Stack(
          children: [
            // Decorative lime blob (asymmetric, off-canvas)
            Positioned(
              top: -90,
              right: -70,
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                  color: ZynboApp.brandLime,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              left: -80,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wordmark
                  FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _anim, curve: const Interval(0.0, 0.5)),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: ZynboApp.brandLime,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chat_bubble_rounded,
                              size: 22, color: ZynboApp.brandDark),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Zynbo',
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Headline
                  SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0, 0.15), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: _anim,
                            curve: const Interval(0.2, 0.8,
                                curve: Curves.easeOutCubic))),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                          parent: _anim, curve: const Interval(0.2, 0.8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Talk freely.\nConnect deeply.',
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 44,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'A private, fast, and beautiful place\nfor your conversations.',
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 56),

                  // Google sign-in button
                  FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _anim, curve: const Interval(0.5, 1.0)),
                    child: SizedBox(
                      width: double.infinity,
                      child: _GoogleSignInButton(
                        loading: _loading,
                        onPressed: _loading ? null : _handleGoogleSignIn,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Terms
                  FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _anim, curve: const Interval(0.6, 1.0)),
                    child: Text(
                      'By continuing you agree to our Terms & Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  const _GoogleSignInButton({required this.onPressed, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(60),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(60),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(ZynboApp.brandTeal),
                  ),
                )
              else
                _GoogleLogo(),
              const SizedBox(width: 14),
              Text(
                loading ? 'Signing you in…' : 'Continue with Google',
                style: GoogleFonts.spaceGrotesk(
                  color: ZynboApp.brandDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Lightweight inline "G" logo (vector-free, brand-respectful)
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ZynboApp.brandDark, width: 2.2),
      ),
      child: Text(
        'G',
        style: GoogleFonts.spaceGrotesk(
          color: ZynboApp.brandDark,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
