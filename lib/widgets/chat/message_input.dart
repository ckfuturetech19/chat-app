import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSendPressed;
  final VoidCallback? onImagePressed;
  final bool isEnabled;
  final String? hint;

  const MessageInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSendPressed,
    this.onImagePressed,
    this.isEnabled = true,
    this.hint,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput>
    with TickerProviderStateMixin {
  late AnimationController _sendButtonController;
  late AnimationController _heartController;
  late AnimationController _pulseController;
  
  late Animation<double> _sendButtonAnimation;
  late Animation<double> _heartAnimation;
  late Animation<double> _pulseAnimation;
  
  bool _hasText = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    
    _sendButtonController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _sendButtonAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _sendButtonController,
      curve: Curves.elasticOut,
    ));
    
    _heartAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _heartController,
      curve: Curves.easeInOut,
    ));
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    // Listen to text changes
    widget.controller.addListener(_onTextChanged);
    
    // Listen to focus changes
    widget.focusNode.addListener(_onFocusChanged);
    
    // Start pulse animation when focused
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _sendButtonController.dispose();
    _heartController.dispose();
    _pulseController.dispose();
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
      
      if (hasText) {
        _sendButtonController.forward();
        _heartController.repeat(reverse: true);
      } else {
        _sendButtonController.reverse();
        _heartController.stop();
        _heartController.reset();
      }
    }
  }

  void _onFocusChanged() {
    setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  void _handleSendPressed() {
    if (_hasText && widget.isEnabled) {
      // Trigger send animation
      _sendButtonController.forward().then((_) {
        _sendButtonController.reverse();
      });
      
      // Haptic feedback
      HapticFeedback.lightImpact();
      
      // Call the callback
      widget.onSendPressed();
    }
  }

 @override
Widget build(BuildContext context) {
  return Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), // Reduced padding
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.95),
      boxShadow: [
        BoxShadow(
          color: AppColors.primaryDeepRose.withOpacity(0.1),
          blurRadius: 20,
          offset: const Offset(0, -5),
        ),
      ],
    ),
    child: SafeArea(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isFocused ? _pulseAnimation.value : 1.0,
            child: _buildInputRow(),
          );
        },
      ),
    ),
  );
}

 Widget _buildInputRow() {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      // Image button
      if (widget.onImagePressed != null)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          child: _buildImageButton(),
        ),
      
      if (widget.onImagePressed != null)
        const SizedBox(width: 8), // Reduced spacing
      
      // Text input field
      Expanded(
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 42, // Reduced height
            maxHeight: 100,
          ),
          child: _buildTextField(),
        ),
      ),
      
      const SizedBox(width: 8), // Reduced spacing
      
      // Send button
      Container(
        margin: const EdgeInsets.only(bottom: 4),
        child: _buildSendButton(),
      ),
    ],
  );
}

  Widget _buildImageButton() {
    return GestureDetector(
      onTap: widget.isEnabled ? widget.onImagePressed : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: AppColors.buttonGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDeepRose.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.image,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            AppColors.neutralCream.withOpacity(0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: _isFocused 
              ? AppColors.primaryDeepRose.withOpacity(0.5)
              : AppColors.primaryRose.withOpacity(0.3),
          width: _isFocused ? 2 : 1,
        ),
        boxShadow: [
          if (_isFocused)
            BoxShadow(
              color: AppColors.primaryDeepRose.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        enabled: widget.isEnabled,
        maxLines: 4,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: widget.hint ?? AppStrings.typeMessage,
          hintStyle: TextStyle(
            color: AppColors.textLight.withOpacity(0.7),
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          suffixIcon: _hasText 
              ? _buildFloatingHeartIcon()
              : null,
        ),
        style: const TextStyle(
          fontSize: 16,
          color: AppColors.textPrimary,
        ),
        onSubmitted: (_) => _handleSendPressed(),
      ),
    );
  }

  Widget _buildFloatingHeartIcon() {
    return AnimatedBuilder(
      animation: _heartAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _heartAnimation.value,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.favorite,
              color: AppColors.primaryDeepRose.withOpacity(0.6),
              size: 16,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSendButton() {
    return AnimatedBuilder(
      animation: _sendButtonAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.8 + (_sendButtonAnimation.value * 0.4),
          child: GestureDetector(
            onTap: _handleSendPressed,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: _hasText && widget.isEnabled
                    ? AppColors.buttonGradient
                    : LinearGradient(
                        colors: [
                          AppColors.textLight.withOpacity(0.3),
                          AppColors.textLight.withOpacity(0.2),
                        ],
                      ),
                shape: BoxShape.circle,
                boxShadow: _hasText && widget.isEnabled
                    ? [
                        BoxShadow(
                          color: AppColors.primaryDeepRose.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Heart background
                  if (_hasText)
                    AnimatedBuilder(
                      animation: _heartController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _heartController.value * 2 * math.pi * 0.1,
                          child: Icon(
                            Icons.favorite,
                            color: Colors.white.withOpacity(0.3),
                            size: 20,
                          ),
                        );
                      },
                    ),
                  
                  // Send icon
                  Icon(
                    Icons.send,
                    color: _hasText && widget.isEnabled
                        ? Colors.white
                        : AppColors.textLight.withOpacity(0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Emoji picker button (optional enhancement)
class EmojiPickerButton extends StatefulWidget {
  final Function(String) onEmojiSelected;

  const EmojiPickerButton({
    super.key,
    required this.onEmojiSelected,
  });

  @override
  State<EmojiPickerButton> createState() => _EmojiPickerButtonState();
}

class _EmojiPickerButtonState extends State<EmojiPickerButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showEmojiPicker = false;

  // Popular romantic emojis
  final List<String> _romanticEmojis = [
    '❤️', '💕', '💖', '💗', '💙', '💚', '💛', '🧡', '💜', '🖤',
    '💝', '💘', '💌', '💟', '💍', '💐', '🌹', '🌺', '🌸', '🌻',
    '😍', '🥰', '😘', '😗', '😙', '😚', '🤗', '🤩', '😊', '☺️',
    '✨', '⭐', '🌟', '💫', '🌙', '☀️', '🌈', '🦋', '🕊️', '💭',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
    
    if (_showEmojiPicker) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Emoji picker panel
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _showEmojiPicker ? 200 : 0,
          child: _showEmojiPicker ? _buildEmojiPicker() : null,
        ),
        
        // Emoji button
        GestureDetector(
          onTap: _toggleEmojiPicker,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: _showEmojiPicker
                  ? AppColors.buttonGradient
                  : LinearGradient(
                      colors: [
                        AppColors.primaryRose.withOpacity(0.3),
                        AppColors.primaryRose.withOpacity(0.2),
                      ],
                    ),
              shape: BoxShape.circle,
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _controller.value * math.pi,
                  child: Icon(
                    _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions,
                    color: _showEmojiPicker ? Colors.white : AppColors.primaryDeepRose,
                    size: 20,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiPicker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDeepRose.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          childAspectRatio: 1,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _romanticEmojis.length,
        itemBuilder: (context, index) {
          final emoji = _romanticEmojis[index];
          return GestureDetector(
            onTap: () {
              widget.onEmojiSelected(emoji);
              _toggleEmojiPicker();
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: AppColors.primaryRose.withOpacity(0.1),
              ),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
} 