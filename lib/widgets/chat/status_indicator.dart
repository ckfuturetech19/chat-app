import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';

class StatusIndicator extends StatefulWidget {
  final bool isDelivered;
  final bool isRead;
  final bool animate;
  final double size;
  final Color? color;

  const StatusIndicator({
    super.key,
    required this.isDelivered,
    required this.isRead,
    this.animate = true,
    this.size = 12,
    this.color,
  });

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with TickerProviderStateMixin {
  late AnimationController _checkController;
  late AnimationController _pulseController;
  late Animation<double> _checkAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _checkAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    ));
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    if (widget.animate) {
      _startAnimations();
    }
  }

  @override
  void didUpdateWidget(StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.animate) {
      if (oldWidget.isDelivered != widget.isDelivered || 
          oldWidget.isRead != widget.isRead) {
        _startAnimations();
      }
    }
  }

  void _startAnimations() {
    if (widget.isDelivered) {
      _checkController.forward();
      
      if (widget.isRead) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _pulseController.forward().then((_) {
              _pulseController.reverse();
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _checkController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_checkAnimation, _pulseAnimation]),
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isRead ? _pulseAnimation.value : 1.0,
          child: _buildStatusIcon(),
        );
      },
    );
  }

  Widget _buildStatusIcon() {
    if (!widget.isDelivered) {
      return _buildPendingIcon();
    } else if (!widget.isRead) {
      return _buildDeliveredIcon();
    } else {
      return _buildReadIcon();
    }
  }

  Widget _buildPendingIcon() {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        valueColor: AlwaysStoppedAnimation<Color>(
          widget.color ?? AppColors.textLight.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildDeliveredIcon() {
    return AnimatedBuilder(
      animation: _checkAnimation,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: CheckMarkPainter(
            progress: _checkAnimation.value,
            color: widget.color ?? AppColors.textLight,
            strokeWidth: 1.5,
          ),
        );
      },
    );
  }

  Widget _buildReadIcon() {
    return AnimatedBuilder(
      animation: _checkAnimation,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: DoubleCheckMarkPainter(
            progress: _checkAnimation.value,
            color: widget.color ?? AppColors.online,
            strokeWidth: 1.5,
          ),
        );
      },
    );
  }
}

// Custom painter for single check mark
class CheckMarkPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  CheckMarkPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final checkSize = size.width * 0.6;
    
    // Check mark path
    final startPoint = Offset(center.dx - checkSize / 3, center.dy);
    final middlePoint = Offset(center.dx - checkSize / 6, center.dy + checkSize / 3);
    final endPoint = Offset(center.dx + checkSize / 2, center.dy - checkSize / 3);
    
    path.moveTo(startPoint.dx, startPoint.dy);
    path.lineTo(middlePoint.dx, middlePoint.dy);
    path.lineTo(endPoint.dx, endPoint.dy);
    
    // Draw with progress
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      final extractedPath = metric.extractPath(0, metric.length * progress);
      canvas.drawPath(extractedPath, paint);
    }
  }

  @override
  bool shouldRepaint(CheckMarkPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

// Custom painter for double check mark
class DoubleCheckMarkPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  DoubleCheckMarkPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final checkSize = size.width * 0.5;
    
    // First check mark (slightly to the left)
    _drawCheckMark(
      canvas,
      paint,
      Offset(center.dx - checkSize / 4, center.dy),
      checkSize * 0.8,
      progress,
    );
    
    // Second check mark (slightly to the right and delayed)
    final secondProgress = math.max(0.0, (progress - 0.3) / 0.7);
    _drawCheckMark(
      canvas,
      paint,
      Offset(center.dx + checkSize / 6, center.dy),
      checkSize * 0.8,
      secondProgress,
    );
  }

  void _drawCheckMark(
    Canvas canvas,
    Paint paint,
    Offset center,
    double size,
    double progress,
  ) {
    final path = Path();
    
    final startPoint = Offset(center.dx - size / 3, center.dy);
    final middlePoint = Offset(center.dx - size / 6, center.dy + size / 3);
    final endPoint = Offset(center.dx + size / 2, center.dy - size / 3);
    
    path.moveTo(startPoint.dx, startPoint.dy);
    path.lineTo(middlePoint.dx, middlePoint.dy);
    path.lineTo(endPoint.dx, endPoint.dy);
    
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      final extractedPath = metric.extractPath(0, metric.length * progress);
      canvas.drawPath(extractedPath, paint);
    }
  }

  @override
  bool shouldRepaint(DoubleCheckMarkPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

// Online status indicator
class OnlineStatusIndicator extends StatefulWidget {
  final bool isOnline;
  final double size;
  final bool showAnimation;

  const OnlineStatusIndicator({
    super.key,
    required this.isOnline,
    this.size = 8,
    this.showAnimation = true,
  });

  @override
  State<OnlineStatusIndicator> createState() => _OnlineStatusIndicatorState();
}

class _OnlineStatusIndicatorState extends State<OnlineStatusIndicator>
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
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    if (widget.showAnimation && widget.isOnline) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(OnlineStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isOnline && widget.showAnimation) {
      _controller.repeat(reverse: true);
    } else {
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isOnline ? AppColors.online : AppColors.offline,
            boxShadow: widget.isOnline && widget.showAnimation
                ? [
                    BoxShadow(
                      color: AppColors.online.withOpacity(0.6),
                      blurRadius: widget.size * _animation.value,
                      spreadRadius: widget.size * (_animation.value - 1) * 0.5,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

// Typing status indicator with dots
class TypingStatusIndicator extends StatefulWidget {
  final bool isTyping;
  final String? userName;
  final double size;

  const TypingStatusIndicator({
    super.key,
    required this.isTyping,
    this.userName,
    this.size = 6,
  });

  @override
  State<TypingStatusIndicator> createState() => _TypingStatusIndicatorState();
}

class _TypingStatusIndicatorState extends State<TypingStatusIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _animations = List.generate(3, (index) {
      return Tween<double>(
        begin: 0.4,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Interval(
          index * 0.2,
          0.6 + (index * 0.2),
          curve: Curves.easeInOut,
        ),
      ));
    });
    
    if (widget.isTyping) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(TypingStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isTyping && !oldWidget.isTyping) {
      _controller.repeat();
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
    if (!widget.isTyping) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.userName != null) ...[
          Text(
            '${widget.userName} ${AppStrings.typing}',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textLight,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 8),
        ],
        
        // Animated dots
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _animations[index],
              builder: (context, child) {
                return Container(
                  margin: EdgeInsets.symmetric(horizontal: widget.size * 0.2),
                  child: Opacity(
                    opacity: _animations[index].value,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.typing,
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

// Message delivery status widget
class MessageDeliveryStatus extends StatelessWidget {
  final bool isDelivered;
  final bool isRead;
  final DateTime? readAt;
  final bool showText;

  const MessageDeliveryStatus({
    super.key,
    required this.isDelivered,
    required this.isRead,
    this.readAt,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusIndicator(
          isDelivered: isDelivered,
          isRead: isRead,
        ),
        
        if (showText) ...[
          const SizedBox(width: 4),
          Text(
            _getStatusText(),
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textLight,
            ),
          ),
        ],
      ],
    );
  }

  String _getStatusText() {
    if (!isDelivered) {
      return AppStrings.sending;
    } else if (!isRead) {
      return AppStrings.delivered;
    } else {
      return AppStrings.read;
    }
  }
}