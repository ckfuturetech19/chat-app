import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:onlyus/screens/couple_display_screen.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_themes.dart';
import '../core/services/couple_code_serivce.dart';
import '../providers/auth_provider.dart';
import '../widgets/common/animated_heart.dart';
import '../widgets/common/gradient_background.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _heartController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _startAnimations();
    _checkAuthStatus();
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _scaleController.forward();

    await Future.delayed(const Duration(milliseconds: 300));
    _fadeController.forward();

    await Future.delayed(const Duration(milliseconds: 200));
    _heartController.repeat();
  }

  void _checkAuthStatus() async {
    // Wait for animations to complete
    await Future.delayed(const Duration(milliseconds: 3000));

    if (!mounted) return;

    // Check authentication status
    final authState = ref.read(authStateProvider);

    authState.when(
      data: (user) async {
        if (user != null) {
          // User is signed in, check couple code status
          await _checkCoupleCodeStatus(user.uid);
        } else {
          // User is not signed in, navigate to auth
          _navigateToAuth();
        }
      },
      loading: () {
        // Still loading, wait a bit more
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) _checkAuthStatus();
        });
      },
      error: (error, stackTrace) {
        // Error occurred, navigate to auth
        _navigateToAuth();
      },
    );
  }

  Future<void> _checkCoupleCodeStatus(String userId) async {
    try {
      // Check if user is already connected
      final isConnected = await CoupleCodeService.instance.isUserConnected(
        userId,
      );

      if (isConnected) {
        // User is connected, navigate to chat
        _navigateToChat();
        return;
      }

      // Check if user has a couple code
      final coupleCode = await CoupleCodeService.instance.getUserCoupleCode(
        userId,
      );

      if (coupleCode != null && coupleCode.isNotEmpty) {
        // User has a code but not connected, navigate to code display
        _navigateToCodeDisplay(coupleCode);
      } else {
        // User doesn't have a code, navigate to code creation/input screen
        _navigateToAuth(); // or create a separate code creation screen
      }
    } catch (e) {
      print('❌ Error checking couple code status: $e');
      _navigateToAuth(); // Fallback to auth screen
    }
  }

  void _navigateToCodeDisplay(String coupleCode) {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _navigateToAuth() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => const AuthScreen(),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _navigateToChat() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => const ChatScreen(),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated heart icons floating around
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Floating hearts
                          ...List.generate(5, (index) {
                            return AnimatedBuilder(
                              animation: _heartController,
                              builder: (context, child) {
                                final angle =
                                    (index * 72.0) * (3.14159 / 180.0);
                                final radius = 80.0 + (20.0 * (index % 2));
                                final x =
                                    radius *
                                    math.cos(
                                      angle +
                                          _heartController.value * 2 * 3.14159,
                                    );
                                final y =
                                    radius *
                                    math.sin(
                                      angle +
                                          _heartController.value * 2 * 3.14159,
                                    );

                                return Transform.translate(
                                  offset: Offset(x, y),
                                  child: AnimatedHeart(
                                    size: 16 + (index * 4).toDouble(),
                                    color: AppColors.heartColors[index],
                                    delay: Duration(milliseconds: index * 200),
                                  ),
                                );
                              },
                            );
                          }),

                          // Main logo/title
                          ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.heartGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryDeepRose
                                        .withOpacity(0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.favorite,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 48),

                      // App title with animation
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          children: [
                            Text(
                              'OnlyUs',
                              style: AppThemes.appTitleStyle.copyWith(
                                fontSize: 36,
                                shadows: [
                                  Shadow(
                                    color: AppColors.primaryDeepRose
                                        .withOpacity(0.3),
                                    offset: const Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Animated subtitle
                            SizedBox(
                              height: 30,
                              child: AnimatedTextKit(
                                animatedTexts: [
                                  TypewriterAnimatedText(
                                    'Just for you and me 💕',
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      color: AppColors.textSecondary,
                                      fontFamily: 'SF Pro Text',
                                    ),
                                    speed: const Duration(milliseconds: 100),
                                  ),
                                ],
                                repeatForever: false,
                                pause: const Duration(milliseconds: 1000),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Loading indicator
              FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: AppColors.buttonGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'Creating magic...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
