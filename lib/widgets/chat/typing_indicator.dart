import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../common/gradient_background.dart';

class TypingIndicator extends StatefulWidget {
  final bool isTyping;
  final String? userName;
  final Duration animationDuration;
  final double bubbleSize;
  final bool showAvatar;

  const TypingIndicator({
    super.key,
    required this.isTyping,
    this.userName,
    this.animationDuration = const Duration(milliseconds: 300),
    this.bubbleSize = 8,
    this.showAvatar = true,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _dotsController;
  late AnimationController _pulseController;

  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late List<Animation<double>> _dotAnimations;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _dotsController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    // Create staggered dot animations
    _dotAnimations = List.generate(3, (index) {
      return Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(
          parent: _dotsController,
          curve: Interval(
            index * 0.2,
            0.6 + (index * 0.2),
            curve: Curves.easeInOut,
          ),
        ),
      );
    });

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isTyping) {
      _startAnimations();
    }
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isTyping && !oldWidget.isTyping) {
      _startAnimations();
    } else if (!widget.isTyping && oldWidget.isTyping) {
      _stopAnimations();
    }
  }

  void _startAnimations() {
    _slideController.forward();
    _dotsController.repeat();
    _pulseController.repeat(reverse: true);
  }

  void _stopAnimations() {
    _slideController.reverse();
    _dotsController.stop();
    _dotsController.reset();
    _pulseController.stop();
    _pulseController.reset();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _dotsController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: widget.animationDuration,
      curve: Curves.easeOutCubic,
      child:
          widget.isTyping ? _buildTypingIndicator() : const SizedBox.shrink(),
    );
  }

  Widget _buildTypingIndicator() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Avatar
              if (widget.showAvatar) ...[
                _buildTypingAvatar(),
                const SizedBox(width: 8),
              ],

              // Typing bubble
              _buildTypingBubble(),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingAvatar() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.partnerMessageGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondaryDeepPurple.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.favorite, size: 16, color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildTypingBubble() {
    return MessageBubbleGradient(
      isMyMessage: false,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Typing text
            if (widget.userName != null) ...[
              Text(
                '${widget.userName} ${AppStrings.typing}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Animated dots
            _buildAnimatedDots(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _dotAnimations[index],
          builder: (context, child) {
            return Container(
              margin: EdgeInsets.symmetric(horizontal: widget.bubbleSize * 0.2),
              child: Transform.scale(
                scale: _dotAnimations[index].value,
                child: Container(
                  width: widget.bubbleSize,
                  height: widget.bubbleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// Advanced typing indicator with heart dots
class HeartTypingIndicator extends StatefulWidget {
  final bool isTyping;
  final String? userName;
  final Color color;

  const HeartTypingIndicator({
    super.key,
    required this.isTyping,
    this.userName,
    this.color = AppColors.typing,
  });

  @override
  State<HeartTypingIndicator> createState() => _HeartTypingIndicatorState();
}

class _HeartTypingIndicatorState extends State<HeartTypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<AnimationController> _heartControllers;
  late List<Animation<double>> _heartAnimations;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Create individual controllers for each heart
    _heartControllers = List.generate(3, (index) {
      return AnimationController(
        duration: const Duration(milliseconds: 800),
        vsync: this,
      );
    });

    _heartAnimations =
        _heartControllers.map((controller) {
          return Tween<double>(begin: 0.5, end: 1.0).animate(
            CurvedAnimation(parent: controller, curve: Curves.easeInOut),
          );
        }).toList();

    if (widget.isTyping) {
      _startHeartAnimations();
    }
  }

  void _startHeartAnimations() {
    _controller.forward();

    // Start each heart animation with a delay
    for (int i = 0; i < _heartControllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted && widget.isTyping) {
          _heartControllers[i].repeat(reverse: true);
        }
      });
    }
  }

  void _stopHeartAnimations() {
    _controller.reverse();

    for (final controller in _heartControllers) {
      controller.stop();
      controller.reset();
    }
  }

  @override
  void didUpdateWidget(HeartTypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isTyping && !oldWidget.isTyping) {
      _startHeartAnimations();
    } else if (!widget.isTyping && oldWidget.isTyping) {
      _stopHeartAnimations();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final controller in _heartControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: widget.isTyping ? _buildHeartIndicator() : const SizedBox.shrink(),
    );
  }

  Widget _buildHeartIndicator() {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Typing text
            if (widget.userName != null) ...[
              Text(
                '${widget.userName} ${AppStrings.typing}',
                style: TextStyle(
                  color: AppColors.textLight,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Animated hearts
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _heartAnimations[index],
                  builder: (context, child) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.scale(
                        scale: _heartAnimations[index].value,
                        child: Icon(
                          Icons.favorite,
                          size: 12,
                          color: widget.color.withOpacity(
                            _heartAnimations[index].value,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// Floating typing indicator
class FloatingTypingIndicator extends StatefulWidget {
  final bool isTyping;
  final String? userName;

  const FloatingTypingIndicator({
    super.key,
    required this.isTyping,
    this.userName,
  });

  @override
  State<FloatingTypingIndicator> createState() =>
      _FloatingTypingIndicatorState();
}

class _FloatingTypingIndicatorState extends State<FloatingTypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _bounceAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _bounceAnimation = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0, -0.3),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.isTyping) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(FloatingTypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isTyping && !oldWidget.isTyping) {
      _controller.repeat(reverse: true);
    } else if (!widget.isTyping && oldWidget.isTyping) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isTyping) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: _bounceAnimation.value * 10,
          child: Container(
            margin: const EdgeInsets.only(left: 16, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryRose.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDeepRose.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.userName != null) ...[
                  Text(
                    '${widget.userName} ${AppStrings.typing}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.more_horiz, color: Colors.white, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
