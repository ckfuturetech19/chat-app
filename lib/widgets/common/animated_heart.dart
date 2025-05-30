import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/constants/app_colors.dart';

class AnimatedHeart extends StatefulWidget {
  final double size;
  final Color color;
  final Duration delay;
  final Duration? duration;
  final bool repeat;

  const AnimatedHeart({
    super.key,
    this.size = 20,
    this.color = AppColors.primaryDeepRose,
    this.delay = Duration.zero,
    this.duration,
    this.repeat = true,
  });

  @override
  State<AnimatedHeart> createState() => _AnimatedHeartState();
}

class _AnimatedHeartState extends State<AnimatedHeart>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _opacityController;
  late AnimationController _rotationController;
  
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    
    final duration = widget.duration ?? const Duration(milliseconds: 2000);
    
    _scaleController = AnimationController(
      duration: duration,
      vsync: this,
    );
    
    _opacityController = AnimationController(
      duration: duration,
      vsync: this,
    );
    
    _rotationController = AnimationController(
      duration: Duration(milliseconds: duration.inMilliseconds * 2),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));
    
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _opacityController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));
    
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _rotationController,
      curve: Curves.linear,
    ));
    
    _startAnimation();
  }

  void _startAnimation() async {
    await Future.delayed(widget.delay);
    
    if (!mounted) return;
    
    if (widget.repeat) {
      _scaleController.repeat(reverse: true);
      _opacityController.repeat(reverse: true);
      _rotationController.repeat();
    } else {
      _scaleController.forward();
      _opacityController.forward();
      _rotationController.forward();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _opacityController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _scaleAnimation,
        _opacityAnimation,
        _rotationAnimation,
      ]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotationAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color,
                      widget.color.withOpacity(0.7),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.3),
                      blurRadius: widget.size * 0.3,
                      spreadRadius: widget.size * 0.1,
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
          ),
        );
      },
    );
  }
}

// Floating hearts widget for message sending animation
class FloatingHeartsWidget extends StatefulWidget {
  final bool isActive;
  final Duration duration;

  const FloatingHeartsWidget({
    super.key,
    required this.isActive,
    this.duration = const Duration(milliseconds: 3000),
  });

  @override
  State<FloatingHeartsWidget> createState() => _FloatingHeartsWidgetState();
}

class _FloatingHeartsWidgetState extends State<FloatingHeartsWidget>
    with TickerProviderStateMixin {
  final List<AnimationController> _controllers = [];
  final List<Animation<Offset>> _animations = [];
  final List<Animation<double>> _opacityAnimations = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _startFloatingHearts();
    }
  }

  @override
  void didUpdateWidget(FloatingHeartsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _startFloatingHearts();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopFloatingHearts();
    }
  }

  void _startFloatingHearts() {
    for (int i = 0; i < 5; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted && widget.isActive) {
          _createFloatingHeart();
        }
      });
    }
  }

  void _createFloatingHeart() {
    final controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    final startX = _random.nextDouble() * 0.6 + 0.2; // Random X position
    final endX = startX + (_random.nextDouble() - 0.5) * 0.4; // Slight horizontal drift

    final animation = Tween<Offset>(
      begin: Offset(startX, 1.2),
      end: Offset(endX, -0.2),
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ));

    final opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    ));

    _controllers.add(controller);
    _animations.add(animation);
    _opacityAnimations.add(opacityAnimation);

    controller.forward().then((_) {
      if (mounted) {
        setState(() {
          final index = _controllers.indexOf(controller);
          if (index != -1) {
            _controllers.removeAt(index);
            _animations.removeAt(index);
            _opacityAnimations.removeAt(index);
          }
        });
        controller.dispose();
      }
    });

    setState(() {});
  }

  void _stopFloatingHearts() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
    _animations.clear();
    _opacityAnimations.clear();
  }

  @override
  void dispose() {
    _stopFloatingHearts();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _animations.asMap().entries.map((entry) {
        final index = entry.key;
        final animation = entry.value;
        final opacityAnimation = _opacityAnimations[index];
        final controller = _controllers[index];

        return AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            return Positioned.fill(
              child: Align(
                alignment: Alignment.lerp(
                  Alignment.bottomCenter,
                  Alignment.topCenter,
                  animation.value.dy + 1.2,
                )!,
                child: Transform.translate(
                  offset: Offset(
                    (animation.value.dx - 0.5) * MediaQuery.of(context).size.width,
                    0,
                  ),
                  child: Opacity(
                    opacity: opacityAnimation.value,
                    child: AnimatedHeart(
                      size: 20 + _random.nextDouble() * 10,
                      color: AppColors.heartColors[index % AppColors.heartColors.length],
                      repeat: false,
                      duration: const Duration(milliseconds: 500),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

// Heart loading indicator
class HeartLoadingIndicator extends StatefulWidget {
  final double size;
  final Color color;

  const HeartLoadingIndicator({
    super.key,
    this.size = 40,
    this.color = AppColors.primaryDeepRose,
  });

  @override
  State<HeartLoadingIndicator> createState() => _HeartLoadingIndicatorState();
}

class _HeartLoadingIndicatorState extends State<HeartLoadingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _animation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    _controller.repeat(reverse: true);
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
        return Transform.scale(
          scale: _animation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.color,
                  widget.color.withOpacity(0.7),
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
              size: widget.size * 0.5,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}