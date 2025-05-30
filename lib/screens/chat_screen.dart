import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/services/chat_service.dart';
import '../core/services/storage_service.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/chat/status_indicator.dart';
import '../widgets/common/gradient_background.dart';
import '../widgets/common/animated_heart.dart';
import '../widgets/common/loading_heart.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/message_input.dart';
import '../widgets/chat/typing_indicator.dart';
import 'profile_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();

  late AnimationController _fabController;
  late AnimationController _heartController;

  bool _isTyping = false;
  bool _showFloatingHearts = false;

  @override
  void initState() {
    super.initState();

    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _messageController.addListener(_onMessageChanged);
    _messageFocusNode.addListener(_onFocusChanged);

    // Auto-scroll when new messages come
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animated: false);
    });
     // Add this to check if chat is properly initialized
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    print('🔍 ChatScreen initializing...');
    final chatService = ChatService.instance;
    final canInit = await chatService.canInitializeChat();
    print('📋 Can initialize chat: $canInit');
    
    if (canInit) {
      final chatId = await chatService.initializeChatWithFallback();
      print('📋 Initialized chat ID: $chatId');
    }
    
    _scrollToBottom(animated: false);
  });

  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _fabController.dispose();
    _heartController.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    final isCurrentlyTyping = _messageController.text.trim().isNotEmpty;

    if (isCurrentlyTyping != _isTyping) {
      setState(() => _isTyping = isCurrentlyTyping);
      ref
          .read(chatControllerProvider.notifier)
          .updateTypingStatus(isCurrentlyTyping);

      if (isCurrentlyTyping) {
        _fabController.forward();
      } else {
        _fabController.reverse();
      }
    }
  }

  void _onFocusChanged() {
    if (_messageFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 500), () {
        ref.read(chatControllerProvider.notifier).markMessagesAsRead();
      });
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (_scrollController.hasClients) {
      if (animated) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // Clear input immediately for better UX
    _messageController.clear();
    setState(() => _isTyping = false);
    _fabController.reverse();

    // Show floating hearts animation
    setState(() => _showFloatingHearts = true);
    _heartController.forward().then((_) {
      _heartController.reset();
      setState(() => _showFloatingHearts = false);
    });

    // Send message with better error handling
    try {
      await ref.read(chatControllerProvider.notifier).sendMessage(message);

      // Scroll to bottom after sending
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom();
      });

      // Haptic feedback
      HapticFeedback.lightImpact();
    } catch (e) {
      _showErrorSnackBar('Failed to send message: $e');
    }
  }

  Future<void> _sendImage() async {
    try {
      final source = await _showImagePickerDialog();
      if (source == null) return;

      XFile? imageFile;
      if (source == ImageSource.camera) {
        imageFile = await StorageService.instance.pickImageFromCamera();
      } else {
        imageFile = await StorageService.instance.pickImageFromGallery();
      }

      if (imageFile == null) return;

      _showUploadingDialog();

      final chatState = ref.read(chatControllerProvider);
      if (chatState is! ChatLoaded) return;

      final imageUrl = await StorageService.instance.uploadChatImage(
        imageFile: imageFile,
        chatId: chatState.chatId,
      );

      Navigator.of(context).pop(); // Dismiss uploading dialog

      if (imageUrl != null) {
        await ref
            .read(chatControllerProvider.notifier)
            .sendImageMessage(imageUrl);
        _scrollToBottom();
        HapticFeedback.lightImpact();
      } else {
        _showErrorSnackBar('Failed to upload image');
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showErrorSnackBar('Error sending image: $e');
    }
  }

  Future<ImageSource?> _showImagePickerDialog() async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Select Image Source',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _ImageSourceOption(
                        icon: Icons.camera_alt,
                        label: AppStrings.camera,
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ImageSourceOption(
                        icon: Icons.photo_library,
                        label: AppStrings.gallery,
                        onTap:
                            () => Navigator.pop(context, ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }

  void _showUploadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const Dialog(
            backgroundColor: Colors.transparent,
            child: Center(child: UploadingImageHeart()),
          ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partnerUser = ref.watch(partnerUserStreamProvider);
    final chatState = ref.watch(chatControllerProvider);
    final currentUserId =
        ref.watch(authControllerProvider.notifier).currentUserId;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Much cleaner background
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade400, Colors.pink.shade300],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  partnerUser.when(
                    data:
                        (partner) =>
                            partner != null
                                ? Expanded(
                                  child: Row(
                                    children: [
                                      Stack(
                                        children: [
                                          CircleAvatar(
                                            radius: 20,
                                            backgroundColor: Colors.white,
                                            backgroundImage:
                                                partner.photoURL != null
                                                    ? NetworkImage(
                                                      partner.photoURL!,
                                                    )
                                                    : null,
                                            child:
                                                partner.photoURL == null
                                                    ? Text(
                                                      partner.initials,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            Colors.purple[600],
                                                      ),
                                                    )
                                                    : null,
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color:
                                                    partner.isOnline
                                                        ? Colors.green
                                                        : Colors.grey,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              partner.displayName,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                            ref
                                                .watch(
                                                  typingStatusProvider(
                                                    partner.uid,
                                                  ),
                                                )
                                                .maybeWhen(
                                                  data:
                                                      (isTyping) =>
                                                          isTyping
                                                              ? const Text(
                                                                'typing...',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color:
                                                                      Colors
                                                                          .white70,
                                                                  fontStyle:
                                                                      FontStyle
                                                                          .italic,
                                                                ),
                                                              )
                                                              : Text(
                                                                partner.isOnline
                                                                    ? 'Online'
                                                                    : partner
                                                                        .lastSeenText,
                                                                style: const TextStyle(
                                                                  fontSize: 12,
                                                                  color:
                                                                      Colors
                                                                          .white70,
                                                                ),
                                                              ),
                                                  orElse:
                                                      () => Text(
                                                        partner.isOnline
                                                            ? 'Online'
                                                            : partner
                                                                .lastSeenText,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                : Expanded(
                                  child: Text(
                                    AppStrings.chatTitle,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                    loading:
                        () => const Expanded(
                          child: Text(
                            'Loading...',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    error:
                        (_, __) => Expanded(
                          child: Text(
                            AppStrings.chatTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey[50]!, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            // Messages list
            Expanded(
              child:
                  chatState is ChatInitial || chatState is ChatLoading
                      ? const Center(child: ChatLoadingHeart())
                      : chatState is ChatLoaded
                      ? _buildMessagesList(chatState.messages, currentUserId)
                      : chatState is ChatSendingMessage
                      ? _buildMessagesList(chatState.messages, currentUserId)
                      : chatState is ChatError
                      ? _buildErrorState(chatState.message)
                      : const SizedBox.shrink(),
            ),

            // Typing indicator
            partnerUser.when(
              data:
                  (partner) =>
                      partner != null
                          ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ref
                                .watch(typingStatusProvider(partner.uid))
                                .maybeWhen(
                                  data:
                                      (isTyping) => AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        height: isTyping ? 40 : 0,
                                        child:
                                            isTyping
                                                ? Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[100],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.grey[300]!,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '${partner.displayName} is typing',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Colors.grey[600],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          valueColor:
                                                              AlwaysStoppedAnimation(
                                                                Colors
                                                                    .purple[400],
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                                : const SizedBox.shrink(),
                                      ),
                                  orElse: () => const SizedBox.shrink(),
                                ),
                          )
                          : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // Message input
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: MessageInput(
                controller: _messageController,
                focusNode: _messageFocusNode,
                onSendPressed: _sendMessage,
                onImagePressed: _sendImage,
                isEnabled: chatState is! ChatError,
              ),
            ),
          ],
        ),
      ),
      // Floating hearts animation overlay
      floatingActionButton:
          _showFloatingHearts
              ? FloatingHeartsWidget(isActive: _showFloatingHearts)
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              ref.read(chatControllerProvider.notifier).retry();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[400],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(
    List<MessageModel> messages,
    String? currentUserId,
  ) {
    if (messages.isEmpty) {
      return _buildEmptyState();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo is ScrollUpdateNotification) {
          // Auto-scroll logic can be added here
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          final isMyMessage = message.isFromCurrentUser(currentUserId ?? '');
          final showAvatar =
              index == 0 || messages[index - 1].senderId != message.senderId;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: MessageBubble(
              message: message,
              isMyMessage: isMyMessage,
              showAvatar: showAvatar,
              onLongPress: () => _showMessageOptions(message),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade300, Colors.pink.shade300],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(Icons.favorite, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 32),
            Text(
              '💕 Start Your Love Story 💕',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Send your first message to begin\nyour beautiful conversation together!',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.purple.shade200, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tips_and_updates,
                    color: Colors.purple[400],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Type something sweet below ↓',
                    style: TextStyle(
                      color: Colors.purple[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(MessageModel message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.message));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message copied')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteMessage(message);
                  },
                ),
              ],
            ),
          ),
    );
  }

  void _confirmDeleteMessage(MessageModel message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Message'),
            content: const Text(
              'Are you sure you want to delete this message?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ref
                      .read(chatControllerProvider.notifier)
                      .deleteMessage(message.id);
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}

class _ImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ImageSourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade400, Colors.pink.shade300],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.white),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
