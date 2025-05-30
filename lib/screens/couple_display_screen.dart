import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onlyus/core/services/couple_code_serivce.dart';
import 'package:onlyus/core/services/firebase_service.dart';
import 'package:onlyus/screens/code_entry_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math' as math;

import '../core/constants/app_colors.dart';
import '../core/services/chat_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/common/gradient_background.dart';
import '../widgets/common/animated_heart.dart';
import 'chat_screen.dart';

class CodeDisplayScreen extends ConsumerStatefulWidget {
  final String coupleCode;

  const CodeDisplayScreen({super.key, required this.coupleCode});

  @override
  ConsumerState<CodeDisplayScreen> createState() => _CodeDisplayScreenState();
}

class _CodeDisplayScreenState extends ConsumerState<CodeDisplayScreen>
    with TickerProviderStateMixin {
  late AnimationController _codeController;
  late AnimationController _heartController;
  late AnimationController _pulseController;

  late Animation<double> _codeScaleAnimation;
  late Animation<double> _codeOpacityAnimation;
  late Animation<double> _pulseAnimation;

  bool _isWaitingForPartner = true;
  String? _partnerId;

  @override
  void initState() {
    super.initState();

    _codeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _codeScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _codeController, curve: Curves.elasticOut),
    );

    _codeOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _codeController, curve: Curves.easeOut));

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startAnimations();
    _listenForPartnerConnection();
  }

  final TextEditingController _codeInputController = TextEditingController();
  bool _isEnteringCode = false;
  bool _isProcessingCode = false;

  // Add this method to _CodeDisplayScreenState class
  void _toggleCodeInput() {
    setState(() {
      _isEnteringCode = !_isEnteringCode;
      if (!_isEnteringCode) {
        _codeInputController.clear();
      }
    });
  }

  // Add this method to _CodeDisplayScreenState class
  Future<void> _submitEnteredCode() async {
    final enteredCode = _codeInputController.text.trim();

    if (enteredCode.isEmpty) {
      _showSnackBar('Please enter a code');
      return;
    }

    if (!CoupleCodeService.isValidCodeFormat(enteredCode)) {
      _showSnackBar('Invalid code format. Please check and try again.');
      return;
    }

    setState(() {
      _isProcessingCode = true;
    });

    try {
      final currentUserId =
          ref.read(authControllerProvider.notifier).currentUserId;
      if (currentUserId == null) {
        _showSnackBar('Authentication error. Please try again.');
        return;
      }

      final result = await CoupleCodeService.instance.useCoupleCode(
        enteredCode,
        currentUserId,
      );

      if (result.isSuccess) {
        _showSnackBar('Successfully connected! 🎉');
        _onPartnerConnected();
      } else {
        _showSnackBar(result.message);
      }
    } catch (e) {
      _showSnackBar('Failed to connect. Please try again.');
      print('❌ Error submitting code: $e');
    } finally {
      setState(() {
        _isProcessingCode = false;
      });
    }
  }

  void _startAnimations() {
    _codeController.forward();
    _heartController.repeat();
    _pulseController.repeat(reverse: true);
  }

 // In code_display_screen.dart, update the _listenForPartnerConnection method:
void _listenForPartnerConnection() {
  final currentUserId = ref.read(authControllerProvider.notifier).currentUserId;
  if (currentUserId == null) return;

  // Listen for changes in user's document
  FirebaseService.usersCollection.doc(currentUserId).snapshots().listen((snapshot) {
    if (!mounted) return;
    
    if (snapshot.exists) {
      final userData = snapshot.data() as Map<String, dynamic>;
      final isConnected = userData['isConnected'] as bool? ?? false;
      final partnerId = userData['partnerId'] as String?;
      
      print('📋 Connection status update - isConnected: $isConnected, partnerId: $partnerId');
      
      // Check if user just got connected
      if (isConnected && partnerId != null && _isWaitingForPartner) {
        print('✅ Partner connected! Partner ID: $partnerId');
        _partnerId = partnerId;
        _onPartnerConnected();
      }
    }
  });
}

  // In code_display_screen.dart:
void _onPartnerConnected() {
  if (!mounted) return;
  
  setState(() => _isWaitingForPartner = false);
  
  // Initialize chat service before showing success dialog
  ChatService.instance.initializeChatWithFallback().then((chatId) {
    if (chatId != null) {
      print('✅ Chat initialized: $chatId');
      // Show success animation
      _showConnectionSuccessDialog();
    } else {
      print('❌ Failed to initialize chat after connection');
      _showSnackBar('Connected but failed to initialize chat. Please try again.');
    }
  });
}

  void _showConnectionSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => _ConnectionSuccessDialog(
            onContinue: () {
              Navigator.of(context).pop();
              _navigateToChat();
            },
          ),
    );
  }

  void _navigateToChat() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => const ChatScreen(),
        transitionDuration: const Duration(milliseconds: 1000),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 1.0),
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

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.coupleCode));
    _showSnackBar('Code copied to clipboard! 💕');
    HapticFeedback.lightImpact();
  }

  Future<void> _shareCode() async {
    final formattedCode = CoupleCodeService.formatCodeForDisplay(
      widget.coupleCode,
    );
    final shareText =
        '''💕 Hey love! Download OnlyUs and enter our couple code to connect:

🔐 ${formattedCode}

OnlyUs - Just for the two of us ❤️
Download: [App Store Link] | [Google Play Link]''';

    await Share.share(shareText, subject: 'Our OnlyUs Couple Code 💕');
  }

  Future<void> _regenerateCode() async {
    try {
      final currentUserId =
          ref.read(authControllerProvider.notifier).currentUserId;
      if (currentUserId != null) {
        final newCode = await CoupleCodeService.instance.regenerateCoupleCode(
          currentUserId,
        );
        _showSnackBar('New code generated! 🔄');

        // Navigate back and show new code
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CodeDisplayScreen(coupleCode: newCode),
          ),
        );
      }
    } catch (e) {
      _showSnackBar('Failed to regenerate code. Please try again.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primaryDeepRose,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _heartController.dispose();
    _pulseController.dispose();
    _codeInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Floating hearts decoration
                      SizedBox(
                        height: 150,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ...List.generate(6, (index) {
                              return AnimatedBuilder(
                                animation: _heartController,
                                builder: (context, child) {
                                  final angle =
                                      (index * 60.0) * (math.pi / 180.0);
                                  final radius = 60.0;
                                  final x =
                                      radius *
                                      math.cos(
                                        angle +
                                            _heartController.value *
                                                2 *
                                                math.pi,
                                      );
                                  final y =
                                      radius *
                                      math.sin(
                                        angle +
                                            _heartController.value *
                                                2 *
                                                math.pi,
                                      );

                                  return Transform.translate(
                                    offset: Offset(x, y),
                                    child: AnimatedHeart(
                                      size: 12 + (index * 2).toDouble(),
                                      color:
                                          AppColors.heartColors[index %
                                              AppColors.heartColors.length],
                                      delay: Duration(
                                        milliseconds: index * 300,
                                      ),
                                    ),
                                  );
                                },
                              );
                            }),

                            // Main heart icon
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _pulseAnimation.value,
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.heartGradient,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primaryDeepRose
                                              .withOpacity(0.4),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.favorite,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Title
                      FadeTransition(
                        opacity: _codeOpacityAnimation,
                        child: Text(
                          _isWaitingForPartner
                              ? '💕 Your Couple Code 💕'
                              : '🎉 Connected! 🎉',
                          style: Theme.of(
                            context,
                          ).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 24),

                      if (_isWaitingForPartner) ...[
                        // Code display
                        ScaleTransition(
                          scale: _codeScaleAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  AppColors.neutralCream.withOpacity(0.8),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.primaryRose.withOpacity(0.3),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryDeepRose.withOpacity(
                                    0.2,
                                  ),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  CoupleCodeService.formatCodeForDisplay(
                                    widget.coupleCode,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDeepRose,
                                    letterSpacing: 4,
                                    fontFamily: 'Courier',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Share this code with your special someone',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Action buttons
                        FadeTransition(
                          opacity: _codeOpacityAnimation,
                          child: Column(
                            children: [
                              if (!_isEnteringCode) ...[
                                // Original buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _copyCode,
                                        icon: const Icon(Icons.copy),
                                        label: const Text('Copy Code'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppColors.primaryDeepRose,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _shareCode,
                                        icon: const Icon(Icons.share),
                                        label: const Text('Share Code'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppColors.secondaryDeepPurple,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Enter code button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  const CodeEntryScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.keyboard),
                                    label: const Text('Enter Partner\'s Code'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accentDeepGold,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 8),

                                TextButton.icon(
                                  onPressed: _regenerateCode,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Generate New Code'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.textSecondary,
                                  ),
                                ),
                              ] else ...[
                                // Code input section
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white,
                                        AppColors.neutralCream.withOpacity(0.8),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.accentDeepGold
                                          .withOpacity(0.3),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.accentDeepGold
                                            .withOpacity(0.1),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  AppColors.accentDeepGold,
                                                  AppColors.accentDeepGold
                                                      .withOpacity(0.8),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.keyboard,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'Enter Partner\'s Code',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),

                                      TextField(
                                        controller: _codeInputController,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2,
                                          color: AppColors.primaryDeepRose,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'ABC-123',
                                          hintStyle: TextStyle(
                                            color: AppColors.textSecondary
                                                .withOpacity(0.5),
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: AppColors.primaryRose
                                                  .withOpacity(0.3),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: const BorderSide(
                                              color: AppColors.accentDeepGold,
                                              width: 2,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 16,
                                              ),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        maxLength: 7, // ABC-123 format
                                        buildCounter:
                                            (
                                              context, {
                                              required currentLength,
                                              required isFocused,
                                              maxLength,
                                            }) => null,
                                        onChanged: (value) {
                                          // Auto-format with dash
                                          if (value.length == 3 &&
                                              !value.contains('-')) {
                                            _codeInputController.text =
                                                '$value-';
                                            _codeInputController.selection =
                                                TextSelection.fromPosition(
                                                  TextPosition(
                                                    offset:
                                                        _codeInputController
                                                            .text
                                                            .length,
                                                  ),
                                                );
                                          }
                                        },
                                      ),

                                      const SizedBox(height: 16),

                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextButton(
                                              onPressed: _toggleCodeInput,
                                              child: const Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed:
                                                  _isProcessingCode
                                                      ? null
                                                      : _submitEnteredCode,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.accentDeepGold,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              child:
                                                  _isProcessingCode
                                                      ? const SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          valueColor:
                                                              AlwaysStoppedAnimation<
                                                                Color
                                                              >(Colors.white),
                                                        ),
                                                      )
                                                      : const Text(
                                                        'Connect',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Waiting message
                        FadeTransition(
                          opacity: _codeOpacityAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.primaryRose.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.primaryRose.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              AppColors.primaryDeepRose,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Waiting for your partner...',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryDeepRose,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Once they enter the code, you\'ll both be connected instantly!',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // // Instructions
                // if (_isWaitingForPartner)
                //   FadeTransition(
                //     opacity: _codeOpacityAnimation,
                //     child: Container(
                //       padding: const EdgeInsets.all(12),
                //       decoration: BoxDecoration(
                //         color: Colors.white.withOpacity(0.1),
                //         borderRadius: BorderRadius.circular(12),
                //       ),
                //       child: Column(
                //         children: [
                //           Row(
                //             children: [
                //               Container(
                //                 padding: const EdgeInsets.all(6),
                //                 decoration: BoxDecoration(
                //                   color: AppColors.accentDeepGold.withOpacity(
                //                     0.2,
                //                   ),
                //                   borderRadius: BorderRadius.circular(6),
                //                 ),
                //                 child: const Icon(
                //                   Icons.info_outline,
                //                   color: AppColors.accentDeepGold,
                //                   size: 16,
                //                 ),
                //               ),
                //               const SizedBox(width: 8),
                //               const Text(
                //                 'How it works:',
                //                 style: TextStyle(
                //                   fontWeight: FontWeight.w600,
                //                   color: AppColors.textPrimary,
                //                 ),
                //               ),
                //             ],
                //           ),
                //           const SizedBox(height: 8),
                //           const Text(
                //             '1. Share your code with your partner\n'
                //             '2. They download OnlyUs and enter the code\n'
                //             '3. You\'ll both be connected instantly!\n'
                //             '4. Start your beautiful conversation 💕',
                //             style: TextStyle(
                //               color: AppColors.textSecondary,
                //               fontSize: 12,
                //               height: 1.4,
                //             ),
                //           ),
                //         ],
                //       ),
                //     ),
                //   ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Connection success dialog
class _ConnectionSuccessDialog extends StatefulWidget {
  final VoidCallback onContinue;

  const _ConnectionSuccessDialog({required this.onContinue});

  @override
  State<_ConnectionSuccessDialog> createState() =>
      _ConnectionSuccessDialogState();
}

class _ConnectionSuccessDialogState extends State<_ConnectionSuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();

    // Auto-continue after animation
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) widget.onContinue();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDeepRose.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated hearts
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Transform.rotate(
                    angle: _rotationAnimation.value * 0.1,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ...List.generate(8, (index) {
                          final angle = (index * 45.0) * (math.pi / 180.0);
                          final radius = 40.0;
                          final x = radius * math.cos(angle);
                          final y = radius * math.sin(angle);

                          return Transform.translate(
                            offset: Offset(x, y),
                            child: Icon(
                              Icons.favorite,
                              size: 16,
                              color:
                                  AppColors.heartColors[index %
                                      AppColors.heartColors.length],
                            ),
                          );
                        }),

                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: AppColors.heartGradient,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Success text
            FadeTransition(
              opacity: _scaleAnimation,
              child: Column(
                children: [
                  Text(
                    '🎉 Hearts Connected! 🎉',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDeepRose,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Your partner has joined!\nRedirecting to your chat...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
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
