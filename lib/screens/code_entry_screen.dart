import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onlyus/core/services/couple_code_serivce.dart';
import 'dart:math' as math;

import '../core/constants/app_colors.dart';

import '../providers/auth_provider.dart';
import '../widgets/common/gradient_background.dart';
import '../widgets/common/animated_heart.dart';
import '../widgets/common/loading_heart.dart';
import 'chat_screen.dart';

class CodeEntryScreen extends ConsumerStatefulWidget {
  const CodeEntryScreen({super.key});

  @override
  ConsumerState<CodeEntryScreen> createState() => _CodeEntryScreenState();
}

class _CodeEntryScreenState extends ConsumerState<CodeEntryScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _heartController;
  late AnimationController _shakeController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _shakeAnimation;

  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _fadeController.forward();
    _heartController.repeat();

    // Auto-focus first field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _heartController.dispose();
    _shakeController.dispose();

    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  String get _enteredCode {
    return _controllers.map((c) => c.text).join('');
  }

  bool get _isCodeComplete {
    return _enteredCode.length == 6 && _enteredCode.trim().isNotEmpty;
  }

  void _onCodeChanged(int index, String value) {
    if (value.isNotEmpty) {
      // Move to next field
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        // Code complete, try to connect
        _focusNodes[index].unfocus();
        if (_isCodeComplete) {
          _connectWithCode();
        }
      }
    }

    setState(() {
      _errorMessage = '';
    });
  }

  void _onCodeDeleted(int index) {
    if (index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _connectWithCode() async {
    if (!_isCodeComplete) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final currentUserId =
          ref.read(authControllerProvider.notifier).currentUserId;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final cleanCode = CoupleCodeService.cleanCode(_enteredCode);
      final result = await CoupleCodeService.instance.useCoupleCode(
        cleanCode,
        currentUserId,
      );

      if (result.isSuccess) {
        // Show success animation and navigate
        _showSuccessAnimation();
      } else {
        // Show error and shake animation
        setState(() {
          _errorMessage = result.message;
          _isLoading = false;
        });
        _shakeController.forward().then((_) => _shakeController.reverse());
        _clearCode();
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection failed. Please try again.';
        _isLoading = false;
      });
      _shakeController.forward().then((_) => _shakeController.reverse());
      _clearCode();
      HapticFeedback.heavyImpact();
    }
  }

  void _clearCode() {
    for (final controller in _controllers) {
      controller.clear();
    }
    _focusNodes[0].requestFocus();
  }

  void _showSuccessAnimation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => _ConnectionSuccessDialog(
            onComplete: () {
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

  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData('text/plain');
      if (clipboardData?.text != null) {
        final pastedText = CoupleCodeService.cleanCode(clipboardData!.text!);

        if (pastedText.length == 6 &&
            CoupleCodeService.isValidCodeFormat(pastedText)) {
          // Fill the code fields
          for (int i = 0; i < 6; i++) {
            _controllers[i].text = pastedText[i];
          }
          setState(() {});

          // Try to connect
          await Future.delayed(const Duration(milliseconds: 300));
          _connectWithCode();
        } else {
          _showSnackBar('Invalid code format in clipboard');
        }
      }
    } catch (e) {
      _showSnackBar('Could not paste from clipboard');
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
  Widget build(BuildContext context) {
    // Get keyboard height to determine if keyboard is visible
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Scaffold(
      // Add this to prevent resize when keyboard appears
      resizeToAvoidBottomInset: true,
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate available height
                  final availableHeight = constraints.maxHeight;

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: availableHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            // Main content - make it flexible when keyboard is visible
                            Flexible(
                              flex: isKeyboardVisible ? 0 : 1,
                              child: Column(
                                mainAxisAlignment:
                                    isKeyboardVisible
                                        ? MainAxisAlignment.start
                                        : MainAxisAlignment.center,
                                children: [
                                  // Reduce heart animation size when keyboard is visible
                                  if (!isKeyboardVisible ||
                                      availableHeight > 600) ...[
                                    SizedBox(
                                      height: isKeyboardVisible ? 80 : 120,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          ...List.generate(5, (index) {
                                            return AnimatedBuilder(
                                              animation: _heartController,
                                              builder: (context, child) {
                                                final angle =
                                                    (index * 72.0) *
                                                    (math.pi / 180.0);
                                                final radius =
                                                    isKeyboardVisible
                                                        ? 35.0
                                                        : 50.0;
                                                final x =
                                                    radius *
                                                    math.cos(
                                                      angle +
                                                          _heartController
                                                                  .value *
                                                              2 *
                                                              math.pi,
                                                    );
                                                final y =
                                                    radius *
                                                    math.sin(
                                                      angle +
                                                          _heartController
                                                                  .value *
                                                              2 *
                                                              math.pi,
                                                    );

                                                return Transform.translate(
                                                  offset: Offset(x, y),
                                                  child: AnimatedHeart(
                                                    size:
                                                        (isKeyboardVisible
                                                            ? 10
                                                            : 14) +
                                                        (index * 2).toDouble(),
                                                    color:
                                                        AppColors
                                                            .heartColors[index],
                                                    delay: Duration(
                                                      milliseconds: index * 200,
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          }),

                                          // Main icon
                                          Container(
                                            width: isKeyboardVisible ? 40 : 60,
                                            height: isKeyboardVisible ? 40 : 60,
                                            decoration: BoxDecoration(
                                              gradient: AppColors.heartGradient,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppColors
                                                      .primaryDeepRose
                                                      .withOpacity(0.3),
                                                  blurRadius: 15,
                                                  spreadRadius: 3,
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.link,
                                              size: isKeyboardVisible ? 20 : 30,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      height: isKeyboardVisible ? 16 : 32,
                                    ),
                                  ],

                                  // Title - smaller when keyboard is visible
                                  Text(
                                    '💕 Connect with Your Love 💕',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                      fontSize: isKeyboardVisible ? 20 : null,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  SizedBox(height: isKeyboardVisible ? 8 : 16),

                                  Text(
                                    'Enter the couple code they shared with you',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: isKeyboardVisible ? 14 : null,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  SizedBox(height: isKeyboardVisible ? 20 : 40),

                                  // Code input fields
                                  AnimatedBuilder(
                                    animation: _shakeAnimation,
                                    builder: (context, child) {
                                      return Transform.translate(
                                        offset: Offset(
                                          _shakeAnimation.value *
                                              10 *
                                              math.sin(
                                                _shakeAnimation.value *
                                                    math.pi *
                                                    8,
                                              ),
                                          0,
                                        ),
                                        child: Container(
                                          padding: EdgeInsets.all(
                                            isKeyboardVisible ? 16 : 24,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color:
                                                  _errorMessage.isNotEmpty
                                                      ? Colors.red.withOpacity(
                                                        0.5,
                                                      )
                                                      : AppColors.primaryRose
                                                          .withOpacity(0.3),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primaryDeepRose
                                                    .withOpacity(0.1),
                                                blurRadius: 15,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              // Code input row
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceEvenly,
                                                children: List.generate(
                                                  6,
                                                  (index) => _buildCodeInput(
                                                    index,
                                                    isKeyboardVisible,
                                                  ),
                                                ),
                                              ),

                                              if (_errorMessage.isNotEmpty) ...[
                                                SizedBox(
                                                  height:
                                                      isKeyboardVisible
                                                          ? 12
                                                          : 16,
                                                ),
                                                Text(
                                                  _errorMessage,
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                    fontSize:
                                                        isKeyboardVisible
                                                            ? 12
                                                            : 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],

                                              SizedBox(
                                                height:
                                                    isKeyboardVisible ? 12 : 20,
                                              ),

                                              // Paste button
                                              TextButton.icon(
                                                onPressed: _pasteFromClipboard,
                                                icon: Icon(
                                                  Icons.content_paste,
                                                  size:
                                                      isKeyboardVisible
                                                          ? 16
                                                          : 20,
                                                ),
                                                label: Text(
                                                  'Paste from Clipboard',
                                                  style: TextStyle(
                                                    fontSize:
                                                        isKeyboardVisible
                                                            ? 12
                                                            : 14,
                                                  ),
                                                ),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.primaryDeepRose,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  SizedBox(height: isKeyboardVisible ? 16 : 32),

                                  // Connect button
                                  if (_isLoading)
                                    LoadingHeart(
                                      showText: true,
                                      text: 'Connecting hearts...',
                                      // textStyle: TextStyle(
                                      //   fontSize: isKeyboardVisible ? 12 : 14,
                                      // ),
                                    )
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed:
                                            _isCodeComplete
                                                ? _connectWithCode
                                                : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              _isCodeComplete
                                                  ? AppColors.primaryDeepRose
                                                  : AppColors.textLight
                                                      .withOpacity(0.3),
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                            vertical:
                                                isKeyboardVisible ? 12 : 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          elevation: _isCodeComplete ? 4 : 0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.favorite,
                                              size: isKeyboardVisible ? 16 : 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Connect Hearts',
                                              style: TextStyle(
                                                fontSize:
                                                    isKeyboardVisible ? 14 : 16,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    _isCodeComplete
                                                        ? Colors.white
                                                        : AppColors.textLight,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Help text - only show when keyboard is not visible or there's enough space
                            if (!isKeyboardVisible ||
                                availableHeight > 500) ...[
                              SizedBox(height: isKeyboardVisible ? 12 : 16),
                              Container(
                                padding: EdgeInsets.all(
                                  isKeyboardVisible ? 12 : 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Don\'t have a code? Ask your partner to share their couple code with you!',
                                  style: TextStyle(
                                    color: AppColors.textLight,
                                    fontSize: isKeyboardVisible ? 10 : 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

 
  Widget _buildCodeInput(int index, bool isCompact) {
    return Container(
      width: isCompact ? 35 : 45,
      height: isCompact ? 45 : 55,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              _focusNodes[index].hasFocus
                  ? AppColors.primaryDeepRose
                  : AppColors.primaryRose.withOpacity(0.3),
          width: _focusNodes[index].hasFocus ? 2 : 1,
        ),
        boxShadow: [
          if (_focusNodes[index].hasFocus)
            BoxShadow(
              color: AppColors.primaryDeepRose.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: TextFormField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: isCompact ? 16 : 20,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        maxLength: 1,
        decoration: const InputDecoration(
          border: InputBorder.none,
          counterText: '',
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (value) {
          if (value.isNotEmpty) {
            _onCodeChanged(index, value.toUpperCase());
          }
        },
        onTap: () {
          // Clear field on tap for easier editing
          _controllers[index].clear();
        },
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          TextInputFormatter.withFunction((oldValue, newValue) {
            return newValue.copyWith(text: newValue.text.toUpperCase());
          }),
        ],
      ),
    );
  }
}

// Connection success dialog
class _ConnectionSuccessDialog extends StatefulWidget {
  final VoidCallback onComplete;

  const _ConnectionSuccessDialog({required this.onComplete});

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
      if (mounted) widget.onComplete();
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
