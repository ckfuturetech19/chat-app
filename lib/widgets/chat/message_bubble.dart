import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:onlyus/core/utils/date_utils.dart';
import 'dart:math' as math;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_themes.dart';
import '../../models/message_model.dart';
import '../common/gradient_background.dart';
import 'status_indicator.dart';

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMyMessage;
  final bool showAvatar;
  final bool showReadStatus; // NEW: Added parameter for read status
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMyMessage,
    this.showAvatar = true,
    this.showReadStatus = false, // NEW: Default value
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
                  _buildAvatar(),
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
                          _buildMessageInfo(),
                        ],
                      ),
                    ),
                  ),
                ),

                // My avatar (right side)
                if (widget.isMyMessage && widget.showAvatar) ...[
                  const SizedBox(width: 8),
                  _buildAvatar(),
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

  Widget _buildAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            widget.isMyMessage
                ? AppColors.myMessageGradient
                : AppColors.partnerMessageGradient,
        boxShadow: [
          BoxShadow(
            color: (widget.isMyMessage
                    ? AppColors.primaryDeepRose
                    : AppColors.secondaryDeepPurple)
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
    return MessageBubbleGradient(
      isMyMessage: widget.isMyMessage,
      borderRadius: _getBorderRadius(),
      child: Container(
        padding: _getPadding(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message.type == MessageType.image)
              _buildImageContent()
            else
              _buildTextContent(),
          ],
        ),
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
      widget.message.message,
      style: AppThemes.messageTextStyle.copyWith(
        fontSize: isOnlyEmojis ? 32 : 16,
        color: Colors.white,
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
                    style: AppThemes.messageTextStyle.copyWith(fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ENHANCED: Message info with optional read status
  Widget _buildMessageInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppDateUtils.formatMessageTime(widget.message.timestamp),
            style: AppThemes.timestampTextStyle,
          ),

          // Show read status for own messages when enabled
          if (widget.isMyMessage && widget.showReadStatus) ...[
            const SizedBox(width: 4),
            StatusIndicator(
              isDelivered: widget.message.isDelivered,
              isRead: widget.message.isRead,
              animate: true,
            ),
          ],
        ],
      ),
    );
  }
}

// Special message bubble for system messages
class SystemMessageBubble extends StatelessWidget {
  final String message;
  final IconData? icon;

  const SystemMessageBubble({super.key, required this.message, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.textLight.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.textLight),
                const SizedBox(width: 8),
              ],
              Text(
                message,
                style: AppThemes.timestampTextStyle.copyWith(
                  color: AppColors.textLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Date separator bubble
class DateSeparatorBubble extends StatelessWidget {
  final DateTime date;

  const DateSeparatorBubble({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: AppColors.buttonGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDeepRose.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            AppDateUtils.formatDateSeparator(date),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// Animated message bubble for sending state
class SendingMessageBubble extends StatefulWidget {
  final String message;
  final bool isMyMessage;

  const SendingMessageBubble({
    super.key,
    required this.message,
    this.isMyMessage = true,
  });

  @override
  State<SendingMessageBubble> createState() => _SendingMessageBubbleState();
}

class _SendingMessageBubbleState extends State<SendingMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(
      begin: 0.3,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            widget.isMyMessage
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _opacityAnimation,
            child: MessageBubbleGradient(
              isMyMessage: widget.isMyMessage,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.message,
                        style: AppThemes.messageTextStyle.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            builder: (context, child) {
              return Opacity(opacity: _opacityAnimation.value, child: child);
            },
          ),
        ],
      ),
    );
  }
}