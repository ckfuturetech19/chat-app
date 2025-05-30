import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/constants/app_colors.dart';

class GradientBackground extends StatefulWidget {
  final Widget child;
  final List<Color>? colors;
  final bool animated;
  final Duration animationDuration;

  const GradientBackground({
    super.key,
    required this.child,
    this.colors,
    this.animated = true,
    this.animationDuration = const Duration(seconds: 8),
  });

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  // Multiple gradient configurations for smooth transitions
  final List<LinearGradient> _gradients = [
    const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFFFBEB), // Cream
        Color(0xFFFFE4E6), // Light pink
        Color(0xFFF3E8FF), // Light purple
      ],
      stops: [0.0, 0.5, 1.0],
    ),
    const LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        Color(0xFFFEF7ED), // Warm ivory
        Color(0xFFFECDD3), // Rose
        Color(0xFFDDD6FE), // Lavender
      ],
      stops: [0.0, 0.4, 1.0],
    ),
    const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFFEF3C7), // Light gold
        Color(0xFFFFE4E6), // Light pink
        Color(0xFFF3E8FF), // Light purple
      ],
      stops: [0.0, 0.6, 1.0],
    ),
  ];

  @override
  void initState() {
    super.initState();
    
    if (widget.animated) {
      _animationController = AnimationController(
        duration: widget.animationDuration,
        vsync: this,
      );
      
      _animation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ));
      
      _animationController.repeat();
    }
  }

  @override
  void dispose() {
    if (widget.animated) {
      _animationController.dispose();
    }
    super.dispose();
  }

  LinearGradient _interpolateGradients(double t) {
    // Calculate which two gradients to interpolate between
    final scaledT = t * (_gradients.length - 1);
    final index = scaledT.floor();
    final fraction = scaledT - index;
    
    final gradient1 = _gradients[index % _gradients.length];
    final gradient2 = _gradients[(index + 1) % _gradients.length];
    
    // Interpolate colors
    final interpolatedColors = <Color>[];
    final maxStops = math.max(gradient1.colors.length, gradient2.colors.length);
    
    for (int i = 0; i < maxStops; i++) {
      final color1 = gradient1.colors[i % gradient1.colors.length];
      final color2 = gradient2.colors[i % gradient2.colors.length];
      interpolatedColors.add(Color.lerp(color1, color2, fraction)!);
    }
    
    // Interpolate alignment
    final beginAlignment = AlignmentGeometry.lerp(
      gradient1.begin,
      gradient2.begin,
      fraction,
    )!;
    
    final endAlignment = AlignmentGeometry.lerp(
      gradient1.end,
      gradient2.end,
      fraction,
    )!;
    
    return LinearGradient(
      begin: beginAlignment,
      end: endAlignment,
      colors: interpolatedColors,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animated) {
      return Container(
        decoration: BoxDecoration(
          gradient: widget.colors != null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.colors!,
                )
              : AppColors.backgroundGradient,
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: _interpolateGradients(_animation.value),
          ),
          child: widget.child,
        );
      },
    );
  }
}

// Chat-specific gradient background
class ChatGradientBackground extends StatelessWidget {
  final Widget child;

  const ChatGradientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.chatBackgroundGradient,
      ),
      child: child,
    );
  }
}

// Message bubble gradient
class MessageBubbleGradient extends StatelessWidget {
  final Widget child;
  final bool isMyMessage;
  final BorderRadius? borderRadius;

  const MessageBubbleGradient({
    super.key,
    required this.child,
    required this.isMyMessage,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: isMyMessage
            ? AppColors.myMessageGradient
            : AppColors.partnerMessageGradient,
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isMyMessage 
                ? AppColors.primaryDeepRose 
                : AppColors.secondaryDeepPurple
            ).withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// Button gradient
class ButtonGradient extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final List<Color>? colors;

  const ButtonGradient({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius,
    this.padding,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: colors != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors!,
              )
            : AppColors.buttonGradient,
        borderRadius: borderRadius ?? BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDeepRose.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius ?? BorderRadius.circular(25),
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// Shimmer gradient for loading states
class ShimmerGradient extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const ShimmerGradient({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFE0E0E0),
    this.highlightColor = const Color(0xFFF5F5F5),
  });

  @override
  State<ShimmerGradient> createState() => _ShimmerGradientState();
}

class _ShimmerGradientState extends State<ShimmerGradient>
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
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
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
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ].map((stop) => stop.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}