import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../common/gradient_background.dart';

// Enhanced Romantic Typing Indicator
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
  late AnimationController _glowController;

  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late List<Animation<double>> _dotAnimations;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

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

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
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

    // Create staggered heart dot animations
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

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
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
    _glowController.repeat(reverse: true);
  }

  void _stopAnimations() {
    _slideController.reverse();
    _dotsController.stop();
    _dotsController.reset();
    _pulseController.stop();
    _pulseController.reset();
    _glowController.stop();
    _glowController.reset();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _dotsController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
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
              // Romantic Avatar
              if (widget.showAvatar) ...[
                _buildRomanticTypingAvatar(),
                const SizedBox(width: 8),
              ],

              // Romantic Typing bubble
              _buildRomanticTypingBubble(),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRomanticTypingAvatar() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _glowAnimation]),
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFFCE93D8,
                ).withOpacity(0.3 * _glowAnimation.value),
                blurRadius: 12 * _glowAnimation.value,
                spreadRadius: 4 * _glowAnimation.value,
              ),
            ],
          ),
          child: Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFCE93D8), Color(0xFFBA68C8)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFCE93D8).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Icon(Icons.favorite, size: 16, color: Colors.white),
                  ),
                  // Sparkle effect
                  AnimatedBuilder(
                    animation: _glowAnimation,
                    builder: (context, child) {
                      return Positioned.fill(
                        child: CustomPaint(
                          painter: AvatarSparklePainter(
                            progress: _glowAnimation.value,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRomanticTypingBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFCE93D8), Color(0xFFBA68C8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCE93D8).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Typing text with romantic styling
          if (widget.userName != null) ...[
            Text(
              '${widget.userName} ${AppStrings.typing}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Animated heart dots
          _buildRomanticAnimatedDots(),
        ],
      ),
    );
  }

  Widget _buildRomanticAnimatedDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _dotAnimations[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              child: Transform.scale(
                scale: _dotAnimations[index].value,
                child: Opacity(
                  opacity: _dotAnimations[index].value,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    child: const Text('💕', style: TextStyle(fontSize: 8)),
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

// Enhanced Heart Typing Indicator
class HeartTypingIndicator extends StatefulWidget {
  final bool isTyping;
  final String? userName;
  final Color color;

  const HeartTypingIndicator({
    super.key,
    required this.isTyping,
    this.userName,
    this.color = const Color(0xFFFF8A95),
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
            // Romantic typing text
            if (widget.userName != null) ...[
              Text(
                '${widget.userName} ${AppStrings.typing}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Animated romantic hearts
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
                        child: Text(
                          ['💕', '💖', '💗'][index],
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.color.withOpacity(
                              _heartAnimations[index].value,
                            ),
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

// Floating Hearts Typing Indicator
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
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8A95), Color(0xFFFF6B7A)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8A95).withOpacity(0.3),
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
                const Text('💕', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Floating Hearts Animation (Alternative Style)
class FloatingHeartsTypingIndicator extends StatefulWidget {
  final String? partnerName;
  final bool isVisible;
  final int heartCount;

  const FloatingHeartsTypingIndicator({
    super.key,
    this.partnerName,
    required this.isVisible,
    this.heartCount = 5,
  });

  @override
  State<FloatingHeartsTypingIndicator> createState() =>
      _FloatingHeartsTypingIndicatorState();
}

class _FloatingHeartsTypingIndicatorState
    extends State<FloatingHeartsTypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<AnimationController> _heartControllers;
  late List<Animation<Offset>> _heartAnimations;
  late List<Animation<double>> _heartOpacityAnimations;

  @override
  void initState() {
    super.initState();
    _setupHeartAnimations();

    if (widget.isVisible) {
      _startHeartAnimations();
    }
  }

  void _setupHeartAnimations() {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _heartControllers = List.generate(widget.heartCount, (index) {
      return AnimationController(
        duration: Duration(milliseconds: 2000 + (index * 200)),
        vsync: this,
      );
    });

    _heartAnimations =
        _heartControllers.map((controller) {
          return Tween<Offset>(
            begin: const Offset(0, 0),
            end: Offset(
              (math.Random().nextDouble() - 0.5) *
                  2, // Random horizontal movement
              -3.0, // Float upward
            ),
          ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));
        }).toList();

    _heartOpacityAnimations =
        _heartControllers.map((controller) {
          return Tween<double>(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(
              parent: controller,
              curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
            ),
          );
        }).toList();
  }

  void _startHeartAnimations() {
    _controller.forward();

    // Start heart animations with staggered delays
    for (int i = 0; i < _heartControllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 300), () {
        if (mounted && widget.isVisible) {
          _heartControllers[i].repeat();
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
  void didUpdateWidget(FloatingHeartsTypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isVisible && !oldWidget.isVisible) {
      _startHeartAnimations();
    } else if (!widget.isVisible && oldWidget.isVisible) {
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
    if (!widget.isVisible) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _controller,
      child: Container(
        height: 100,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          children: [
            // Typing indicator base
            Positioned(
              bottom: 0,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFCE93D8), Color(0xFFBA68C8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFCE93D8).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.partnerName ?? 'Your love'} is typing',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('💕', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),

            // Floating hearts
            ...List.generate(widget.heartCount, (index) {
              return AnimatedBuilder(
                animation: Listenable.merge([
                  _heartAnimations[index],
                  _heartOpacityAnimations[index],
                ]),
                builder: (context, child) {
                  return Positioned(
                    left: 50 + (index * 10.0),
                    bottom: 30,
                    child: Transform.translate(
                      offset: _heartAnimations[index].value * 20,
                      child: Opacity(
                        opacity: _heartOpacityAnimations[index].value,
                        child: Text(
                          ['💕', '💖', '💗', '💝', '💘'][index % 5],
                          style: TextStyle(fontSize: 12 + (index % 3) * 2.0),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

// Custom painter for avatar sparkle effects
class AvatarSparklePainter extends CustomPainter {
  final double progress;
  final Color color;

  AvatarSparklePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color.withOpacity(0.6 * progress)
          ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final sparklePositions = [
      Offset(center.dx - 6, center.dy - 6),
      Offset(center.dx + 6, center.dy - 6),
      Offset(center.dx + 6, center.dy + 6),
      Offset(center.dx - 6, center.dy + 6),
    ];

    for (int i = 0; i < sparklePositions.length; i++) {
      final sparkleProgress = ((progress + (i * 0.25)) % 1.0);
      final sparkleSize = 1.5 * sparkleProgress;

      if (sparkleProgress > 0.2 && sparkleProgress < 0.8) {
        _drawMiniSparkle(canvas, paint, sparklePositions[i], sparkleSize);
      }
    }
  }

  void _drawMiniSparkle(
    Canvas canvas,
    Paint paint,
    Offset position,
    double size,
  ) {
    // Draw a simple plus sign sparkle
    canvas.drawRect(
      Rect.fromCenter(center: position, width: size * 3, height: size),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: position, width: size, height: size * 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(AvatarSparklePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
