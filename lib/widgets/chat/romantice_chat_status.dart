import 'package:flutter/material.dart';

// Main romantic status indicator widget
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

// Enhanced message bubble with romantic status
class RomanticMessageBubble extends StatelessWidget {
  final String message;
  final bool isMyMessage;
  final MessageStatus status;
  final DateTime timestamp;
  final bool showAvatar;
  final VoidCallback? onLongPress;

  const RomanticMessageBubble({
    super.key,
    required this.message,
    required this.isMyMessage,
    required this.status,
    required this.timestamp,
    this.showAvatar = true,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment: isMyMessage 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMyMessage && showAvatar) ...[
            _buildAvatar(),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Column(
                crossAxisAlignment: isMyMessage 
                    ? CrossAxisAlignment.end 
                    : CrossAxisAlignment.start,
                children: [
                  _buildMessageContent(context),
                  const SizedBox(height: 4),
                  _buildRomanticStatus(),
                ],
              ),
            ),
          ),
          
          if (isMyMessage && showAvatar) ...[
            const SizedBox(width: 8),
            _buildAvatar(),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isMyMessage 
              ? [const Color(0xFFFF8A95), const Color(0xFFFF6B7A)]
              : [const Color(0xFFCE93D8), const Color(0xFFBA68C8)],
        ),
        boxShadow: [
          BoxShadow(
            color: (isMyMessage 
                ? const Color(0xFFFF8A95) 
                : const Color(0xFFCE93D8)).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.favorite,
        size: 16,
        color: Colors.white,
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isMyMessage
              ? [const Color(0xFFFF8A95), const Color(0xFFFF6B7A)]
              : [const Color(0xFFCE93D8), const Color(0xFFBA68C8)],
        ),
        borderRadius: _getBorderRadius(),
        boxShadow: [
          BoxShadow(
            color: (isMyMessage 
                ? const Color(0xFFFF8A95) 
                : const Color(0xFFCE93D8)).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildRomanticStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(timestamp),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),
          if (isMyMessage) ...[
            const SizedBox(width: 6),
            RomanticStatusIndicator(
              status: status,
              size: 14,
              showLabel: false,
            ),
          ],
        ],
      ),
    );
  }

  BorderRadius _getBorderRadius() {
    const radius = 20.0;
    const smallRadius = 8.0;

    if (isMyMessage) {
      return BorderRadius.only(
        topLeft: const Radius.circular(radius),
        topRight: const Radius.circular(radius),
        bottomLeft: const Radius.circular(radius),
        bottomRight: showAvatar
            ? const Radius.circular(smallRadius)
            : const Radius.circular(radius),
      );
    } else {
      return BorderRadius.only(
        topLeft: const Radius.circular(radius),
        topRight: const Radius.circular(radius),
        bottomLeft: showAvatar
            ? const Radius.circular(smallRadius)
            : const Radius.circular(radius),
        bottomRight: const Radius.circular(radius),
      );
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }
}

// Romantic typing indicator
class RomanticTypingIndicator extends StatefulWidget {
  final String? partnerName;
  final bool isVisible;

  const RomanticTypingIndicator({
    super.key,
    this.partnerName,
    required this.isVisible,
  });

  @override
  State<RomanticTypingIndicator> createState() => _RomanticTypingIndicatorState();
}

class _RomanticTypingIndicatorState extends State<RomanticTypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _dotsController;
  late AnimationController _heartController;
  late List<Animation<double>> _dotAnimations;
  late Animation<double> _heartAnimation;

  @override
  void initState() {
    super.initState();
    
    _dotsController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

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

    _heartAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.easeInOut),
    );

    if (widget.isVisible) {
      _startAnimations();
    }
  }

  @override
  void didUpdateWidget(RomanticTypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isVisible && !oldWidget.isVisible) {
      _startAnimations();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _stopAnimations();
    }
  }

  void _startAnimations() {
    _dotsController.repeat();
    _heartController.repeat(reverse: true);
  }

  void _stopAnimations() {
    _dotsController.stop();
    _dotsController.reset();
    _heartController.stop();
    _heartController.reset();
  }

  @override
  void dispose() {
    _dotsController.dispose();
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _heartAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _heartAnimation.value,
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
                  child: const Icon(
                    Icons.favorite,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                Row(
                  children: List.generate(3, (index) {
                    return AnimatedBuilder(
                      animation: _dotAnimations[index],
                      builder: (context, child) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          child: Opacity(
                            opacity: _dotAnimations[index].value,
                            child: const Text(
                              '💕',
                              style: TextStyle(fontSize: 8),
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
        ],
      ),
    );
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

// Support classes
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

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

// Example usage widget
class RomanticChatExample extends StatefulWidget {
  const RomanticChatExample({super.key});

  @override
  State<RomanticChatExample> createState() => _RomanticChatExampleState();
}

class _RomanticChatExampleState extends State<RomanticChatExample> {
  final List<ExampleMessage> messages = [
    ExampleMessage(
      text: "Good morning, my love! 💕",
      isMyMessage: false,
      status: MessageStatus.read,
      timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
    ),
    ExampleMessage(
      text: "Good morning beautiful! How did you sleep?",
      isMyMessage: true,
      status: MessageStatus.read,
      timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
    ),
    ExampleMessage(
      text: "Like an angel, dreaming of you 😊",
      isMyMessage: false,
      status: MessageStatus.read,
      timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
    ),
    ExampleMessage(
      text: "I can't wait to see you today!",
      isMyMessage: true,
      status: MessageStatus.delivered,
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    ExampleMessage(
      text: "Missing you already... 💖",
      isMyMessage: true,
      status: MessageStatus.sent,
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
    ),
  ];

  bool showTyping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Romantic Chat'),
        backgroundColor: const Color(0xFFCE93D8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite),
            onPressed: () {
              setState(() {
                showTyping = !showTyping;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[messages.length - 1 - index];
                return RomanticMessageBubble(
                  message: message.text,
                  isMyMessage: message.isMyMessage,
                  status: message.status,
                  timestamp: message.timestamp,
                  showAvatar: true,
                );
              },
            ),
          ),
          RomanticTypingIndicator(
            partnerName: "Sarah",
            isVisible: showTyping,
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const TextField(
                      decoration: InputDecoration(
                        hintText: 'Type a sweet message...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8A95), Color(0xFFFF6B7A)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.favorite, color: Colors.white),
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExampleMessage {
  final String text;
  final bool isMyMessage;
  final MessageStatus status;
  final DateTime timestamp;

  ExampleMessage({
    required this.text,
    required this.isMyMessage,
    required this.status,
    required this.timestamp,
  });
}