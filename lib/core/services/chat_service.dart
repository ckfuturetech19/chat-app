import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onlyus/core/services/couple_code_serivce.dart';

import '../../models/chat_model.dart';
import '../../models/message_model.dart';
import 'firebase_service.dart';
import 'notification_service.dart';

class ChatService {
  // Singleton instance
  static ChatService? _instance;
  static ChatService get instance => _instance ??= ChatService._();
  ChatService._();

  // Current active chat ID
  String? _activeChatId;

  // Typing status tracking
  final Map<String, bool> _typingStatus = {};

  // Enhanced message cache for offline support
  final Map<String, List<MessageModel>> _messageCache = {};

  final Map<String, StreamSubscription> _messageSubscriptions = {};

  // Connection status
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;

  // Stream controllers for real-time updates with better management
  final Map<String, StreamController<List<MessageModel>>>
  _messageStreamControllers = {};

  // Message delivery confirmation
  final Map<String, Completer<bool>> _messageDeliveryCompleters = {};

  void initialize() async {
    _setupConnectivityListener();

    // Initialize Firebase real-time listeners
    _setupFirebaseConnectionListener();

    // Try to initialize chat when service starts
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId != null) {
      final isConnected = await CoupleCodeService.instance.isUserConnected(
        currentUserId,
      );
      if (isConnected) {
        await initializeChatWithFallback();
      }
    }
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) {
      final wasOnline = _isOnline;
      _isOnline =
          result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.mobile);

      print('🌐 Connection status changed: $_isOnline');

      if (!wasOnline && _isOnline) {
        print('🌐 Connection restored, refreshing streams');
        _refreshAllStreams();
        _processOfflineMessages();
      }
    });
  }

  void _setupFirebaseConnectionListener() {
    // Listen to Firebase connection state
    FirebaseFirestore.instance
        .collection('system')
        .doc('connection')
        .snapshots()
        .listen((snapshot) {
          // This helps detect Firebase connection issues
          print('🔥 Firebase connection check');
        })
        .onError((error) {
          print('❌ Firebase connection error: $error');
        });
  }

  void _refreshAllStreams() {
    // Refresh all active message streams when connection is restored
    _messageStreamControllers.forEach((chatId, controller) {
      if (!controller.isClosed) {
        _setupMessageStreamListener(chatId);
      }
    });
  }

  // In chat_service.dart, update this method:
  Future<String?> initializeChatWithPartner() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Get current user document to find partner
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();

      if (!currentUserDoc.exists) {
        print('⚠️ Current user document not found');
        return null;
      }

      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
      final partnerId = currentUserData['partnerId'] as String?;

      if (partnerId == null || partnerId.isEmpty) {
        print('⚠️ No partner found for current user');
        print('📋 User data: $currentUserData'); // Debug log
        return null;
      }

      print('✅ Found partner: $partnerId');

      // Check if partner exists
      final partnerDoc =
          await FirebaseService.usersCollection.doc(partnerId).get();

      if (!partnerDoc.exists) {
        print('⚠️ Partner document not found');
        return null;
      }

      // Get or create chat room
      final chatId = await FirebaseService.getOrCreateChatRoom(partnerId);

      _activeChatId = chatId;
      print('✅ Chat initialized with ID: $chatId');

      return chatId;
    } catch (e) {
      print('❌ Error initializing chat: $e');
      return null;
    }
  }

  Future<String?> findExistingChat() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return null;

      // Query chats where current user is a participant
      final chatsQuery =
          await FirebaseService.chatsCollection
              .where('participants', arrayContains: currentUserId)
              .limit(1)
              .get();

      if (chatsQuery.docs.isNotEmpty) {
        final chatDoc = chatsQuery.docs.first;
        final chatId = chatDoc.id;
        _activeChatId = chatId;
        print('✅ Found existing chat: $chatId');
        return chatId;
      }

      print('⚠️ No existing chat found');
      return null;
    } catch (e) {
      print('❌ Error finding existing chat: $e');
      return null;
    }
  }

  Future<String?> initializeChatWithFallback() async {
    try {
      // Method 1: Try to initialize with partner
      String? chatId = await initializeChatWithPartner();
      if (chatId != null) return chatId;

      // Method 2: Try to find existing chat
      chatId = await findExistingChat();
      if (chatId != null) return chatId;

      print('⚠️ No chat could be initialized');
      return null;
    } catch (e) {
      print('❌ Error in chat initialization fallback: $e');
      return null;
    }
  }

  // In chat_service.dart:
  Future<bool> canInitializeChat() async { 
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return false;

    try {
      // Check if user document exists and has partnerId
      final userDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();
      if (!userDoc.exists) return false;

      final userData = userDoc.data() as Map<String, dynamic>;
      final partnerId = userData['partnerId'] as String?;
      final isConnected = userData['isConnected'] as bool? ?? false;

      print(
        '📋 canInitializeChat - partnerId: $partnerId, isConnected: $isConnected',
      );

      return partnerId != null && isConnected;
    } catch (e) {
      print('❌ Error checking if chat can be initialized: $e');
      return false;
    }
  }

  Future<bool> sendTextMessage({
    required String message,
    String? chatId,
  }) async {
    try {
      print('🔍 Starting sendTextMessage...');

      if (!_isOnline) {
        print('⚠️ Device is offline, queueing message');
        await _queueOfflineMessage(message, chatId);
        return false;
      }

      final currentUser = FirebaseService.currentUser;
      if (currentUser == null) {
        print('❌ Current user is null');
        throw Exception('User not authenticated');
      }
      print('✅ Current user: ${currentUser.uid}');

      // Check if user can send messages (is connected)
      final canSend = await canInitializeChat();
      if (!canSend) {
        print('⚠️ User is not connected to a partner');
        return false;
      }
      print('✅ User can send messages');

      final activeChatId = chatId ?? _activeChatId;
      print('🔍 Active chat ID: $activeChatId');

      if (activeChatId == null) {
        print('🔍 No active chat, trying to initialize...');
        final newChatId = await initializeChatWithFallback();
        if (newChatId == null) {
          print('❌ Could not initialize chat');
          throw Exception('No active chat and could not create one');
        }
        _activeChatId = newChatId;
        print('✅ New chat initialized: $_activeChatId');
      }

      // Create message delivery completer for confirmation
      final messageId = FirebaseService.generateMessageId();
      print('🔍 Generated message ID: $messageId');

      final deliveryCompleter = Completer<bool>();
      _messageDeliveryCompleters[messageId] = deliveryCompleter;

      // Send message to Firebase with enhanced data
      print('🔍 Sending message to Firebase...');
      await FirebaseService.sendMessage(
        chatId: _activeChatId!,
        message: message.trim(),
        senderId: currentUser.uid,
        senderName: currentUser.displayName ?? 'Unknown',
        messageId: messageId,
      );
      print('✅ Message sent to Firebase');

      // Update last activity
      await _updateLastActivity(_activeChatId!);
      print('✅ Updated last activity');

      // Send push notification to partner (improved)
      await _sendNotificationToPartner(
        chatId: _activeChatId!,
        message: message.trim(),
        senderId: currentUser.uid,
        senderName: currentUser.displayName ?? 'OnlyUs',
      );
      print('✅ Notification sent');

      // Clear typing status
      await updateTypingStatus(false);
      print('✅ Cleared typing status');

      print('✅ Text message sent successfully with ID: $messageId');

      // Wait for delivery confirmation (with timeout)
      try {
        await deliveryCompleter.future.timeout(const Duration(seconds: 10));
        return true;
      } catch (e) {
        print('⚠️ Message delivery timeout, but message was sent');
        return true; // Still return true as message was sent
      }
    } catch (e, stackTrace) {
      print('❌ Error sending text message: $e');
      print('📋 Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> sendImageMessage({
    required String imageUrl,
    String? caption,
    String? chatId,
  }) async {
    try {
      if (!_isOnline) {
        print('⚠️ Device is offline, cannot send image');
        return false;
      }

      final currentUser = FirebaseService.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final activeChatId = chatId ?? _activeChatId;
      if (activeChatId == null) {
        final newChatId = await initializeChatWithFallback();
        if (newChatId == null) {
          throw Exception('No active chat and could not create one');
        }
        _activeChatId = newChatId;
      }

      // Send image message to Firebase
      final messageId = FirebaseService.generateMessageId();
      await FirebaseService.sendMessage(
        chatId: _activeChatId!,
        message: caption ?? '',
        imageUrl: imageUrl,
        senderId: currentUser.uid,
        senderName: currentUser.displayName ?? 'Unknown',
        messageId: messageId,
      );

      // Update last activity
      await _updateLastActivity(_activeChatId!);

      // Send push notification to partner
      await _sendNotificationToPartner(
        chatId: _activeChatId!,
        message: '📷 Photo',
        senderId: currentUser.uid,
        senderName: currentUser.displayName ?? 'OnlyUs',
      );

      print('✅ Image message sent successfully');
      return true;
    } catch (e) {
      print('❌ Error sending image message: $e');
      return false;
    }
  }

  Future<void> updateTypingStatus(bool isTyping) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null || !_isOnline) return;

      if (_activeChatId == null) {
        await initializeChatWithFallback();
        if (_activeChatId == null) return;
      }

      // Update local typing status
      _typingStatus[currentUserId] = isTyping;

      // Update typing status in Firestore with better error handling
      await FirebaseService.chatsCollection
          .doc(_activeChatId!)
          .update({
            'typingUsers.$currentUserId': isTyping,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 3));

      print('✅ Typing status updated: $isTyping');
    } catch (e) {
      print('❌ Error updating typing status: $e');
    }
  }

  Future<void> markMessagesAsRead({String? chatId}) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null || !_isOnline) return;

      final activeChatId = chatId ?? _activeChatId;
      if (activeChatId == null) return;

      await FirebaseService.markMessagesAsRead(activeChatId, currentUserId);
      print('✅ Messages marked as read');
    } catch (e) {
      print('❌ Error marking messages as read: $e');
    }
  }

  Future<bool> deleteMessage(String messageId) async {
    try {
      if (!_isOnline) {
        print('⚠️ Device is offline, cannot delete message');
        return false;
      }

      await FirebaseService.deleteMessage(messageId);
      print('✅ Message deleted successfully');
      return true;
    } catch (e) {
      print('❌ Error deleting message: $e');
      return false;
    }
  }

  // Enhanced message stream with better real-time handling
  Stream<List<MessageModel>> getMessagesStream({String? chatId}) {
    final activeChatId = chatId ?? _activeChatId;
    if (activeChatId == null) {
      return Stream.value([]);
    }

    // Create or get existing stream controller
    if (!_messageStreamControllers.containsKey(activeChatId)) {
      _messageStreamControllers[activeChatId] =
          StreamController<List<MessageModel>>.broadcast();
      _setupMessageStreamListener(activeChatId);
    }

    return _messageStreamControllers[activeChatId]!.stream;
  }

  void _setupMessageStreamListener(String chatId) {
    final controller = _messageStreamControllers[chatId];
    if (controller == null || controller.isClosed) return;

    // Cancel any existing subscription to prevent duplicates
    _messageSubscriptions[chatId]?.cancel();

    print('📡 Setting up real-time message stream for chat: $chatId');

    // Enhanced Firestore query for better real-time performance
    final query = FirebaseService.messagesCollection
        .where('chatId', isEqualTo: chatId)
        .where('isDeleted', isEqualTo: false) // Exclude deleted messages
        .orderBy('timestamp', descending: true)
        .limit(100); // Limit for performance

    // Listen to Firestore stream with enhanced error handling
    _messageSubscriptions[chatId] = query.snapshots().listen(
      (snapshot) {
        try {
          print('📨 Stream received ${snapshot.docs.length} messages');

          final messages =
              snapshot.docs
                  .map(
                    (doc) => MessageModel.fromFirestore(
                      doc as DocumentSnapshot<Map<String, dynamic>>,
                    ),
                  )
                  .toList();

          // Handle message delivery confirmations
          for (final message in messages) {
            final completer = _messageDeliveryCompleters[message.id];
            if (completer != null && !completer.isCompleted) {
              completer.complete(true);
              _messageDeliveryCompleters.remove(message.id);
            }
          }

          // Sort messages by timestamp (newest first)
          messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Cache messages
          _messageCache[chatId] = messages;

          // Add to stream if controller is still active
          if (!controller.isClosed) {
            controller.add(messages);
            print('✅ Stream updated with ${messages.length} messages');
          }
        } catch (e) {
          print('❌ Error processing message snapshot: $e');
          // Add cached messages if available
          final cachedMessages = _messageCache[chatId] ?? [];
          if (!controller.isClosed) {
            controller.add(cachedMessages);
          }
        }
      },
      onError: (error) {
        print('❌ Message stream error: $error');

        // Handle specific Firestore errors
        final errorString = error.toString().toLowerCase();

        if (errorString.contains('failed-precondition') ||
            errorString.contains('requires an index') ||
            errorString.contains('index')) {
          print('⚠️ Firestore index missing - please create composite index');
          print(
            '📋 Required index: Collection: messages, Fields: chatId (Ascending), isDeleted (Ascending), timestamp (Descending)',
          );

          // Provide cached messages
          final cachedMessages = _messageCache[chatId] ?? [];
          if (!controller.isClosed) {
            controller.add(cachedMessages);
          }
          return; // Don't retry for index errors
        }

        // Try to provide cached messages for other errors
        final cachedMessages = _messageCache[chatId] ?? [];
        if (!controller.isClosed) {
          controller.add(cachedMessages);
        }

        // Retry connection after delay for other errors
        Timer(const Duration(seconds: 3), () {
          if (!controller.isClosed && _isOnline) {
            print('🔄 Retrying message stream connection');
            _setupMessageStreamListener(chatId);
          }
        });
      },
    );
  }

  // Enhanced chat stream for typing indicators
  Stream<ChatModel?> getChatStream({String? chatId}) {
    final activeChatId = chatId ?? _activeChatId;
    if (activeChatId == null) {
      return Stream.value(null);
    }

    return FirebaseService.chatsCollection
        .doc(activeChatId)
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            return ChatModel.fromFirestore(doc);
          }
          return null;
        })
        .handleError((error) {
          print('❌ Error in chat stream: $error');
          return null;
        });
  }

  Future<int> getUnreadMessageCount({String? chatId}) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return 0;

      final activeChatId = chatId ?? _activeChatId;
      if (activeChatId == null) return 0;

      final unreadMessages =
          await FirebaseService.messagesCollection
              .where('chatId', isEqualTo: activeChatId)
              .where('senderId', isNotEqualTo: currentUserId)
              .where('isRead', isEqualTo: false)
              .where('isDeleted', isEqualTo: false)
              .get();

      return unreadMessages.docs.length;
    } catch (e) {
      print('❌ Error getting unread message count: $e');
      return 0;
    }
  }

  Future<void> _updateLastActivity(String chatId) async {
    try {
      await FirebaseService.chatsCollection.doc(chatId).update({
        'lastActivity': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error updating last activity: $e');
    }
  }

  // Enhanced notification sending with better error handling
  Future<void> _sendNotificationToPartner({
    required String chatId,
    required String message,
    required String senderId,
    required String senderName,
  }) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return;

      // Get partner info
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();

      if (!currentUserDoc.exists) return;

      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
      final partnerId = currentUserData['partnerId'] as String?;

      if (partnerId == null) return;

      final partnerDoc =
          await FirebaseService.usersCollection.doc(partnerId).get();

      if (!partnerDoc.exists) return;

      final partnerData = partnerDoc.data() as Map<String, dynamic>;
      final oneSignalPlayerId = partnerData['oneSignalPlayerId'] as String?;

      if (oneSignalPlayerId == null || oneSignalPlayerId.isEmpty) {
        print('⚠️ Partner does not have OneSignal player ID');
        return;
      }

      // Check if partner is currently active in the chat
      final isPartnerInChat = await _isPartnerActiveInChat(partnerId, chatId);
      if (isPartnerInChat) {
        print('📱 Partner is active in chat, skipping notification');
        return;
      }

      // Send notification with retry logic
      await NotificationService.sendMessageNotification(
        recipientPlayerId: oneSignalPlayerId,
        senderName: senderName,
        message: message,
        chatId: chatId,
        senderId: senderId,
      );

      print('✅ Notification sent to partner');
    } catch (e) {
      print('❌ Error sending notification to partner: $e');
    }
  }

  Future<bool> _isPartnerActiveInChat(String partnerId, String chatId) async {
    try {
      // Check if partner was recently active (within last 30 seconds)
      final partnerDoc =
          await FirebaseService.usersCollection.doc(partnerId).get();
      if (!partnerDoc.exists) return false;

      final partnerData = partnerDoc.data() as Map<String, dynamic>;
      final lastSeen = partnerData['lastSeen'] as Timestamp?;

      if (lastSeen == null) return false;

      final now = DateTime.now();
      final lastSeenTime = lastSeen.toDate();
      final difference = now.difference(lastSeenTime);

      // Consider active if last seen within 30 seconds
      return difference.inSeconds < 30;
    } catch (e) {
      print('❌ Error checking partner activity: $e');
      return false;
    }
  }

  // Offline message queueing
  Future<void> _queueOfflineMessage(String message, String? chatId) async {
    try {
      // Store message locally for sending when online
      // You can implement this using local storage like Hive or SharedPreferences
      print('📝 Queuing offline message: $message');

      // For now, we'll just cache it in memory
      // In production, you should persist this to local storage
      // You can implement proper offline message storage here
    } catch (e) {
      print('❌ Error queueing offline message: $e');
    }
  }

  // Process queued offline messages when connection is restored
  Future<void> _processOfflineMessages() async {
    try {
      // Process any queued offline messages
      // Implementation depends on your local storage choice
      print('📤 Processing queued offline messages');
    } catch (e) {
      print('❌ Error processing offline messages: $e');
    }
  }

  // Enhanced message caching
  void cacheMessages(String chatId, List<MessageModel> messages) {
    try {
      _messageCache[chatId] = List.from(messages);

      // You can also persist to local storage here
      // Example: await _localStorage.setMessages(chatId, messages);

      print('💾 Cached ${messages.length} messages for chat $chatId');
    } catch (e) {
      print('❌ Error caching messages: $e');
    }
  }

  // Getters and utility methods
  String? get activeChatId => _activeChatId;
  bool get isOnline => _isOnline;

  void setActiveChatId(String? chatId) {
    _activeChatId = chatId;
  }

  List<MessageModel> getCachedMessages({String? chatId}) {
    final activeChatId = chatId ?? _activeChatId;
    if (activeChatId == null) return [];
    return List.from(_messageCache[activeChatId] ?? []);
  }

  bool isUserTyping(String userId) {
    return _typingStatus[userId] ?? false;
  }

  // Enhanced connection status
  Future<bool> checkConnectionHealth() async {
    try {
      // Try to read a small document from Firestore
      await FirebaseService.chatsCollection
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      print('❌ Connection health check failed: $e');
      return false;
    }
  }

  // Clean up resources
  void dispose() {
    print('🧹 Disposing ChatService resources');

    _connectivitySubscription?.cancel();

    // Cancel all message subscriptions
    _messageSubscriptions.forEach((_, subscription) {
      subscription.cancel();
    });
    _messageSubscriptions.clear();

    // Close all stream controllers
    _messageStreamControllers.forEach((_, controller) {
      if (!controller.isClosed) {
        controller.close();
      }
    });
    _messageStreamControllers.clear();

    // Complete any pending delivery confirmations
    _messageDeliveryCompleters.forEach((_, completer) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });
    _messageDeliveryCompleters.clear();

    // Clear caches
    _typingStatus.clear();
    _messageCache.clear();
    _activeChatId = null;
  }

  // Force refresh all active streams (useful for debugging)
  void forceRefreshStreams() {
    print('🔄 Force refreshing all message streams');
    _refreshAllStreams();
  }

  // Get detailed service status for debugging
  Map<String, dynamic> getServiceStatus() {
    return {
      'isOnline': _isOnline,
      'activeChatId': _activeChatId,
      'activeStreams': _messageStreamControllers.length,
      'cachedChats': _messageCache.length,
      'typingUsers': _typingStatus.length,
      'pendingDeliveries': _messageDeliveryCompleters.length,
    };
  }
}
