import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/constants/app_colors.dart';

class LoadingHeart extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;
  final bool showText;
  final String? text;

  const LoadingHeart({
    super.key,
    this.size = 60,
    this.color = AppColors.primaryDeepRose,
    this.duration = const Duration(milliseconds: 1200),
    this.showText = false,
    this.text,
  });

  @override
  State<LoadingHeart> createState() => _LoadingHeartState();
}

class _LoadingHeartState extends State<LoadingHeart>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _scaleController;

  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation
    _pulseController = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Rotation animation
    _rotationController = AnimationController(
      duration: Duration(milliseconds: widget.duration.inMilliseconds * 3),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    // Scale animation for subtle breathing effect
    _scaleController = AnimationController(
      duration: Duration(milliseconds: widget.duration.inMilliseconds ~/ 2),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    _startAnimations();
  }

  void _startAnimations() {
    _pulseController.repeat(reverse: true);
    _rotationController.repeat();
    _scaleController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Heart loading animation
        AnimatedBuilder(
          animation: Listenable.merge([
            _pulseAnimation,
            _rotationAnimation,
            _scaleAnimation,
          ]),
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Transform.rotate(
                angle: _rotationAnimation.value * 0.1, // Subtle rotation
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow effect
                    Container(
                      width: widget.size * _pulseAnimation.value * 1.5,
                      height: widget.size * _pulseAnimation.value * 1.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            widget.color.withOpacity(0.1),
                            widget.color.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),

                    // Main heart
                    Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              widget.color,
                              widget.color.withOpacity(0.8),
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withOpacity(0.3),
                              blurRadius: widget.size * 0.2,
                              spreadRadius: widget.size * 0.05,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.favorite,
                          size: widget.size * 0.6,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    // Floating particles
                    ...List.generate(6, (index) {
                      final angle = (index * 60.0) * (math.pi / 180.0);
                      final radius = widget.size * 0.8;
                      final particleOffset = Offset(
                        radius * math.cos(angle + _rotationAnimation.value),
                        radius * math.sin(angle + _rotationAnimation.value),
                      );

                      // Fix: Clamp opacity to valid range (0.0 to 1.0)
                      final particleOpacity =
                          ((math.sin(_pulseAnimation.value * math.pi) * 0.5 +
                                  0.5)
                              .clamp(0.0, 1.0));

                      return Transform.translate(
                        offset: particleOffset,
                        child: Opacity(
                          opacity: particleOpacity,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: widget.color.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        ),

        // Loading text
        if (widget.showText) ...[
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              // Fix: Clamp opacity to valid range (0.0 to 1.0)
              final textOpacity = (_pulseAnimation.value * 0.7 + 0.3).clamp(
                0.0,
                1.0,
              );

              return Opacity(
                opacity: textOpacity,
                child: Text(
                  widget.text ?? 'Loading...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: widget.color.withOpacity(0.8),
                    fontFamily: 'SF Pro Text',
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

// Specific loading heart for different states
class ChatLoadingHeart extends StatelessWidget {
  const ChatLoadingHeart({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoadingHeart(
      size: 40,
      showText: true,
      text: 'Loading messages...',
      color: AppColors.primaryDeepRose,
    );
  }
}

class SendingMessageHeart extends StatelessWidget {
  const SendingMessageHeart({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoadingHeart(
      size: 20,
      showText: false,
      color: AppColors.secondaryDeepPurple,
      duration: Duration(milliseconds: 800),
    );
  }
}

class UploadingImageHeart extends StatelessWidget {
  const UploadingImageHeart({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoadingHeart(
      size: 50,
      showText: true,
      text: 'Uploading image...',
      color: AppColors.accentDeepGold,
    );
  }
}

// Multi-heart loading animation for special occasions
class MultiHeartLoading extends StatefulWidget {
  final int heartCount;
  final double size;
  final Duration duration;

  const MultiHeartLoading({
    super.key,
    this.heartCount = 3,
    this.size = 30,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<MultiHeartLoading> createState() => _MultiHeartLoadingState();
}

class _MultiHeartLoadingState extends State<MultiHeartLoading>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(
      widget.heartCount,
      (index) => AnimationController(duration: widget.duration, vsync: this),
    );

    _animations =
        _controllers.map((controller) {
          return Tween<double>(begin: 0.5, end: 1.0).animate(
            CurvedAnimation(parent: controller, curve: Curves.easeInOut),
          );
        }).toList();

    // Start animations with delays
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.heartCount, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.size * 0.1),
              child: Transform.scale(
                scale: _animations[index].value,
                child: Opacity(
                  opacity: _animations[index].value,
                  child: Icon(
                    Icons.favorite,
                    size: widget.size,
                    color:
                        AppColors.heartColors[index %
                            AppColors.heartColors.length],
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

// Circular progress with heart
class HeartCircularProgress extends StatefulWidget {
  final double size;
  final double progress;
  final Color color;
  final bool showPercentage;

  const HeartCircularProgress({
    super.key,
    this.size = 80,
    this.progress = 0.0,
    this.color = AppColors.primaryDeepRose,
    this.showPercentage = true,
  });

  @override
  State<HeartCircularProgress> createState() => _HeartCircularProgressState();
}

class _HeartCircularProgressState extends State<HeartCircularProgress>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartAnimation;

  @override
  void initState() {
    super.initState();

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _heartAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.easeInOut),
    );

    _heartController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withOpacity(0.1),
            ),
          ),

          // Progress circle
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CircularProgressIndicator(
              value: widget.progress,
              strokeWidth: 4,
              backgroundColor: widget.color.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(widget.color),
            ),
          ),

          // Center heart
          AnimatedBuilder(
            animation: _heartAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _heartAnimation.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite,
                      size: widget.size * 0.3,
                      color: widget.color,
                    ),
                    if (widget.showPercentage) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${(widget.progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: widget.size * 0.12,
                          fontWeight: FontWeight.w600,
                          color: widget.color,
                          fontFamily: 'SF Pro Text',
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// Heart dots loading (like typing indicator)
class HeartDotsLoading extends StatefulWidget {
  final double size;
  final Color color;
  final int dotCount;

  const HeartDotsLoading({
    super.key,
    this.size = 8,
    this.color = AppColors.primaryDeepRose,
    this.dotCount = 3,
  });

  @override
  State<HeartDotsLoading> createState() => _HeartDotsLoadingState();
}

class _HeartDotsLoadingState extends State<HeartDotsLoading>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(
      widget.dotCount,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      ),
    );

    _animations =
        _controllers.map((controller) {
          return Tween<double>(begin: 0.4, end: 1.0).animate(
            CurvedAnimation(parent: controller, curve: Curves.easeInOut),
          );
        }).toList();

    // Start animations with staggered delays
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.dotCount, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              margin: EdgeInsets.symmetric(horizontal: widget.size * 0.2),
              child: Opacity(
                opacity: _animations[index].value,
                child: Icon(
                  Icons.favorite,
                  size: widget.size * _animations[index].value,
                  color: widget.color,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// Shimmer heart loading
class ShimmerHeartLoading extends StatefulWidget {
  final double size;
  final Color baseColor;
  final Color highlightColor;

  const ShimmerHeartLoading({
    super.key,
    this.size = 60,
    this.baseColor = AppColors.primaryRose,
    this.highlightColor = AppColors.primaryDeepRose,
  });

  @override
  State<ShimmerHeartLoading> createState() => _ShimmerHeartLoadingState();
}

class _ShimmerHeartLoadingState extends State<ShimmerHeartLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops:
                  [
                    _animation.value - 0.3,
                    _animation.value,
                    _animation.value + 0.3,
                  ].map((stop) => stop.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          child: Icon(Icons.favorite, size: widget.size, color: Colors.white),
        );
      },
    );
  }
}
