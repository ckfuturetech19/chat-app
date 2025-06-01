// Add this to your MessageBubble file or create as a separate romantic_status.dart file

import 'package:flutter/material.dart';

import '../../models/message_model.dart';

// Message Status Enum
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

// Status Info Class
class StatusInfo {
  final String icon;
  final String label;
  final Color color;
  final Color backgroundColor;

  StatusInfo({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
  });
}

// Romantic Status Indicator Widget
class RomanticStatusIndicator extends StatefulWidget {
  final MessageStatus status;
  final double size;
  final bool animate;
  final bool showLabel;
  final TextStyle? labelStyle;
  final Duration animationDuration;

  const RomanticStatusIndicator({
    super.key,
    required this.status,
    this.size = 16,
    this.animate = true,
    this.showLabel = true,
    this.labelStyle,
    this.animationDuration = const Duration(milliseconds: 800),
  });

  @override
  State<RomanticStatusIndicator> createState() => _RomanticStatusIndicatorState();
}

class _RomanticStatusIndicatorState extends State<RomanticStatusIndicator>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _sparkleController;
  late AnimationController _bloomController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _sparkleAnimation;
  late Animation<double> _bloomAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    
    if (widget.animate) {
      _startStatusAnimation();
    }
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _sparkleController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _bloomController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));

    _sparkleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _sparkleController,
      curve: Curves.easeInOut,
    ));

    _bloomAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _bloomController,
      curve: Curves.easeInOut,
    ));
  }

  void _startStatusAnimation() {
    _fadeController.forward();
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _scaleController.forward();
    });

    // Special animations for different statuses
    switch (widget.status) {
      case MessageStatus.read:
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _sparkleController.repeat(reverse: true);
            _bloomController.forward().then((_) => _bloomController.reverse());
          }
        });
        break;
      case MessageStatus.delivered:
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _bloomController.forward().then((_) => _bloomController.reverse());
          }
        });
        break;
      default:
        break;
    }
  }

  @override
  void didUpdateWidget(RomanticStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.status != widget.status && widget.animate) {
      _restartAnimations();
    }
  }

  void _restartAnimations() {
    _fadeController.reset();
    _scaleController.reset();
    _sparkleController.reset();
    _bloomController.reset();
    
    _startStatusAnimation();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _sparkleController.dispose();
    _bloomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _fadeAnimation,
        _scaleAnimation,
        _sparkleAnimation,
        _bloomAnimation,
      ]),
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Transform.scale(
            scale: _scaleAnimation.value * _bloomAnimation.value,
            child: widget.showLabel 
                ? _buildStatusWithLabel()
                : _buildStatusIcon(),
          ),
        );
      },
    );
  }

  Widget _buildStatusWithLabel() {
    final statusInfo = _getStatusInfo();
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _buildStatusIcon(),
            if (widget.status == MessageStatus.read && widget.animate)
              _buildSparkleEffect(),
          ],
        ),
        const SizedBox(width: 4),
        Text(
          statusInfo.label,
          style: widget.labelStyle ?? TextStyle(
            fontSize: 10,
            color: statusInfo.color.withOpacity(0.8),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon() {
    final statusInfo = _getStatusInfo();
    
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: statusInfo.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: statusInfo.color.withOpacity(0.3),
            blurRadius: 4,
            spreadRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          statusInfo.icon,
          style: TextStyle(
            fontSize: widget.size * 0.7,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildSparkleEffect() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _sparkleAnimation,
        builder: (context, child) {
          return CustomPaint(
            painter: SparklePainter(
              progress: _sparkleAnimation.value,
              color: const Color(0xFFFFD700),
            ),
          );
        },
      ),
    );
  }

  StatusInfo _getStatusInfo() {
    switch (widget.status) {
      case MessageStatus.sending:
        return StatusInfo(
          icon: '💌',
          label: 'Sending with 💌',
          color: const Color(0xFFE1BEE7),
          backgroundColor: const Color(0xFFF3E5F5),
        );
      case MessageStatus.sent:
        return StatusInfo(
          icon: '💌',
          label: 'Sent with 💌',
          color: const Color(0xFFCE93D8),
          backgroundColor: const Color(0xFFF3E5F5),
        );
      case MessageStatus.delivered:
        return StatusInfo(
          icon: '🌸',
          label: 'Delivered 🌸',
          color: const Color(0xFFF8BBD9),
          backgroundColor: const Color(0xFFFCE4EC),
        );
      case MessageStatus.read:
        return StatusInfo(
          icon: '💖',
          label: 'Read with 💖',
          color: const Color(0xFFFF8A95),
          backgroundColor: const Color(0xFFFFEBEE),
        );
      case MessageStatus.failed:
        return StatusInfo(
          icon: '🌙',
          label: 'Queued 🌙',
          color: const Color(0xFFB0BEC5),
          backgroundColor: const Color(0xFFECEFF1),
        );
    }
  }
}

// Custom painter for sparkle effects
class SparklePainter extends CustomPainter {
  final double progress;
  final Color color;

  SparklePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8 * progress)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final sparklePositions = [
      Offset(center.dx - 8, center.dy - 8),
      Offset(center.dx + 8, center.dy - 8),
      Offset(center.dx, center.dy + 10),
    ];

    for (int i = 0; i < sparklePositions.length; i++) {
      final sparkleProgress = ((progress + (i * 0.3)) % 1.0);
      final sparkleSize = 2.0 * sparkleProgress;
      
      if (sparkleProgress > 0.1 && sparkleProgress < 0.9) {
        _drawSparkle(canvas, paint, sparklePositions[i], sparkleSize);
      }
    }
  }

  void _drawSparkle(Canvas canvas, Paint paint, Offset position, double size) {
    final path = Path();
    
    // Create a simple star shape
    path.moveTo(position.dx, position.dy - size);
    path.lineTo(position.dx + size * 0.3, position.dy - size * 0.3);
    path.lineTo(position.dx + size, position.dy);
    path.lineTo(position.dx + size * 0.3, position.dy + size * 0.3);
    path.lineTo(position.dx, position.dy + size);
    path.lineTo(position.dx - size * 0.3, position.dy + size * 0.3);
    path.lineTo(position.dx - size, position.dy);
    path.lineTo(position.dx - size * 0.3, position.dy - size * 0.3);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(SparklePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// Helper extension to convert MessageModel to MessageStatus
extension MessageModelExtension on MessageModel {
  MessageStatus get romanticStatus {
    if (!isDelivered) {
      return MessageStatus.sending;
    } else if (!isRead) {
      return MessageStatus.delivered;
    } else {
      return MessageStatus.read;
    }
  }
}