import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:onlyus/core/services/firebase_service.dart';
import 'package:onlyus/core/services/notification_service.dart';
import 'package:onlyus/screens/favorites_screen.dart';

import '../core/constants/app_strings.dart';
import '../core/services/chat_service.dart';
import '../core/services/pressence_service.dart';
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
import '../widgets/chat/typing_indicator.dart'; // Updated romantic typing indicator
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
  late AnimationController _favoriteController;
  // ADD these properties
  Timer? _messageStatusTimer;
  Timer? _presenceCheckTimer;

  bool _isTyping = false;
  bool _showFloatingHearts = false;
  bool _useFloatingHeartsIndicator =
      false; // Toggle between typing indicator styles
  bool _isChatFavorited = false;

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

    // ADD THIS
    _favoriteController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    // Set user online when entering chat
    PresenceService.instance.setUserOnline();

    _messageController.addListener(_onMessageChanged);
    _messageFocusNode.addListener(_onFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeChatWithNotifications();
      _checkIfChatIsFavorited();
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
    // Start periodic message status checks
    _startMessageStatusTracking();

    // Start presence checking for partner
    _startPresenceChecking();
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
    _favoriteController.dispose();
    _messageStatusTimer?.cancel();
    _presenceCheckTimer?.cancel();
    super.dispose();
  }

  void _startMessageStatusTracking() {
    _messageStatusTimer?.cancel();

    // Check message statuses every 5 seconds (reduced frequency)
    _messageStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final chatState = ref.read(chatControllerProvider);
      if (chatState is ChatLoaded) {
        // FIXED: Only update read status for received messages, not sent messages
        await _markReceivedMessagesAsRead();
      }
    });
  }

  // Add these methods to your _ChatScreenState class

  Future<void> _checkIfChatIsFavorited() async {
    try {
      final chatState = ref.read(chatControllerProvider);
      if (chatState is ChatLoaded) {
        final currentUserId = FirebaseService.currentUserId;
        if (currentUserId != null) {
          final userDoc =
              await FirebaseService.usersCollection.doc(currentUserId).get();

          final favoriteChats = List<String>.from(
            userDoc.data()?['favoriteChats'] ?? [],
          );

          setState(() {
            _isChatFavorited = favoriteChats.contains(chatState.chatId);
          });

          if (_isChatFavorited) {
            _favoriteController.forward();
          }
        }
      }
    } catch (e) {
      print('❌ Error checking if chat is favorited: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final chatState = ref.read(chatControllerProvider);
      if (chatState is! ChatLoaded) return;

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return;

      final userRef = FirebaseService.usersCollection.doc(currentUserId);
      final userDoc = await userRef.get();

      List<String> favoriteChats = List<String>.from(
        userDoc.data()?['favoriteChats'] ?? [],
      );

      if (_isChatFavorited) {
        // Remove from favorites
        favoriteChats.remove(chatState.chatId);
        _favoriteController.reverse();

        if (mounted) {
          _showSnackBar('💔 Removed from favorites', Colors.orange);
        }
      } else {
        // Add to favorites
        favoriteChats.add(chatState.chatId);
        _favoriteController.forward();

        if (mounted) {
          _showSnackBar('💖 Added to favorites', Colors.pink);
        }
      }

      await userRef.update({'favoriteChats': favoriteChats});

      setState(() {
        _isChatFavorited = !_isChatFavorited;
      });

      HapticFeedback.lightImpact();
    } catch (e) {
      print('❌ Error toggling favorite: $e');
      if (mounted) {
        _showSnackBar('❌ Failed to update favorites', Colors.red);
      }
    }
  }

  void _showFavorites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FavoritesScreen()),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted || !context.mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _markReceivedMessagesAsRead() async {
    try {
      final currentUserId =
          ref.read(authControllerProvider.notifier).currentUserId;
      if (currentUserId == null) return;

      final chatState = ref.read(chatControllerProvider);
      if (chatState is! ChatLoaded) return;

      // Get current messages
      final messages = chatState.messages;

      // Count unread messages that were NOT sent by current user
      int unreadReceivedCount = 0;
      for (final message in messages) {
        if (message.senderId != currentUserId && !message.isRead) {
          unreadReceivedCount++;
        }
      }

      print('📊 Found $unreadReceivedCount unread received messages');

      // Only mark as read if there are actually unread received messages
      if (unreadReceivedCount > 0) {
        print(
          '📖 Marking received messages as read for chat: ${chatState.chatId}',
        );
        await ChatService.instance.markMessagesAsReadEnhanced(
          chatId: chatState.chatId,
        );

        // Clear unread count
        await NotificationService.clearUnreadCount(
          currentUserId,
          chatState.chatId,
        );
      } else {
        // Don't spam logs when there are no unread messages
        // print('✅ No unread received messages to mark');
      }
    } catch (e) {
      print('❌ Error marking received messages as read: $e');
    }
  }

  void _startPresenceChecking() {
    _presenceCheckTimer?.cancel();

    // Check partner presence every 5 seconds
    _presenceCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return;

      final partnerInfo = await ChatService.instance.getPartnerInfo(
        currentUserId,
      );
      if (partnerInfo != null) {
        final partnerId = partnerInfo['partnerId'] as String;

        // Force refresh partner's presence
        final isOnline = await PresenceService.instance.isUserOnline(partnerId);
        print('👥 Partner presence check: ${isOnline ? "Online" : "Offline"}');
      }
    });
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

  // Enhanced debounced typing status update
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

  void _onFocusChanged() {
    if (_messageFocusNode.hasFocus) {
      // User focused on input - only mark RECEIVED messages as read after delay
      Future.delayed(const Duration(milliseconds: 1000), () async {
        if (mounted && _messageFocusNode.hasFocus) {
          final currentUserId =
              ref.read(authControllerProvider.notifier).currentUserId;
          if (currentUserId == null) return;

          // FIXED: Only mark received messages as read
          await _markReceivedMessagesAsRead();
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

  // Handle app lifecycle changes within chat
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App is active
        PresenceService.instance.setUserOnline();
        NotificationService.setAppForegroundState(true);
        _handleChatResumed();
        break;
      case AppLifecycleState.paused:
        // App is in background
        PresenceService.instance.setUserOffline();
        NotificationService.setAppForegroundState(false);
        _handleChatPaused();
        break;
      case AppLifecycleState.inactive:
        // App is inactive (transitioning)
        break;
      case AppLifecycleState.detached:
        // App is detached
        PresenceService.instance.setUserOffline();
        break;
      case AppLifecycleState.hidden:
        // App is hidden
        PresenceService.instance.setUserOffline();
        break;
    }
  }

  // Initialize chat with notification integration
  Future<void> _initializeChatWithNotifications() async {
    try {
      print('🔍 ChatScreen: Initializing with notification integration...');

      final chatService = ChatService.instance;
      final canInit = await chatService.canInitializeChat();

      if (canInit) {
        final chatId = await chatService.initializeChatWithFallback();

        if (chatId != null) {
          // Set current user as active in this chat WITHOUT marking messages as read
          final currentUserId = FirebaseService.currentUserId;
          if (currentUserId != null) {
            await FirebaseService.usersCollection.doc(currentUserId).update({
              'activeChatId': chatId,
              'isInChat': true,
              'lastActiveInChat': FieldValue.serverTimestamp(),
            });

            // Set in notification service
            await NotificationService.setUserActiveChatId(
              currentUserId,
              chatId,
            );
          }

          print('✅ Chat initialized with notifications: $chatId');
        }
      }

      _scrollToBottom(animated: false);
    } catch (e) {
      print('❌ Error initializing chat with notifications: $e');
    }
  }

  // Handle chat resumed
  Future<void> _handleChatResumed() async {
    try {
      print('📱 Chat screen resumed');

      final chatState = ref.read(chatControllerProvider);
      if (chatState is ChatLoaded && chatState.chatId.isNotEmpty) {
        // Re-establish active chat
        await ChatService.instance.onChatScreenEntered(chatState.chatId);

        // FIXED: Don't automatically mark messages as read on resume
        // Only clear notifications, don't mark as read unless user actually reads
        await NotificationService.clearAllNotifications();

        // Update user presence to show they're active
        final currentUserId =
            ref.read(authControllerProvider.notifier).currentUserId;
        if (currentUserId != null) {
          await PresenceService.instance.updateLastSeen();
        }
      }
    } catch (e) {
      print('❌ Error handling chat resumed: $e');
    }
  }

  // Handle chat paused
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

  // Handle chat exit
  Future<void> _handleChatExit() async {
    try {
      print('📱 Chat screen exiting');

      // Clear typing status
      if (mounted) {
        await ref
            .read(chatControllerProvider.notifier)
            .updateTypingStatus(false);
      }

      // Clear active chat
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        await FirebaseService.usersCollection.doc(currentUserId).update({
          'activeChatId': null,
          'isInChat': false,
          'lastLeftChat': FieldValue.serverTimestamp(),
        });
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

    _messageController.clear();
    setState(() => _isTyping = false);
    _fabController.reverse();

    ChatService.instance.updateTypingStatus(false);

    setState(() => _showFloatingHearts = true);
    _heartController.forward().then((_) {
      _heartController.reset();
      setState(() => _showFloatingHearts = false);
    });

    try {
      // Send the message
      await ref.read(chatControllerProvider.notifier).sendMessage(message);

      // Check for instant read receipt if partner is in chat
      Future.delayed(const Duration(milliseconds: 500), () async {
        await ChatService.instance.checkAndUpdateMessageStatuses();
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom();
      });

      HapticFeedback.lightImpact();
    } catch (e) {
      print('❌ Error sending message: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to send message: $e');
      }
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
              gradient: LinearGradient(
                colors: [Colors.purple.shade50, Colors.pink.shade50],
              ),
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
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade300, Colors.pink.shade300],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '💕 Select Image Source',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _RomanticImageSourceOption(
                        icon: Icons.camera_alt,
                        label: AppStrings.camera,
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _RomanticImageSourceOption(
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
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use real-time providers for better presence updates
    final partnerUser = ref.watch(optimizedPartnerUserProvider);
final currentUser = ref.watch(optimizedCurrentUserProvider);
final chatState = ref.watch(cachedChatControllerProvider);
    final currentUserId =
        ref.watch(authControllerProvider.notifier).currentUserId;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70), // Reduced height
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFFCE93D8), const Color(0xFFFF8A95)],
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  _buildRomanticAppBarUserInfo(partnerUser, currentUser),

                  // Enhanced Favorite button
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap:
                          _showFavorites, // Always shows the favorites screen
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.favorite, // Always show filled heart
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  // Typing indicator style toggle (debug mode only)
                  if (kDebugMode)
                    IconButton(
                      icon: Icon(
                        _useFloatingHeartsIndicator
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _useFloatingHeartsIndicator =
                              !_useFloatingHeartsIndicator;
                        });
                      },
                      tooltip: 'Toggle Typing Style',
                    ),

                  // Profile button
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ProfileScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
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
                _buildCachedMessagesList(chatState, currentUserId),
            ),

            // Romantic Typing indicator
            _buildRomanticTypingIndicator(partnerUser),

            // Message input
            // Message input
            Container(
              padding: const EdgeInsets.fromLTRB(
                12,
                8,
                12,
                12,
              ), // Reduced padding
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

  Widget _buildCachedMessagesList(dynamic chatState, String? currentUserId) {
  if (chatState is CachedChatInitial || chatState is CachedChatLoading) {
    // Show cached messages if available during loading
    if (chatState is CachedChatLoading && chatState.cachedMessages.isNotEmpty) {
      return _buildRomanticMessagesList(chatState.cachedMessages, currentUserId);
    }
    return const Center(child: ChatLoadingHeart());
  }
  
  if (chatState is CachedChatLoaded) {
    return Column(
      children: [
        // Optional: Show cache indicator
        if (chatState.isFromCache)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: Colors.orange.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.cached, size: 14, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'Showing cached messages',
                  style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                ),
              ],
            ),
          ),
        Expanded(child: _buildRomanticMessagesList(chatState.messages, currentUserId)),
      ],
    );
  }
  
  if (chatState is CachedChatSendingMessage) {
    return _buildRomanticMessagesList(chatState.messages, currentUserId);
  }
  
  if (chatState is CachedChatError) {
    if (chatState.cachedMessages.isNotEmpty) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.red.withOpacity(0.1),
            child: Text(
              'Connection error - showing cached messages',
              style: TextStyle(fontSize: 12, color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(child: _buildRomanticMessagesList(chatState.cachedMessages, currentUserId)),
        ],
      );
    }
    return _buildErrorState(chatState.message);
  }
  
  // Fallback for old states
  if (chatState is ChatLoaded) {
    return _buildRomanticMessagesList(chatState.messages, currentUserId);
  }
  
  return const Center(child: ChatLoadingHeart());
}

  // Enhanced romantic app bar user info
  Widget _buildRomanticAppBarUserInfo(
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
                  return _buildRomanticUserRow(
                    user: partner,
                    showTypingIndicator: true,
                  );
                } else {
                  return _buildRomanticConnectingState();
                }
              },
              loading: () => _buildRomanticPartnerLoadingState(),
              error: (error, stack) {
                print('❌ Error loading partner: $error');
                return _buildRomanticConnectionErrorState();
              },
            ),
          ),
        ],
      ),
    );
  }

  // Romantic user row with enhanced styling
  Widget _buildRomanticUserRow({
    required UserModel user,
    bool showTypingIndicator = false,
  }) {
    return Row(
      children: [
        Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CircleAvatar(
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
            ),
            // Enhanced romantic status indicator
            // In your _buildRomanticUserRow method, update the status indicator:
            Positioned(
              bottom: 0,
              right: 0,
              child: Consumer(
                builder: (context, ref, child) {
                  final statusColor = ref.watch(userStatusColorProvider(user));
                  return Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
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
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
              _buildRomanticPartnerStatusText(user, showTypingIndicator),
            ],
          ),
        ),
      ],
    );
  }

  // Update this method in your ChatScreen
  Widget _buildRomanticPartnerStatusText(
    UserModel partner,
    bool showTypingIndicator,
  ) {
    if (showTypingIndicator) {
      return ref
          .watch(enhancedTypingStatusProvider(partner.uid))
          .maybeWhen(
            data:
                (isTyping) =>
                    isTyping
                        ? const Text(
                          '💕 typing...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                        : Consumer(
                          builder: (context, ref, child) {
                            // Use the simple privacy-aware status from UserModel
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
                    // Use privacy-aware status for fallback
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

    // For non-typing indicator, use privacy-aware status
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

  // Romantic loading states
  Widget _buildRomanticPartnerLoadingState() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.3),
                Colors.white.withOpacity(0.1),
              ],
            ),
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
                '💕 Connecting to your love...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Please wait 💖',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRomanticConnectingState() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.3),
                Colors.white.withOpacity(0.1),
              ],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
          ),
          child: const Icon(Icons.favorite, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '💕 Finding your partner...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Connecting hearts 💖',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRomanticConnectionErrorState() {
    return GestureDetector(
      onTap: () async {
        print('🔄 Retrying romantic connection...');

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
              gradient: LinearGradient(
                colors: [
                  Colors.red.withOpacity(0.8),
                  Colors.pink.withOpacity(0.6),
                ],
              ),
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
                  '💔 Connection issue',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Tap to reconnect hearts 💕',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Enhanced romantic typing indicator
  Widget _buildRomanticTypingIndicator(AsyncValue<UserModel?> partnerUser) {
    return partnerUser.when(
      data:
          (partner) =>
              partner != null
                  ? ref
                      .watch(enhancedTypingStatusProvider(partner.uid))
                      .maybeWhen(
                        data:
                            (isTyping) =>
                                _useFloatingHeartsIndicator
                                    ? FloatingHeartsTypingIndicator(
                                      partnerName: partner.displayName,
                                      isVisible: isTyping,
                                    )
                                    : TypingIndicator(
                                      isTyping: isTyping,
                                      userName: partner.displayName,
                                      showAvatar: true,
                                    ),
                        orElse: () => const SizedBox.shrink(),
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
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey.shade300, Colors.grey.shade400],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.heart_broken,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '💔 $message',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              ref.read(chatControllerProvider.notifier).retry();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A95),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('💕 Try Again'),
          ),
        ],
      ),
    );
  }

  // Enhanced romantic messages list
  Widget _buildRomanticMessagesList(
    List<MessageModel> messages,
    String? currentUserId,
  ) {
    if (messages.isEmpty) {
      return _buildRomanticEmptyState();
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
              showReadStatus: true, // Enable romantic status display
              onLongPress: () => _showMessageOptions(message),
            ),
          );
        },
      ),
    );
  }

  // Enhanced romantic empty state
  Widget _buildRomanticEmptyState() {
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
                  colors: [const Color(0xFFCE93D8), const Color(0xFFFF8A95)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFCE93D8).withOpacity(0.3),
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
              'Send your first message to begin\nyour beautiful conversation together! 💖',
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
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFCE93D8).withOpacity(0.2),
                    const Color(0xFFFF8A95).withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFCE93D8).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite,
                    color: const Color(0xFFFF8A95),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Type something sweet below ↓',
                    style: TextStyle(
                      color: const Color(0xFFCE93D8),
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
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, Colors.purple.shade50],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
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
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFCE93D8),
                        const Color(0xFFFF8A95),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Copy Message
                ListTile(
                  leading: Icon(Icons.copy, color: const Color(0xFFCE93D8)),
                  title: const Text('Copy Message'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.message));
                    Navigator.pop(context);
                    if (mounted) {
                      _showSnackBar(
                        'Message copied with love 💕',
                        const Color(0xFFFF8A95),
                      );
                    }
                  },
                ),

                // Favorite Message
                FutureBuilder<bool>(
                  future: _checkIfMessageIsFavorited(message),
                  builder: (context, snapshot) {
                    final isFavorited = snapshot.data ?? false;
                    return ListTile(
                      leading: Icon(
                        isFavorited ? Icons.favorite : Icons.favorite_border,
                        color:
                            isFavorited ? Colors.red : const Color(0xFFCE93D8),
                      ),
                      title: Text(
                        isFavorited
                            ? 'Remove from Favorites'
                            : 'Add to Favorites',
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _toggleMessageFavorite(message);
                      },
                    );
                  },
                ),

                // Delete Message
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete Message',
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

  // Add these helper methods to your ChatScreen
  Future<bool> _checkIfMessageIsFavorited(MessageModel message) async {
    final chatState = ref.read(chatControllerProvider);
    if (chatState is! ChatLoaded) return false;

    return await ChatService.instance.isMessageFavorited(
      chatState.chatId,
      message.id,
    );
  }

  Future<void> _toggleMessageFavorite(MessageModel message) async {
    try {
      final chatState = ref.read(chatControllerProvider);
      if (chatState is! ChatLoaded) return;

      final success = await ChatService.instance.toggleMessageFavorite(
        chatState.chatId,
        message.id,
      );

      if (success && mounted) {
        final isFavorited = await _checkIfMessageIsFavorited(message);

        if (isFavorited) {
          _showSnackBar('💖 Message added to favorites', Colors.pink);
        } else {
          _showSnackBar('💔 Message removed from favorites', Colors.orange);
        }

        HapticFeedback.lightImpact();
      }
    } catch (e) {
      print('❌ Error toggling message favorite: $e');
      if (mounted) {
        _showSnackBar('❌ Failed to update favorite', Colors.red);
      }
    }
  }

  void _confirmDeleteMessage(MessageModel message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('💔 Delete Message'),
            content: const Text(
              'Are you sure you want to delete this message?\nThis action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ref
                      .read(chatControllerProvider.notifier)
                      .deleteMessage(message.id);
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }
}

// Enhanced romantic image source option
class _RomanticImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RomanticImageSourceOption({
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
            colors: [const Color(0xFFCE93D8), const Color(0xFFFF8A95)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFCE93D8).withOpacity(0.3),
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
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
