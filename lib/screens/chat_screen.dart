import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:onlyus/core/services/firebase_service.dart';
import 'package:onlyus/core/services/notification_service.dart';

import '../core/constants/app_strings.dart';
import '../core/services/chat_service.dart';
import '../core/services/storage_service.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/common/animated_heart.dart';
import '../widgets/common/loading_heart.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/message_input.dart';
import 'profile_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeChatWithNotifications();
    });

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
    WidgetsBinding.instance.removeObserver(this);

    _handleChatExit();

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

      // Use enhanced typing status
      _updateTypingStatusWithDebounce(isCurrentlyTyping);

      if (isCurrentlyTyping) {
        _fabController.forward();
      } else {
        _fabController.reverse();
      }
    }
  }

  // NEW: Debounced typing status update
  Timer? _typingDebounceTimer;

  void _updateTypingStatusWithDebounce(bool isTyping) {
    // Cancel previous timer
    _typingDebounceTimer?.cancel();

    if (isTyping) {
      // Immediately show typing
      ChatService.instance.updateTypingStatusEnhanced(true);

      // Set timer to clear typing status if no more input
      _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _messageController.text.trim().isEmpty) {
          ChatService.instance.updateTypingStatusEnhanced(false);
          setState(() => _isTyping = false);
          _fabController.reverse();
        }
      });
    } else {
      // Delay clearing typing status briefly
      _typingDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        ChatService.instance.updateTypingStatusEnhanced(false);
      });
    }
  }

  Future<void> _testNotificationSetup() async {
    try {
      print('🧪 Testing notification setup...');

      // Debug user and player ID mapping
      await NotificationService.debugUserPlayerIdMapping();

      // Debug chat service notification setup
      await ChatService.instance.debugNotificationSetup();

      // Test notification creation (without actually sending)
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        final partnerInfo = await ChatService.instance.getPartnerInfo(
          currentUserId,
        );

        if (partnerInfo != null) {
          print('✅ Notification test setup complete');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Notification setup test complete - check console',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          print('❌ No partner found for notification test');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No partner found for notifications'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error testing notification setup: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification test error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onFocusChanged() {
    if (_messageFocusNode.hasFocus) {
      // User focused on input - mark messages as read after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _messageFocusNode.hasFocus) {
          ref.read(chatControllerProvider.notifier).markMessagesAsRead();

          // Also clear any unread count
          final chatState = ref.read(chatControllerProvider);
          if (chatState is ChatLoaded) {
            final currentUserId =
                ref.read(authControllerProvider.notifier).currentUserId;
            if (currentUserId != null) {
              NotificationService.clearUnreadCount(
                currentUserId,
                chatState.chatId,
              );
            }
          }
        }
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

  // NEW: Handle app lifecycle changes within chat
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _handleChatResumed();
        break;
      case AppLifecycleState.paused:
        _handleChatPaused();
        break;
      case AppLifecycleState.inactive:
        // App is temporarily inactive (e.g., notification panel)
        break;
      default:
        break;
    }
  }

  // NEW: Initialize chat with notification integration
  Future<void> _initializeChatWithNotifications() async {
    try {
      print('🔍 ChatScreen: Initializing with notification integration...');

      final chatService = ChatService.instance;
      final canInit = await chatService.canInitializeChat();

      if (canInit) {
        final chatId = await chatService.initializeChatWithFallback();

        if (chatId != null) {
          // Notify chat service that user entered this chat
          await chatService.onChatScreenEntered(chatId);
          print('✅ Chat initialized with notifications: $chatId');
        }
      }

      _scrollToBottom(animated: false);
    } catch (e) {
      print('❌ Error initializing chat with notifications: $e');
    }
  }

  // NEW: Handle chat resumed
  Future<void> _handleChatResumed() async {
    try {
      print('📱 Chat screen resumed');

      final chatState = ref.read(chatControllerProvider);
      if (chatState is ChatLoaded && chatState.chatId.isNotEmpty) {
        // Re-establish active chat
        await ChatService.instance.onChatScreenEntered(chatState.chatId);

        // Mark messages as read
        await ref.read(chatControllerProvider.notifier).markMessagesAsRead();

        // Clear any pending notifications
        await NotificationService.clearAllNotifications();
      }
    } catch (e) {
      print('❌ Error handling chat resumed: $e');
    }
  }

  // NEW: Handle chat paused
  Future<void> _handleChatPaused() async {
    try {
      print('📱 Chat screen paused');

      // Clear typing status
      await ref.read(chatControllerProvider.notifier).updateTypingStatus(false);

      // Notify that user exited chat
      await ChatService.instance.onChatScreenExited();
    } catch (e) {
      print('❌ Error handling chat paused: $e');
    }
  }

  // NEW: Handle chat exit
  Future<void> _handleChatExit() async {
    try {
      print('📱 Chat screen exiting');

      // Clear typing status
      if (mounted) {
        await ref
            .read(chatControllerProvider.notifier)
            .updateTypingStatus(false);
      }

      // Notify chat service
      await ChatService.instance.onChatScreenExited();
    } catch (e) {
      print('❌ Error handling chat exit: $e');
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // Clear input immediately for better UX
    _messageController.clear();
    setState(() => _isTyping = false);
    _fabController.reverse();

    // Clear typing status immediately
    ChatService.instance.updateTypingStatusEnhanced(false);

    // Show floating hearts animation
    setState(() => _showFloatingHearts = true);
    _heartController.forward().then((_) {
      _heartController.reset();
      setState(() => _showFloatingHearts = false);
    });

    try {
      // Use enhanced message sending
      final success = await ChatService.instance.sendTextMessageEnhanced(
        message: message,
      );

      if (success) {
        // Scroll to bottom after sending
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollToBottom();
        });

        // Haptic feedback
        HapticFeedback.lightImpact();

        print('✅ Message sent with smart notifications');
      } else {
        throw Exception('Failed to send message');
      }
    } catch (e) {
      print('❌ Error sending message: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to send message: $e');
      }
    }
  }

  // NEW: Show notification debug info (for development)
  Future<void> _showNotificationDebugInfo() async {
    if (!mounted) return;

    try {
      final stats = await ChatService.instance.getNotificationStats();
      final settings = await NotificationService.getNotificationSettings();

      if (mounted) {
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Notification Debug Info'),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Notification Stats:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total Unread: ${stats['totalUnreadMessages'] ?? 0}',
                      ),
                      Text('Active Chat: ${stats['activeChatId'] ?? 'None'}'),
                      Text(
                        'App in Background: ${stats['isAppInBackground'] ?? false}',
                      ),
                      Text(
                        'Player ID: ${stats['oneSignalPlayerId'] ?? 'None'}',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'OneSignal Settings:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Permission: ${settings['permission'] ?? false}'),
                      Text(
                        'SDK Version: ${settings['sdkVersion'] ?? 'Unknown'}',
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await NotificationService.debugNotificationSetup();
                      if (mounted) {
                        _showErrorSnackBar(
                          'Debug test completed - check console',
                        );
                      }
                    },
                    child: const Text('Test'),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      print('❌ Error showing debug info: $e');
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

      // Check if widget is still mounted before popping dialog
      if (mounted) {
        Navigator.of(context).pop(); // Dismiss uploading dialog
      }

      if (imageUrl != null) {
        await ref
            .read(chatControllerProvider.notifier)
            .sendImageMessage(imageUrl);
        _scrollToBottom();
        HapticFeedback.lightImpact();
      } else {
        // Check if widget is still mounted before showing SnackBar
        if (mounted) {
          _showErrorSnackBar('Failed to upload image');
        }
      }
    } catch (e) {
      // Check if widget is still mounted before popping dialog and showing SnackBar
      if (mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar('Error sending image: $e');
      }
    }
  }

  Future<ImageSource?> _showImagePickerDialog() async {
    if (!mounted) return null;

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
    if (!mounted) return;

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
    // Double-check if widget is mounted and context is valid
    if (!mounted || !context.mounted) return;

    // Use a post-frame callback to ensure the widget tree is stable
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(
              16,
            ), // Add margin to prevent off-screen rendering
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // FIXED: Use real-time providers for better presence updates
    final partnerUser = ref.watch(realTimePartnerUserProvider);

    // Keep current user for other purposes (but don't show in app bar)
    final currentUser = ref.watch(realTimeCurrentUserProvider);

    final chatState = ref.watch(chatControllerProvider);
    final currentUserId =
        ref.watch(authControllerProvider.notifier).currentUserId;

    return Scaffold(
      backgroundColor: Colors.grey[50],
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
                  // IconButton(
                  //   icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  //   onPressed: () => Navigator.pop(context),
                  // ),
                  _buildAppBarUserInfo(partnerUser, currentUser),
                  IconButton(
                    icon: const Icon(Icons.person, color: Colors.white),
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

            // Typing indicator (shows partner's typing status)
            _buildTypingIndicator(partnerUser),

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
      floatingActionButton:
          _showFloatingHearts
              ? FloatingHeartsWidget(isActive: _showFloatingHearts)
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // Updated _buildAppBarUserInfo method to ALWAYS show partner info

  Widget _buildAppBarUserInfo(
    AsyncValue<UserModel?> partnerUser,
    AsyncValue<UserModel?> currentUser,
  ) {
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: partnerUser.when(
              data: (partner) {
                if (partner != null) {
                  return _buildUserRow(
                    user: partner,
                    showTypingIndicator: true,
                  );
                } else {
                  return _buildConnectingState();
                }
              },
              loading: () => _buildPartnerLoadingState(),
              error: (error, stack) {
                print('❌ Error loading partner: $error');
                return _buildConnectionErrorState();
              },
            ),
          ),

          // NEW: Notification status indicator (for debugging)
          if (kDebugMode) // Only show in debug mode
            IconButton(
              icon: Icon(
                Icons.notifications,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              onPressed: () async {
                final success =
                    await NotificationService.testNotificationToSelf();
                print('Self test result: $success');
              },
              tooltip: 'Notification Debug',
            ),
          if (kDebugMode) // Only show in debug mode
            IconButton(
              icon: Icon(
                Icons.notifications,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              onPressed: () async {
                final success =
                    await NotificationService.testNotificationToPartner();
                print('Partner test result: $success');
              },
              tooltip: 'Notification Debug',
            ),
          if (kDebugMode) // Only show in debug mode
            IconButton(
              icon: Icon(
                Icons.notifications,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              onPressed: () async {
                final results =
                    await NotificationService.runComprehensiveNotificationTest();
                print('Full test results: ${results['success_rate']}');
              },
              tooltip: 'Notification Debug',
            ),
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report, color: Colors.white),
              onPressed: _testNotificationSetup,
              tooltip: 'Test Notifications',
            ),
        ],
      ),
    );
  }

  // NEW: Enhanced connection error state with notification retry
  Widget _buildConnectionErrorState() {
    return GestureDetector(
      onTap: () async {
        print('🔄 Retrying connection with notification reset...');

        // Reset notification state
        final currentUserId =
            ref.read(authControllerProvider.notifier).currentUserId;
        if (currentUserId != null) {
          await NotificationService.setUserActiveChatId(currentUserId, null);
          await NotificationService.updateUserPlayerId();
        }

        // Refresh providers
        ref.invalidate(partnerUserStreamProvider);
        ref.invalidate(quickPartnerProvider);

        // Reinitialize chat
        try {
          await _initializeChatWithNotifications();
        } catch (e) {
          print('❌ Error retrying with notifications: $e');
        }
      },
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.refresh, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Connection issue',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Tap to retry with notifications',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Updated _buildUserRow to show partner-specific information
  Widget _buildUserRow({
    required UserModel user,
    bool showTypingIndicator = false,
  }) {
    return Row(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              backgroundImage:
                  user.photoURL != null && user.photoURL!.isNotEmpty
                      ? NetworkImage(user.photoURL!)
                      : null,
              child:
                  user.photoURL == null || user.photoURL!.isEmpty
                      ? Text(
                        user.initials,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple[600],
                        ),
                      )
                      : null,
            ),
            // FIXED: Online status indicator with real-time presence color
            Positioned(
              bottom: 0,
              right: 0,
              child: Consumer(
                builder: (context, ref, child) {
                  final presenceData =
                      ref.watch(livePresenceStatusProvider(user.uid)).value;
                  Color statusColor = const Color(0xFF9E9E9E); // Default gray

                  if (presenceData != null) {
                    final isOnline = presenceData['isOnline'] as bool? ?? false;
                    final lastSeen = presenceData['lastSeen'] as DateTime?;

                    if (isOnline) {
                      statusColor = const Color(0xFF4CAF50); // Green for online
                    } else if (lastSeen != null) {
                      final difference = DateTime.now().difference(lastSeen);
                      if (difference.inMinutes <= 2) {
                        statusColor = const Color(
                          0xFFFF9800,
                        ); // Orange for recently active
                      }
                    }
                  } else {
                    // Fallback to user model color
                    statusColor = user.onlineStatusColor;
                  }

                  return Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                user.displayName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              _buildPartnerStatusText(user, showTypingIndicator),
            ],
          ),
        ),
      ],
    );
  }

  // FIXED: Add Consumer import at the top of your ChatScreen file
  // import 'package:flutter_riverpod/flutter_riverpod.dart'; // Make sure this is imported

  // FIXED: Updated status text specifically for partner in chat screen
  Widget _buildPartnerStatusText(UserModel partner, bool showTypingIndicator) {
    if (showTypingIndicator) {
      return ref
          .watch(enhancedTypingStatusProvider(partner.uid))
          .maybeWhen(
            data:
                (isTyping) =>
                    isTyping
                        ? const Text(
                          'typing...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                        : Consumer(
                          builder: (context, ref, child) {
                            final quickStatus = ref.watch(
                              userQuickStatusProvider(partner),
                            );
                            return Text(
                              quickStatus,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            );
                          },
                        ),
            orElse:
                () => Consumer(
                  builder: (context, ref, child) {
                    final quickStatus = ref.watch(
                      userQuickStatusProvider(partner),
                    );
                    return Text(
                      quickStatus,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    );
                  },
                ),
          );
    }

    return Consumer(
      builder: (context, ref, child) {
        final quickStatus = ref.watch(userQuickStatusProvider(partner));
        return Text(
          quickStatus,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        );
      },
    );
  }

  // New method for showing partner loading state
  Widget _buildPartnerLoadingState() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Connecting to your love...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Please wait',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // New method for showing connecting state (no partner yet)
  Widget _buildConnectingState() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade300, Colors.pink.shade300],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
          ),
          child: const Icon(Icons.person_search, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Finding your partner...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Connecting hearts',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // FIXED: Typing indicator with real-time partner status
  Widget _buildTypingIndicator(AsyncValue<UserModel?> partnerUser) {
    return partnerUser.when(
      data:
          (partner) =>
              partner != null
                  ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ref
                        .watch(enhancedTypingStatusProvider(partner.uid))
                        .maybeWhen(
                          data:
                              (isTyping) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: isTyping ? 40 : 0,
                                child:
                                    isTyping
                                        ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Partner avatar with real-time status
                                              Stack(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 8,
                                                    backgroundColor:
                                                        Colors.purple[100],
                                                    backgroundImage:
                                                        partner.photoURL !=
                                                                    null &&
                                                                partner
                                                                    .photoURL!
                                                                    .isNotEmpty
                                                            ? NetworkImage(
                                                              partner.photoURL!,
                                                            )
                                                            : null,
                                                    child:
                                                        partner.photoURL ==
                                                                    null ||
                                                                partner
                                                                    .photoURL!
                                                                    .isEmpty
                                                            ? Text(
                                                              partner.initials,
                                                              style: TextStyle(
                                                                fontSize: 8,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    Colors
                                                                        .purple[600],
                                                              ),
                                                            )
                                                            : null,
                                                  ),
                                                  // Real-time status dot
                                                  Positioned(
                                                    bottom: 0,
                                                    right: 0,
                                                    child: Consumer(
                                                      builder: (
                                                        context,
                                                        ref,
                                                        child,
                                                      ) {
                                                        final presenceData =
                                                            ref
                                                                .watch(
                                                                  livePresenceStatusProvider(
                                                                    partner.uid,
                                                                  ),
                                                                )
                                                                .value;

                                                        Color statusColor =
                                                            Colors.grey;
                                                        if (presenceData !=
                                                            null) {
                                                          final isOnline =
                                                              presenceData['isOnline']
                                                                  as bool? ??
                                                              false;
                                                          statusColor =
                                                              isOnline
                                                                  ? Colors.green
                                                                  : Colors.grey;
                                                        }

                                                        return Container(
                                                          width: 6,
                                                          height: 6,
                                                          decoration: BoxDecoration(
                                                            color: statusColor,
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                              color:
                                                                  Colors.white,
                                                              width: 1,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${partner.displayName} is typing',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 1.5,
                                                  valueColor:
                                                      AlwaysStoppedAnimation(
                                                        Colors.purple[400],
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
    if (!mounted) return;

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
                    // Check if mounted before showing SnackBar
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message copied'),
                          behavior: SnackBarBehavior.floating,
                          margin: EdgeInsets.all(16),
                        ),
                      );
                    }
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
    if (!mounted) return;

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
