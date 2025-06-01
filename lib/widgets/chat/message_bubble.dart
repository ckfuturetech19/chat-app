import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:onlyus/core/utils/date_utils.dart';
import '../../models/message_model.dart';

// Updated MessageBubble with romantic status integration
class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMyMessage;
  final bool showAvatar;
  final bool showReadStatus;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMyMessage,
    this.showAvatar = true,
    this.showReadStatus = false,
    this.onLongPress,
    this.onTap,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(widget.isMyMessage ? 1.0 : -1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    // Start animation with a slight delay for staggered effect
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment:
                  widget.isMyMessage
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Partner avatar (left side)
                if (!widget.isMyMessage && widget.showAvatar) ...[
                  _buildRomanticAvatar(),
                  const SizedBox(width: 8),
                ] else if (!widget.isMyMessage && !widget.showAvatar) ...[
                  const SizedBox(width: 40), // Space for alignment
                ],

                // Message content
                Flexible(
                  child: GestureDetector(
                    onLongPress: widget.onLongPress,
                    onTap: widget.onTap,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            widget.isMyMessage
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                        children: [
                          _buildMessageBubble(),
                          const SizedBox(height: 4),
                          _buildRomanticMessageInfo(),
                        ],
                      ),
                    ),
                  ),
                ),

                // My avatar (right side)
                if (widget.isMyMessage && widget.showAvatar) ...[
                  const SizedBox(width: 8),
                  _buildRomanticAvatar(),
                ] else if (widget.isMyMessage && !widget.showAvatar) ...[
                  const SizedBox(width: 40), // Space for alignment
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRomanticAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors:
              widget.isMyMessage
                  ? [const Color(0xFFFF8A95), const Color(0xFFFF6B7A)]
                  : [const Color(0xFFCE93D8), const Color(0xFFBA68C8)],
        ),
        boxShadow: [
          BoxShadow(
            color: (widget.isMyMessage
                    ? const Color(0xFFFF8A95)
                    : const Color(0xFFCE93D8))
                .withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.favorite, size: 16, color: Colors.white),
    );
  }

  Widget _buildMessageBubble() {
    return Container(
      padding: _getPadding(),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              widget.isMyMessage
                  ? [const Color(0xFFFF8A95), const Color(0xFFFF6B7A)]
                  : [const Color(0xFFCE93D8), const Color(0xFFBA68C8)],
        ),
        borderRadius: _getBorderRadius(),
        boxShadow: [
          BoxShadow(
            color: (widget.isMyMessage
                    ? const Color(0xFFFF8A95)
                    : const Color(0xFFCE93D8))
                .withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message.type == MessageType.image)
            _buildImageContent()
          else
            _buildTextContent(),
        ],
      ),
    );
  }

  BorderRadius _getBorderRadius() {
    const radius = 20.0;
    const smallRadius = 8.0;

    if (widget.isMyMessage) {
      return BorderRadius.only(
        topLeft: const Radius.circular(radius),
        topRight: const Radius.circular(radius),
        bottomLeft: const Radius.circular(radius),
        bottomRight:
            widget.showAvatar
                ? const Radius.circular(smallRadius)
                : const Radius.circular(radius),
      );
    } else {
      return BorderRadius.only(
        topLeft: const Radius.circular(radius),
        topRight: const Radius.circular(radius),
        bottomLeft:
            widget.showAvatar
                ? const Radius.circular(smallRadius)
                : const Radius.circular(radius),
        bottomRight: const Radius.circular(radius),
      );
    }
  }

  EdgeInsets _getPadding() {
    if (widget.message.type == MessageType.image) {
      return const EdgeInsets.all(4);
    }
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  }

  Widget _buildTextContent() {
    final isOnlyEmojis = widget.message.isOnlyEmojis;

    return Text(
      widget.message.messageContent,
      style: TextStyle(
        fontSize: isOnlyEmojis ? 32 : 16,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildImageContent() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: widget.message.imageUrl!,
              fit: BoxFit.cover,
              placeholder:
                  (context, url) => Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
              errorWidget:
                  (context, url, error) => Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
            ),

            // Caption overlay if exists
            if (widget.message.message.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Text(
                    widget.message.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ENHANCED: Romantic message info with new status system
  Widget _buildRomanticMessageInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppDateUtils.formatMessageTime(widget.message.timestamp),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),

          // Show romantic status for own messages when enabled
          if (widget.isMyMessage && widget.showReadStatus) ...[
            const SizedBox(width: 6),
            RomanticStatusIndicator(
              status: _getMessageStatus(),
              size: 14,
              showLabel: false,
              animate: true,
            ),
          ],
        ],
      ),
    );
  }

  // Convert MessageModel status to RomanticStatus
  MessageStatus _getMessageStatus() {
    // Check if message is deleted first
    if (widget.message.isDeleted == true) {
      return MessageStatus.failed; // Shows as "Queued 🌙"
    }

    // For received messages (not my message), don't show status
    if (!widget.isMyMessage) {
      return MessageStatus.delivered;
    }

    // For sent messages by current user
    if (!widget.message.isDelivered) {
      return MessageStatus.sending; // Shows "💌" - still sending
    }

    // Check read status
    if (widget.message.isRead) {
      return MessageStatus.read; // Shows "💖" - read by partner
    }

    // Message is delivered but not read
    return MessageStatus.delivered; // Shows "🌸" - delivered but not read
  }
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
  State<RomanticStatusIndicator> createState() =>
      _RomanticStatusIndicatorState();
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

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _sparkleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sparkleController, curve: Curves.easeInOut),
    );

    _bloomAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _bloomController, curve: Curves.easeInOut),
    );
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
            child:
                widget.showLabel ? _buildStatusWithLabel() : _buildStatusIcon(),
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
          style:
              widget.labelStyle ??
              TextStyle(
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
          style: TextStyle(fontSize: widget.size * 0.7, height: 1.0),
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
    final paint =
        Paint()
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

// Support classes
enum MessageStatus { sending, sent, delivered, read, failed }

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
