import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:onlyus/core/services/couple_code_serivce.dart';
import 'package:onlyus/core/services/firebase_service.dart';
import 'package:onlyus/screens/couple_display_screen.dart';
import 'dart:math' as math;

import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_themes.dart';
import '../providers/auth_provider.dart';
import '../widgets/common/animated_heart.dart';
import '../widgets/common/gradient_background.dart';
import '../widgets/auth/google_sign_in_button.dart';
import 'chat_screen.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _heartController;
  late AnimationController _logoController;
  
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoRotationAnimation;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );
    
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _logoScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    ));
    
    _logoRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeInOut,
    ));
    
    _startAnimations();
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Start logo animation
    _logoController.forward();
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Start other animations
    _fadeController.forward();
    _slideController.forward();
    _heartController.repeat();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _heartController.dispose();
    _logoController.dispose();
    super.dispose();
  }

 void _handleSignInSuccess() async {
  final currentUser = FirebaseService.currentUser;
  if (currentUser == null) return;
  
  try {
    // Check if user is already connected
    final isConnected = await CoupleCodeService.instance.isUserConnected(currentUser.uid);
    
    if (isConnected) {
      // User is connected, navigate to chat
      _navigateToChat();
      return;
    }
    
    // Check if user has a couple code
    final coupleCode = await CoupleCodeService.instance.getUserCoupleCode(currentUser.uid);
    
    if (coupleCode != null && coupleCode.isNotEmpty) {
      // User has a code but not connected, navigate to code display
      _navigateToCodeDisplay(coupleCode);
    } else {
      // User doesn't have a code, create one and navigate to code display
      final newCode = await CoupleCodeService.instance.createCoupleCodeForUser(currentUser.uid);
      _navigateToCodeDisplay(newCode);
    }
  } catch (e) {
    print('❌ Error handling sign in success: $e');
    _showErrorSnackBar('Something went wrong. Please try again.');
  }
}

void _navigateToChat() {
  Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => const ChatScreen(),
      transitionDuration: const Duration(milliseconds: 1000),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
    ),
  );
}

void _navigateToCodeDisplay(String coupleCode) {
  Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => 
          CodeDisplayScreen(coupleCode: coupleCode),
      transitionDuration: const Duration(milliseconds: 1000),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
    ),
  );
}

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to auth state changes
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is AuthSuccess) {
        _handleSignInSuccess();
      } else if (next is AuthError) {
        _showErrorSnackBar(next.message);
      }
    });

    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Floating hearts decoration
                              SizedBox(
                                height: 200,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Animated hearts around the logo
                                    ...List.generate(8, (index) {
                                      return AnimatedBuilder(
                                        animation: _heartController,
                                        builder: (context, child) {
                                          final angle = (index * 45.0) * (math.pi / 180.0);
                                          final radius = 70.0 + (math.sin(_heartController.value * 2 * math.pi) * 10);
                                          final x = radius * math.cos(angle + _heartController.value * 2 * math.pi * 0.3);
                                          final y = radius * math.sin(angle + _heartController.value * 2 * math.pi * 0.3);
                                          
                                          return Transform.translate(
                                            offset: Offset(x, y),
                                            child: AnimatedHeart(
                                              size: 12 + (index % 3) * 4.0,
                                              color: AppColors.heartColors[index % AppColors.heartColors.length],
                                              delay: Duration(milliseconds: index * 200),
                                            ),
                                          );
                                        },
                                      );
                                    }),
                                    
                                    // Main logo with advanced animations
                                    AnimatedBuilder(
                                      animation: Listenable.merge([_logoScaleAnimation, _logoRotationAnimation]),
                                      builder: (context, child) {
                                        return Transform.scale(
                                          scale: _logoScaleAnimation.value,
                                          child: Transform.rotate(
                                            angle: _logoRotationAnimation.value * 0.1, // Subtle rotation
                                            child: Container(
                                              width: 100,
                                              height: 100,
                                              decoration: BoxDecoration(
                                                gradient: AppColors.heartGradient,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppColors.primaryDeepRose.withOpacity(0.4),
                                                    blurRadius: 25,
                                                    spreadRadius: 8,
                                                  ),
                                                  BoxShadow(
                                                    color: Colors.white.withOpacity(0.2),
                                                    blurRadius: 15,
                                                    spreadRadius: -5,
                                                    offset: const Offset(-5, -5),
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.favorite,
                                                size: 50,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 32),
                              
                              // App title with enhanced styling
                              ShaderMask(
                                shaderCallback: (bounds) => AppColors.buttonGradient.createShader(bounds),
                                child: Text(
                                  AppStrings.appName,
                                  style: AppThemes.appTitleStyle.copyWith(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -1,
                                    shadows: [
                                      Shadow(
                                        color: AppColors.primaryDeepRose.withOpacity(0.3),
                                        offset: const Offset(0, 4),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Animated subtitle with multiple phrases
                              SizedBox(
                                height: 60,
                                child: AnimatedTextKit(
                                  animatedTexts: AppStrings.animatedSubtitles.map((subtitle) => 
                                    TypewriterAnimatedText(
                                      subtitle,
                                      textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                      speed: const Duration(milliseconds: 60),
                                      textAlign: TextAlign.center,
                                    ),
                                  ).toList(),
                                  repeatForever: true,
                                  pause: const Duration(milliseconds: 2500),
                                ),
                              ),
                              
                              const SizedBox(height: 48),
                              
                              // Welcome description
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.8),
                                      Colors.white.withOpacity(0.6),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.primaryRose.withOpacity(0.3),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryDeepRose.withOpacity(0.1),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      AppStrings.welcomeTitle,
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    
                                    const SizedBox(height: 12),
                                    
                                    Text(
                                      AppStrings.signInDescription,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: AppColors.textSecondary,
                                        height: 1.6,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 40),
                              
                              // Sign in button with loading state
                              GoogleSignInButton(
                                onPressed: authState is AuthLoading 
                                    ? null 
                                    : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
                                isLoading: authState is AuthLoading,
                              ),
                              
                              const SizedBox(height: 32),
                              
                              // Features showcase
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.7),
                                      Colors.white.withOpacity(0.5),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.primaryRose.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            gradient: AppColors.heartGradient,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.star,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            AppStrings.featuresTitle,
                                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                              color: AppColors.textPrimary,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    
                                    const SizedBox(height: 20),
                                    
                                    // Feature list with enhanced styling
                                    ...[
                                      ('💕', AppStrings.featureExclusive),
                                      ('🔒', AppStrings.featureSecure),
                                      ('❤️', AppStrings.featureDesign),
                                      ('📱', AppStrings.featureNotifications),
                                      ('✨', AppStrings.featureAnimations),
                                    ].asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final feature = entry.value;
                                      
                                      return TweenAnimationBuilder<double>(
                                        duration: Duration(milliseconds: 500 + (index * 100)),
                                        tween: Tween(begin: 0.0, end: 1.0),
                                        builder: (context, value, child) {
                                          return Transform.translate(
                                            offset: Offset(0, 20 * (1 - value)),
                                            child: Opacity(
                                              opacity: value,
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 6),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 32,
                                                      height: 32,
                                                      decoration: BoxDecoration(
                                                        color: AppColors.primaryRose.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          feature.$1,
                                                          style: const TextStyle(fontSize: 16),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Expanded(
                                                      child: Text(
                                                        feature.$2,
                                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                          color: AppColors.textSecondary,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Footer with enhanced styling
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            AppStrings.footerText,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textLight,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        const SizedBox(height: 8),
                        
                        Text(
                          AppStrings.version,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textLight.withOpacity(0.7),
                            fontSize: 10,
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
      ),
    );
  }
}