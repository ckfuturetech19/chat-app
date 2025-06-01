import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onlyus/core/services/couple_code_serivce.dart';
import 'package:onlyus/core/services/pressence_service.dart';
import 'package:onlyus/models/user_model.dart';

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

  // ADD: Prevent continuous read marking loops
  final Map<String, DateTime> _lastReadMarkTime = {};
  final Map<String, DateTime> _lastPartnerInfoCheck = {};
  static const Duration _readMarkCooldown = Duration(seconds: 30);
  static const Duration _partnerInfoCooldown = Duration(seconds: 10);

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

  // UPDATED: Enhanced initializeChatWithPartner
  Future<String?> initializeChatWithPartner() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      print('🔍 Initializing chat with partner for user: $currentUserId');

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
        print('📋 User data: $currentUserData');
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

      // IMPORTANT: Set up the message stream immediately after chat initialization
      await _setupMessageStreamListener(chatId);

      return chatId;
    } catch (e) {
      print('❌ Error initializing chat: $e');
      return null;
    }
  }

  // UPDATED: Enhanced findExistingChat
  Future<String?> findExistingChat() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return null;

      // Query chats where current user is a participant and hasn't deleted the chat
      final chatsQuery =
          await FirebaseService.chatsCollection
              .where('participants', arrayContains: currentUserId)
              .limit(1)
              .get();

      for (final chatDoc in chatsQuery.docs) {
        final chatData = chatDoc.data();
        final deletedBy = List<String>.from(chatData['deletedBy'] ?? []);

        // Skip if current user has deleted this chat
        if (deletedBy.contains(currentUserId)) {
          continue;
        }

        final chatId = chatDoc.id;
        _activeChatId = chatId;
        print('✅ Found existing chat: $chatId');

        // Set up message stream for existing chat
        await _setupMessageStreamListener(chatId);

        return chatId;
      }

      print('⚠️ No existing active chat found');
      return null;
    } catch (e) {
      print('❌ Error finding existing chat: $e');
      return null;
    }
  }

  // UPDATED: Enhanced getMessagesStream with subcollection
  Stream<List<MessageModel>> getMessagesStream({String? chatId}) {
    final activeChatId = chatId ?? _activeChatId;
    if (activeChatId == null) {
      print('⚠️ No active chat ID for message stream');
      return Stream.value([]);
    }

    print('📡 Creating message stream for chat: $activeChatId');

    // Create or get existing stream controller
    if (!_messageStreamControllers.containsKey(activeChatId)) {
      _messageStreamControllers[activeChatId] =
          StreamController<List<MessageModel>>.broadcast();

      // Set up the listener immediately
      _setupMessageStreamListener(activeChatId);
    }

    return _messageStreamControllers[activeChatId]!.stream;
  }

  // UPDATED: Improved message stream listener setup with subcollection
  Future<void> _setupMessageStreamListener(String chatId) async {
    final controller = _messageStreamControllers[chatId];
    if (controller == null || controller.isClosed) {
      print('⚠️ Stream controller not available for chat: $chatId');
      return;
    }

    await _messageSubscriptions[chatId]?.cancel();
    print('📡 Setting up message stream for subcollection chat: $chatId');

    try {
      // UPDATED: Use subcollection query
      final query = FirebaseService.getMessagesCollection(chatId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('timestamp', descending: true)
          .limit(100);

      print('📋 Using subcollection query for chat: $chatId');

      _messageSubscriptions[chatId] = query.snapshots().listen(
        (snapshot) {
          try {
            print(
              '📨 Subcollection stream received ${snapshot.docs.length} messages',
            );

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

            // Cache messages
            _messageCache[chatId] = messages;

            if (!controller.isClosed) {
              controller.add(messages);
              print(
                '✅ Subcollection stream updated with ${messages.length} messages',
              );
            }
          } catch (e) {
            print('❌ Error processing subcollection message snapshot: $e');
            final cachedMessages = _messageCache[chatId] ?? [];
            if (!controller.isClosed) {
              controller.add(cachedMessages);
            }
          }
        },
        onError: (error) {
          print('❌ Subcollection message stream error: $error');

          // Provide cached messages for errors
          final cachedMessages = _messageCache[chatId] ?? [];
          if (!controller.isClosed) {
            controller.add(cachedMessages);
          }

          // Retry after delay
          Timer(const Duration(seconds: 5), () {
            if (!controller.isClosed && _isOnline) {
              print('🔄 Retrying subcollection query for chat: $chatId');
              _setupMessageStreamListener(chatId);
            }
          });
        },
      );
    } catch (e) {
      print('❌ Error setting up subcollection stream: $e');
    }
  }

  // NEW: Soft delete chat for current user
  Future<bool> deleteChatForCurrentUser({String? chatId}) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user for chat deletion');
        return false;
      }

      final activeChatId = chatId ?? _activeChatId;
      if (activeChatId == null) {
        print('❌ No chat ID provided for deletion');
        return false;
      }

      print('🗑️ Soft deleting chat for user: $currentUserId');

      // Soft delete the chat for current user
      await FirebaseService.deleteChatForUser(activeChatId, currentUserId);

      // Clear local state if this was the active chat
      if (activeChatId == _activeChatId) {
        _activeChatId = null;

        // Close stream for this chat
        await _messageSubscriptions[activeChatId]?.cancel();
        _messageSubscriptions.remove(activeChatId);

        // Close stream controller
        final controller = _messageStreamControllers[activeChatId];
        if (controller != null && !controller.isClosed) {
          controller.close();
        }
        _messageStreamControllers.remove(activeChatId);

        // Clear cache
        _messageCache.remove(activeChatId);
      }

      print('✅ Chat soft deleted successfully');
      return true;
    } catch (e) {
      print('❌ Error soft deleting chat: $e');
      return false;
    }
  }

  // NEW: Get user's chats stream (excluding deleted ones)
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>> getUserChatsStream() {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) {
      return Stream.value([]);
    }

    return FirebaseService.getUserChatsStreamFiltered(currentUserId);
  }

  // NEW: Check if chat is deleted by current user
  Future<bool> isChatDeletedByUser({String? chatId}) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return false;

      final activeChatId = chatId ?? _activeChatId;
      if (activeChatId == null) return false;

      final chatDoc =
          await FirebaseService.chatsCollection.doc(activeChatId).get();
      if (!chatDoc.exists) return true; // Consider non-existent as deleted

      final chatData = chatDoc.data() as Map<String, dynamic>;
      final deletedBy = List<String>.from(chatData['deletedBy'] ?? []);

      return deletedBy.contains(currentUserId);
    } catch (e) {
      print('❌ Error checking if chat is deleted: $e');
      return false;
    }
  }

  // NEW: Restore deleted chat
  Future<bool> restoreChat({String? chatId}) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user for chat restoration');
        return false;
      }

      final activeChatId = chatId ?? _activeChatId;
      if (activeChatId == null) {
        print('❌ No chat ID provided for restoration');
        return false;
      }

      print('🔄 Restoring chat for user: $currentUserId');

      await FirebaseService.restoreChatForUser(activeChatId, currentUserId);

      // Set up streams again if this becomes active chat
      if (activeChatId == _activeChatId) {
        await _setupMessageStreamListener(activeChatId);
      }

      print('✅ Chat restored successfully');
      return true;
    } catch (e) {
      print('❌ Error restoring chat: $e');
      return false;
    }
  }

  // Force refresh messages stream
  Future<void> refreshMessagesStream({String? chatId}) async {
    final activeChatId = chatId ?? _activeChatId;
    if (activeChatId == null) return;

    print('🔄 Force refreshing messages stream for chat: $activeChatId');

    // Cancel existing subscription
    await _messageSubscriptions[activeChatId]?.cancel();

    // Set up new listener
    await _setupMessageStreamListener(activeChatId);
  }

  // Set active chat ID and setup stream
  Future<void> setActiveChatId(String? chatId) async {
    _activeChatId = chatId;
    if (chatId != null) {
      await _setupMessageStreamListener(chatId);
    }
  }

  // Enhanced _refreshAllStreams
  void _refreshAllStreams() {
    // Refresh all active message streams when connection is restored
    _messageStreamControllers.forEach((chatId, controller) {
      if (!controller.isClosed) {
        print('🔄 Refreshing stream for chat: $chatId');
        _setupMessageStreamListener(chatId);
      }
    });
  }

  // Check if stream is active for debugging
  bool isStreamActive(String? chatId) {
    final activeChatId = chatId ?? _activeChatId;
    if (activeChatId == null) return false;

    final controller = _messageStreamControllers[activeChatId];
    final subscription = _messageSubscriptions[activeChatId];

    return controller != null && !controller.isClosed && subscription != null;
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

  // UPDATED: Send text message with subcollection support
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

      // UPDATED: Send message to Firebase subcollection
      print('🔍 Sending message to Firebase subcollection...');
      await FirebaseService.sendMessage(
        chatId: _activeChatId!,
        message: message.trim(),
        senderId: currentUser.uid,
        senderName: currentUser.displayName ?? 'Unknown',
        messageId: messageId,
      );
      print('✅ Message sent to Firebase subcollection');

      // Update last activity
      await _updateLastActivity(_activeChatId!);
      print('✅ Updated last activity');

      // FIXED: Enhanced notification sending with better targeting
      await _sendNotificationToPartnerEnhanced(
        chatId: _activeChatId!,
        message: message.trim(),
        senderId: currentUser.uid,
        senderName: currentUser.displayName ?? 'OnlyUs',
      );
      print('✅ Enhanced notification sent');

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

  // UPDATED: Send image message with subcollection support
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

      // Send image message to Firebase subcollection
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

      // FIXED: Enhanced notification for image messages
      await _sendNotificationToPartnerEnhanced(
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

      // Update typing status in Firestore
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

  // FIXED: Enhanced mark messages as read with cooldown to prevent loops
  Future<void> markMessagesAsReadEnhanced({String? chatId}) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null || !_isOnline) return;

      final activeChatId = chatId ?? _activeChatId;
      if (activeChatId == null) return;

      // CHECK: Prevent continuous read marking with cooldown
      final now = DateTime.now();
      final lastMarkTime = _lastReadMarkTime[activeChatId];

      if (lastMarkTime != null &&
          now.difference(lastMarkTime) < _readMarkCooldown) {
        print(
          '🔄 Skipping read mark - cooldown active (${now.difference(lastMarkTime).inSeconds}s ago)',
        );
        return;
      }

      _lastReadMarkTime[activeChatId] = now;

      print('🔍 Marking received messages as read for chat: $activeChatId');

      // FIXED: Only mark messages as read that were received by current user
      await FirebaseService.markReceivedMessagesAsRead(
        activeChatId,
        currentUserId,
      );

      // Also update presence to show user is active
      await PresenceService.instance.updateLastSeen();

      print('✅ Received messages marked as read and presence updated');
    } catch (e) {
      print('❌ Error marking received messages as read: $e');
    }
  }

  // UPDATED: Delete message in subcollection
  Future<bool> deleteMessage(String messageId) async {
    try {
      if (!_isOnline) {
        print('⚠️ Device is offline, cannot delete message');
        return false;
      }

      if (_activeChatId == null) {
        print('❌ No active chat for message deletion');
        return false;
      }

      await FirebaseService.deleteMessage(_activeChatId!, messageId);
      print('✅ Message deleted successfully');
      return true;
    } catch (e) {
      print('❌ Error deleting message: $e');
      return false;
    }
  }

  Future<String?> initializeChatAfterConnection() async {
    try {
      print('🔍 ChatService: Initializing chat after connection...');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user ID available');
        return null;
      }

      // Wait a moment for Firestore to propagate the connection changes
      await Future.delayed(const Duration(milliseconds: 1000));

      // Verify user is actually connected
      final connectionStatus = await CoupleCodeService.instance
          .getConnectionStatus(currentUserId);
      print('📋 Connection status: $connectionStatus');

      if (connectionStatus['isConnected'] != true ||
          connectionStatus['partnerId'] == null) {
        print('❌ User is not properly connected');
        return null;
      }

      final partnerId = connectionStatus['partnerId'] as String;
      print('✅ Found partner: $partnerId');

      // Initialize chat with retry logic
      String? chatId;
      int attempts = 0;
      const maxAttempts = 3;

      while (chatId == null && attempts < maxAttempts) {
        attempts++;
        print('🔍 Chat initialization attempt $attempts/$maxAttempts');

        try {
          chatId = await FirebaseService.getOrCreateChatRoom(partnerId);

          print('✅ Chat room created/found: $chatId');

          // Verify chat room is properly set up
          final chatDoc =
              await FirebaseService.chatsCollection.doc(chatId).get();
          if (chatDoc.exists) {
            final chatData = chatDoc.data() as Map<String, dynamic>;
            final participants = List<String>.from(
              chatData['participants'] ?? [],
            );

            if (participants.contains(currentUserId) &&
                participants.contains(partnerId)) {
              print('✅ Chat room verified with correct participants');
              _activeChatId = chatId;
              return chatId;
            } else {
              print('⚠️ Chat room participants mismatch, retrying...');
              chatId = null;
            }
          } else {
            print('⚠️ Chat document not found, retrying...');
            chatId = null;
          }
        } catch (e) {
          print('❌ Error in attempt $attempts: $e');
          if (attempts >= maxAttempts) {
            rethrow;
          }
        }

        if (chatId == null && attempts < maxAttempts) {
          // Wait before retry
          await Future.delayed(Duration(milliseconds: 500 * attempts));
        }
      }

      if (chatId == null) {
        throw Exception(
          'Failed to initialize chat after $maxAttempts attempts',
        );
      }

      return chatId;
    } catch (e) {
      print('❌ Error in initializeChatAfterConnection: $e');
      return null;
    }
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

      return await FirebaseService.getUnreadMessageCount(
        activeChatId,
        currentUserId,
      );
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

  // FIXED: Enhanced notification sending with better presence checking
  Future<void> _sendNotificationToPartnerEnhanced({
    required String chatId,
    required String message,
    required String senderId,
    required String senderName,
  }) async {
    try {
      print('📤 Sending enhanced notification to partner...');
      print('📋 Chat ID: $chatId');
      print('📋 Sender: $senderName');
      print('📋 Message: $message');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user ID for notification');
        return;
      }

      // FIXED: Get partner info WITHOUT cooldown for notifications
      final partnerInfo = await getPartnerInfoForNotification(currentUserId);
      if (partnerInfo == null) {
        print('❌ No partner found for notification');
        return;
      }

      final partnerId = partnerInfo['partnerId'] as String;
      final oneSignalPlayerId = partnerInfo['oneSignalPlayerId'] as String;
      final partnerName = partnerInfo['displayName'] as String;
      final isPartnerOnline = partnerInfo['isOnline'] as bool? ?? false;

      print('✅ Partner info retrieved:');
      print('  - Partner ID: $partnerId');
      print('  - Player ID: $oneSignalPlayerId');
      print('  - Name: $partnerName');
      print('  - Is Online: $isPartnerOnline');

      // SIMPLIFIED: Always send notification if partner is offline
      // Check partner presence more thoroughly
      bool shouldSendNotification = true;

      try {
        // Quick online check - if offline, definitely send
        final partnerPresenceStatus = await PresenceService.instance
            .isUserOnline(partnerId);
        print(
          '👥 Partner presence check: ${partnerPresenceStatus ? "Online" : "Offline"}',
        );

        if (!partnerPresenceStatus) {
          print('✅ Partner is offline - sending notification');
          shouldSendNotification = true;
        } else {
          // Partner is online, check if they're actively in this chat
          final partnerDoc =
              await FirebaseService.usersCollection.doc(partnerId).get();
          if (partnerDoc.exists) {
            final partnerData = partnerDoc.data() as Map<String, dynamic>;
            final partnerActiveChatId = partnerData['activeChatId'] as String?;
            final partnerIsInBackground =
                partnerData['isAppInBackground'] as bool? ?? false;

            // Send notification if partner is in background OR not in this specific chat
            if (partnerIsInBackground || partnerActiveChatId != chatId) {
              print(
                '✅ Partner not actively viewing this chat - sending notification',
              );
              shouldSendNotification = true;
            } else {
              print(
                '❌ Partner is actively viewing this chat - skipping notification',
              );
              shouldSendNotification = false;
            }
          }
        }
      } catch (e) {
        print(
          '⚠️ Error checking partner presence: $e - defaulting to send notification',
        );
        shouldSendNotification = true; // Default to sending on error
      }

      if (!shouldSendNotification) {
        print('❌ Skipping notification - partner is actively viewing chat');
        return;
      }

      // Send the notification
      print('🚀 Proceeding to send notification...');

      final success = await NotificationService.sendMessageNotification(
        recipientPlayerId: oneSignalPlayerId,
        senderName: senderName,
        message: message,
        chatId: chatId,
        senderId: senderId,
      );

      if (success) {
        print(
          '✅ Enhanced notification sent successfully to partner: $partnerName',
        );
      } else {
        print('❌ Enhanced notification failed to send via normal method');

        // FALLBACK: Try force send if normal send fails
        print('🔄 Attempting force send as fallback...');
        final forceSuccess = await NotificationService.forceSendNotification(
          recipientPlayerId: oneSignalPlayerId,
          senderName: senderName,
          message: message,
          chatId: chatId,
          senderId: senderId,
        );

        if (forceSuccess) {
          print('✅ Force notification sent successfully');
        } else {
          print('❌ Both normal and force notification failed');
        }
      }
    } catch (e) {
      print('❌ Error sending enhanced notification to partner: $e');
    }
  }

  Future<Map<String, dynamic>?> getPartnerInfoForNotification(
    String currentUserId,
  ) async {
    try {
      print('🔍 Getting partner info for notification (no cooldown)');

      // Get current user document
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();

      if (!currentUserDoc.exists) {
        print('❌ Current user document not found: $currentUserId');
        return null;
      }

      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
      final partnerId = currentUserData['partnerId'] as String?;

      if (partnerId == null || partnerId.isEmpty) {
        print('⚠️ No partner ID found for user: $currentUserId');
        return null;
      }

      print('✅ Found partner ID: $partnerId');

      // Get partner document
      final partnerDoc =
          await FirebaseService.usersCollection.doc(partnerId).get();

      if (!partnerDoc.exists) {
        print('❌ Partner document not found: $partnerId');
        return null;
      }

      final partnerData = partnerDoc.data() as Map<String, dynamic>;
      final oneSignalPlayerId = partnerData['oneSignalPlayerId'] as String?;

      if (oneSignalPlayerId == null || oneSignalPlayerId.isEmpty) {
        print('⚠️ Partner does not have OneSignal player ID: $partnerId');
        return null;
      }

      print('✅ Partner has OneSignal player ID: $oneSignalPlayerId');

      // Get partner's real-time presence status
      bool isPartnerOnlineRealtime = false;
      try {
        isPartnerOnlineRealtime = await PresenceService.instance.isUserOnline(
          partnerId,
        );
      } catch (e) {
        print('⚠️ Error getting partner real-time presence: $e');
      }

      return {
        'partnerId': partnerId,
        'oneSignalPlayerId': oneSignalPlayerId,
        'displayName': partnerData['displayName'] ?? 'Unknown',
        'photoURL': partnerData['photoURL'],
        'isOnline': partnerData['isOnline'] ?? false, // Firestore status
        'isOnlineRealtime': isPartnerOnlineRealtime, // Real-time status
        'lastSeen': partnerData['lastSeen'],
        'activeChatId': partnerData['activeChatId'],
        'appState': partnerData['appState'],
        'isAppInBackground': partnerData['isAppInBackground'] ?? false,
      };
    } catch (e) {
      print('❌ Error getting partner info for notification: $e');
      return null;
    }
  }

  // IMPROVED: Get partner information with better error handling and more details
  Future<Map<String, dynamic>?> getPartnerInfoWithCooldown(
    String currentUserId,
  ) async {
    try {
      // CHECK: Prevent continuous partner info checks
      final now = DateTime.now();
      final lastCheckTime = _lastPartnerInfoCheck[currentUserId];

      if (lastCheckTime != null &&
          now.difference(lastCheckTime) < _partnerInfoCooldown) {
        // print(
        //   '🔄 Skipping partner info check - cooldown active (${now.difference(lastCheckTime).inSeconds}s ago)',
        // );
        return null;
      }

      _lastPartnerInfoCheck[currentUserId] = now;

      print('🔍 Getting partner info for user: $currentUserId');

      // Get current user document
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();

      if (!currentUserDoc.exists) {
        print('❌ Current user document not found: $currentUserId');
        return null;
      }

      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
      final partnerId = currentUserData['partnerId'] as String?;

      if (partnerId == null || partnerId.isEmpty) {
        print('⚠️ No partner ID found for user: $currentUserId');
        return null;
      }

      print('✅ Found partner ID: $partnerId');

      // Get partner document
      final partnerDoc =
          await FirebaseService.usersCollection.doc(partnerId).get();

      if (!partnerDoc.exists) {
        print('❌ Partner document not found: $partnerId');
        return null;
      }

      final partnerData = partnerDoc.data() as Map<String, dynamic>;
      final oneSignalPlayerId = partnerData['oneSignalPlayerId'] as String?;

      if (oneSignalPlayerId == null || oneSignalPlayerId.isEmpty) {
        print('⚠️ Partner does not have OneSignal player ID: $partnerId');
        return null;
      }

      print('✅ Partner has OneSignal player ID: $oneSignalPlayerId');

      // Get partner's real-time presence status
      bool isPartnerOnlineRealtime = false;
      try {
        isPartnerOnlineRealtime = await PresenceService.instance.isUserOnline(
          partnerId,
        );
      } catch (e) {
        print('⚠️ Error getting partner real-time presence: $e');
      }

      return {
        'partnerId': partnerId,
        'oneSignalPlayerId': oneSignalPlayerId,
        'displayName': partnerData['displayName'] ?? 'Unknown',
        'photoURL': partnerData['photoURL'],
        'isOnline': partnerData['isOnline'] ?? false, // Firestore status
        'isOnlineRealtime': isPartnerOnlineRealtime, // Real-time status
        'lastSeen': partnerData['lastSeen'],
        'activeChatId': partnerData['activeChatId'],
        'appState': partnerData['appState'],
        'isAppInBackground': partnerData['isAppInBackground'] ?? false,
      };
    } catch (e) {
      print('❌ Error getting partner info: $e');
      return null;
    }
  }

  // ADD: Method to test notification sending easily
  Future<void> testNotificationToPartner() async {
    try {
      print('🧪 Testing notification to partner...');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user for test');
        return;
      }

      final partnerInfo = await getPartnerInfoWithCooldown(currentUserId);
      if (partnerInfo == null) {
        print('❌ No partner info for test');
        return;
      }

      final oneSignalPlayerId = partnerInfo['oneSignalPlayerId'] as String;
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();
      final currentUserName =
          currentUserDoc.exists
              ? (currentUserDoc.data()
                      as Map<String, dynamic>)['displayName'] ??
                  'Test User'
              : 'Test User';

      // Force send test notification
      final success = await NotificationService.forceSendNotification(
        recipientPlayerId: oneSignalPlayerId,
        senderName: currentUserName,
        message:
            '🧪 Test notification from ChatService - ${DateTime.now().toIso8601String()}',
        chatId: _activeChatId ?? 'test_chat',
        senderId: currentUserId,
      );

      print(
        success ? '✅ Test notification sent!' : '❌ Test notification failed!',
      );
    } catch (e) {
      print('❌ Error testing notification: $e');
    }
  }

  // ADD: Debug method to check notification status
  Future<void> debugNotificationStatus() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user for debug');
        return;
      }

      print('🔍 === NOTIFICATION DEBUG STATUS ===');

      // Check current user OneSignal setup
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();
      if (currentUserDoc.exists) {
        final userData = currentUserDoc.data() as Map<String, dynamic>;
        print(
          '📱 Current User OneSignal Player ID: ${userData['oneSignalPlayerId']}',
        );
        print('📱 Current User Name: ${userData['displayName']}');
        print('📱 Notifications Enabled: ${userData['notificationEnabled']}');
      }

      // Check partner setup
      final partnerInfo = await getPartnerInfo(currentUserId);
      if (partnerInfo != null) {
        print('👥 Partner ID: ${partnerInfo['partnerId']}');
        print(
          '👥 Partner OneSignal Player ID: ${partnerInfo['oneSignalPlayerId']}',
        );
        print('👥 Partner Name: ${partnerInfo['displayName']}');
        print('👥 Partner Online (Firestore): ${partnerInfo['isOnline']}');
        print(
          '👥 Partner Online (Realtime): ${partnerInfo['isOnlineRealtime']}',
        );
        print('👥 Partner Active Chat: ${partnerInfo['activeChatId']}');
        print('👥 Partner App State: ${partnerInfo['appState']}');
        print('👥 Partner In Background: ${partnerInfo['isAppInBackground']}');
      } else {
        print('❌ No partner info available');
      }

      // Check active chat
      print('💬 Current Active Chat: $_activeChatId');

      // Check cooldown status
      final lastCheck = _lastPartnerInfoCheck[currentUserId];
      if (lastCheck != null) {
        final timeSince = DateTime.now().difference(lastCheck);
        print('⏰ Last partner info check: ${timeSince.inSeconds} seconds ago');
      }

      print('🔍 === END DEBUG STATUS ===');
    } catch (e) {
      print('❌ Error in notification debug: $e');
    }
  }

  // LEGACY: Keep original method for backward compatibility
  Future<Map<String, dynamic>?> getPartnerInfo(String currentUserId) async {
    return await getPartnerInfoWithCooldown(currentUserId);
  }

  Future<void> setActiveChatIdWithNotification(String? chatId) async {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return;

    try {
      // Update local state
      _activeChatId = chatId;

      // Update notification service
      NotificationService.setActiveChatId(chatId);

      // Update user's active chat in Firestore
      await NotificationService.setUserActiveChatId(currentUserId, chatId);

      // Clear unread count for this chat if opening it
      if (chatId != null) {
        await NotificationService.clearUnreadCount(currentUserId, chatId);
        await markMessagesAsReadEnhanced(chatId: chatId);
      }

      // Set up message stream listener
      if (chatId != null) {
        await _setupMessageStreamListener(chatId);
      }

      print('✅ Active chat set with notification integration: $chatId');
    } catch (e) {
      print('❌ Error setting active chat with notification: $e');
    }
  }

  // Offline message queueing
  Future<void> _queueOfflineMessage(String message, String? chatId) async {
    try {
      // Store message locally for sending when online
      print('📝 Queuing offline message: $message');
      // Implementation for offline storage would go here
    } catch (e) {
      print('❌ Error queueing offline message: $e');
    }
  }

  // Process queued offline messages when connection is restored
  Future<void> _processOfflineMessages() async {
    try {
      // Process any queued offline messages
      print('📤 Processing queued offline messages');
      // Implementation for processing offline messages would go here
    } catch (e) {
      print('❌ Error processing offline messages: $e');
    }
  }

  // Enhanced message caching
  void cacheMessages(String chatId, List<MessageModel> messages) {
    try {
      _messageCache[chatId] = List.from(messages);
      print('💾 Cached ${messages.length} messages for chat $chatId');
    } catch (e) {
      print('❌ Error caching messages: $e');
    }
  }

  // Getters and utility methods
  String? get activeChatId => _activeChatId;
  bool get isOnline => _isOnline;

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

  // RESTORED: Enhanced typing status with notification awareness
  Future<void> updateTypingStatusEnhanced(bool isTyping) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null || !_isOnline) return;

      if (_activeChatId == null) {
        await initializeChatWithFallback();
        if (_activeChatId == null) return;
      }

      // Update local typing status
      _typingStatus[currentUserId] = isTyping;

      // Update typing status in Firestore
      await FirebaseService.chatsCollection
          .doc(_activeChatId!)
          .update({
            'typingUsers.$currentUserId': isTyping,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 3));

      // If user starts typing, ensure they're marked as active in this chat
      if (isTyping) {
        await NotificationService.setUserActiveChatId(
          currentUserId,
          _activeChatId,
        );
      }

      print('✅ Enhanced typing status updated: $isTyping');
    } catch (e) {
      print('❌ Error updating enhanced typing status: $e');
    }
  }

  // RESTORED: Debug method to check notification setup
  Future<void> debugNotificationSetup() async {
    try {
      print('🔍 Debugging notification setup...');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user for debug');
        return;
      }

      // Check current user OneSignal setup
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();
      if (currentUserDoc.exists) {
        final userData = currentUserDoc.data() as Map<String, dynamic>;
        print(
          '📋 Current user OneSignal player ID: ${userData['oneSignalPlayerId']}',
        );
        print(
          '📋 Current user notification enabled: ${userData['notificationEnabled']}',
        );
      }

      // Check partner setup
      final partnerInfo = await getPartnerInfo(currentUserId);
      if (partnerInfo != null) {
        print(
          '📋 Partner OneSignal player ID: ${partnerInfo['oneSignalPlayerId']}',
        );
        print('📋 Partner name: ${partnerInfo['displayName']}');
      } else {
        print('❌ No partner info available');
      }

      // // Check OneSignal service status
      // await NotificationService.debugUserPlayerIdMapping();
    } catch (e) {
      print('❌ Error in notification debug: $e');
    }
  }

  // RESTORED: Method to handle when user enters chat screen
  Future<void> onChatScreenEntered(String chatId) async {
    try {
      print('📱 User entered chat screen: $chatId');

      // Set active chat with notification integration
      await setActiveChatIdWithNotification(chatId);

      // Mark messages as read with cooldown
      await markMessagesAsReadEnhanced(chatId: chatId);

      // Update user activity
      await _updateLastActivity(chatId);

      print('✅ Chat screen entry handled');
    } catch (e) {
      print('❌ Error handling chat screen entry: $e');
    }
  }

  // RESTORED: Method to handle when user exits chat screen
  Future<void> onChatScreenExited() async {
    try {
      print('📱 User exited chat screen');

      // Clear active chat
      await setActiveChatIdWithNotification(null);

      // Clear typing status
      await updateTypingStatus(false);

      print('✅ Chat screen exit handled');
    } catch (e) {
      print('❌ Error handling chat screen exit: $e');
    }
  }

  // ADD this method for automatic read receipts
  Future<void> checkAndUpdateMessageStatuses() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null || _activeChatId == null) return;

      print('🔍 Checking message statuses for user: $currentUserId');

      // FIXED: Only mark messages as read that were SENT TO current user (not BY current user)
      final unreadReceivedQuery =
          await FirebaseService.getMessagesCollection(_activeChatId!)
              .where(
                'senderId',
                isNotEqualTo: currentUserId,
              ) // Messages NOT sent by current user
              .where('isRead', isEqualTo: false) // That are unread
              .where('isDeleted', isEqualTo: false) // And not deleted
              .get();

      if (unreadReceivedQuery.docs.isNotEmpty) {
        print(
          '📖 Found ${unreadReceivedQuery.docs.length} unread received messages to mark as read',
        );

        final batch = FirebaseService.firestore.batch();

        for (final doc in unreadReceivedQuery.docs) {
          batch.update(doc.reference, {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
            'readBy': currentUserId,
            'deliveryStatus': 'read',
          });
        }

        await batch.commit();
        print(
          '✅ Updated ${unreadReceivedQuery.docs.length} received messages to read status',
        );
      } else {
        // Don't spam logs when there are no unread messages
        // print('✅ No unread received messages found');
      }

      // SEPARATE: Update delivery status for messages sent BY current user (but don't mark them as read)
      await _updateSentMessageDeliveryStatus(currentUserId);
    } catch (e) {
      print('❌ Error checking and updating message statuses: $e');
    }
  }

  Future<void> _updateSentMessageDeliveryStatus(String currentUserId) async {
    try {
      // Get partner info
      final partnerInfo = await getPartnerInfo(currentUserId);
      if (partnerInfo == null) return;

      final partnerId = partnerInfo['partnerId'] as String;

      // Check if partner is online and in same chat
      final partnerDoc =
          await FirebaseService.usersCollection.doc(partnerId).get();
      if (!partnerDoc.exists) return;

      final partnerData = partnerDoc.data() as Map<String, dynamic>;
      final partnerActiveChat = partnerData['activeChatId'] as String?;
      final isPartnerOnline = await PresenceService.instance.isUserOnline(
        partnerId,
      );

      // If partner is online and in same chat, update delivery status for sent messages
      if (isPartnerOnline && partnerActiveChat == _activeChatId) {
        final undeliveredSentMessages =
            await FirebaseService.getMessagesCollection(_activeChatId!)
                .where(
                  'senderId',
                  isEqualTo: currentUserId,
                ) // Messages sent BY current user
                .where(
                  'deliveryStatus',
                  whereIn: ['sending', 'sent'],
                ) // Not yet delivered
                .get();

        if (undeliveredSentMessages.docs.isNotEmpty) {
          final batch = FirebaseService.firestore.batch();

          for (final doc in undeliveredSentMessages.docs) {
            batch.update(doc.reference, {
              'deliveryStatus': 'delivered',
              'deliveredAt': FieldValue.serverTimestamp(),
            });
          }

          await batch.commit();
          print(
            '✅ Updated ${undeliveredSentMessages.docs.length} sent messages to delivered status',
          );
        }
      }
    } catch (e) {
      print('❌ Error updating sent message delivery status: $e');
    }
  }

  // ADD this enhanced method for entering chat
  Future<void> onChatScreenEnteredEnhanced(String chatId) async {
    try {
      print('📱 User entered chat screen: $chatId');

      // Set active chat
      _activeChatId = chatId;

      // Update user's active chat in Firestore
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        await FirebaseService.usersCollection.doc(currentUserId).update({
          'activeChatId': chatId,
          'lastActiveInChat': FieldValue.serverTimestamp(),
        });

        // Set in notification service
        await NotificationService.setUserActiveChatId(currentUserId, chatId);
      }

      // Mark messages as read with cooldown
      await markMessagesAsReadEnhanced(chatId: chatId);

      // Update last activity
      await _updateLastActivity(chatId);

      // Check for auto-read receipts
      await checkAndUpdateMessageStatuses();

      print('✅ Chat screen entry handled');
    } catch (e) {
      print('❌ Error handling chat screen entry: $e');
    }
  }

  // RESTORED: Check if partner is actively using the app
  Future<bool> isPartnerActiveInApp(String partnerId) async {
    try {
      // Check online status using presence service
      final isOnline = await PresenceService.instance.isUserOnline(partnerId);

      if (!isOnline) return false;

      // Check last seen time
      final lastSeen = await PresenceService.instance.getUserLastSeen(
        partnerId,
      );

      if (lastSeen != null) {
        final timeSinceLastSeen = DateTime.now().difference(lastSeen);
        // Consider active if last seen within 30 seconds
        return timeSinceLastSeen.inSeconds <= 30;
      }

      return false;
    } catch (e) {
      print('❌ Error checking partner activity: $e');
      return false;
    }
  }

  // RESTORED: Get notification statistics
  Future<Map<String, dynamic>> getNotificationStats() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return {};

      final userDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();

      if (!userDoc.exists) return {};

      final userData = userDoc.data() as Map<String, dynamic>;

      return {
        'totalUnreadMessages': userData['totalUnreadMessages'] ?? 0,
        'unreadChats': userData['unreadChats'] ?? {},
        'notificationEnabled': userData['notificationEnabled'] ?? true,
        'oneSignalPlayerId': userData['oneSignalPlayerId'],
        'activeChatId': userData['activeChatId'],
        'isAppInBackground': userData['isAppInBackground'] ?? false,
      };
    } catch (e) {
      print('❌ Error getting notification stats: $e');
      return {};
    }
  }

  Future<bool> sendTextMessageWithReadReceipts({
    required String message,
    String? chatId,
  }) async {
    try {
      // First send the message normally
      final success = await sendTextMessage(message: message, chatId: chatId);

      if (success && _activeChatId != null) {
        // Check if partner is currently active in this chat
        final partnerInfo = await getPartnerInfo(
          FirebaseService.currentUserId!,
        );
        if (partnerInfo != null) {
          final partnerId = partnerInfo['partnerId'] as String;

          // Check partner's active chat
          final partnerDoc =
              await FirebaseService.usersCollection.doc(partnerId).get();
          if (partnerDoc.exists) {
            final partnerData = partnerDoc.data() as Map<String, dynamic>;
            final partnerActiveChat = partnerData['activeChatId'] as String?;

            // If partner is in this chat, their messages should be marked as read
            if (partnerActiveChat == _activeChatId) {
              await markMessagesAsReadEnhanced(chatId: _activeChatId);
            }
          }
        }
      }

      return success;
    } catch (e) {
      print('❌ Error sending message with read receipts: $e');
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

    // Clear caches and cooldown maps
    _typingStatus.clear();
    _messageCache.clear();
    _lastReadMarkTime.clear();
    _lastPartnerInfoCheck.clear();
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
      'readMarkCooldowns': _lastReadMarkTime.length,
      'partnerInfoCooldowns': _lastPartnerInfoCheck.length,
    };
  }

  Future<void> checkForMissedMessages() async {
    try {
      print('🔍 Checking for missed messages...');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null || _activeChatId == null) {
        print('⚠️ No user ID or active chat for missed messages check');
        return;
      }

      // Get the last time user checked messages
      final userDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data() as Map<String, dynamic>;
      final lastReadData = userData['lastReadAt'] as Map<String, dynamic>?;
      final lastReadTimestamp = lastReadData?[_activeChatId] as Timestamp?;

      if (lastReadTimestamp == null) {
        print('⚠️ No last read timestamp found');
        return;
      }

      final lastReadTime = lastReadTimestamp.toDate();

      // Query messages received after last read time
      final missedMessagesQuery =
          await FirebaseService.getMessagesCollection(_activeChatId!)
              .where('timestamp', isGreaterThan: lastReadTimestamp)
              .where('senderId', isNotEqualTo: currentUserId)
              .where('isDeleted', isEqualTo: false)
              .orderBy('timestamp', descending: false)
              .get();

      final missedCount = missedMessagesQuery.docs.length;

      if (missedCount > 0) {
        print(
          '📨 Found $missedCount missed messages since ${lastReadTime.toString()}',
        );

        // Mark them as read
        await markMessagesAsReadEnhanced(chatId: _activeChatId);

        // Clear any notifications for this chat
        await NotificationService.clearUnreadCount(
          currentUserId,
          _activeChatId!,
        );

        // Refresh the message stream to ensure UI updates
        await refreshMessagesStream(chatId: _activeChatId);
      } else {
        print('✅ No missed messages found');
      }

      // Update last activity
      await _updateLastActivity(_activeChatId!);
    } catch (e) {
      print('❌ Error checking for missed messages: $e');
    }
  }

  // Add this helper method to ChatService if not already present:
  Future<int> getMissedMessageCount() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null || _activeChatId == null) return 0;

      final userDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();
      if (!userDoc.exists) return 0;

      final userData = userDoc.data() as Map<String, dynamic>;
      final unreadChats = userData['unreadChats'] as Map<String, dynamic>?;

      if (unreadChats == null) return 0;

      final unreadCount = unreadChats[_activeChatId] as int? ?? 0;
      return unreadCount;
    } catch (e) {
      print('❌ Error getting missed message count: $e');
      return 0;
    }
  }

  // Add these methods to your ChatService class

// Get favorite chats for current user
Future<List<String>> getFavoriteChats() async {
  try {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return [];

    final userDoc = await FirebaseService.usersCollection
        .doc(currentUserId)
        .get();

    if (!userDoc.exists) return [];

    final data = userDoc.data() as Map<String, dynamic>;
    return List<String>.from(data['favoriteChats'] ?? []);
  } catch (e) {
    print('❌ Error getting favorite chats: $e');
    return [];
  }
}

// Add chat to favorites
Future<bool> addToFavorites(String chatId) async {
  try {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return false;

    final userRef = FirebaseService.usersCollection.doc(currentUserId);
    
    await userRef.update({
      'favoriteChats': FieldValue.arrayUnion([chatId])
    });

    return true;
  } catch (e) {
    print('❌ Error adding to favorites: $e');
    return false;
  }
}

// Remove chat from favorites
Future<bool> removeFromFavorites(String chatId) async {
  try {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return false;

    final userRef = FirebaseService.usersCollection.doc(currentUserId);
    
    await userRef.update({
      'favoriteChats': FieldValue.arrayRemove([chatId])
    });

    return true;
  } catch (e) {
    print('❌ Error removing from favorites: $e');
    return false;
  }
}

// Check if chat is favorited
Future<bool> isChatFavorited(String chatId) async {
  try {
    final favoriteChats = await getFavoriteChats();
    return favoriteChats.contains(chatId);
  } catch (e) {
    print('❌ Error checking if chat is favorited: $e');
    return false;
  }
}


// Get partner user stream for real-time updates
Stream<UserModel?> getPartnerUserStream(String currentUserId) {
  return getPartnerInfo(currentUserId).asStream().asyncExpand((partnerInfo) {
    if (partnerInfo == null) return Stream.value(null);
    
    final partnerId = partnerInfo['partnerId'] as String;
    
    return FirebaseService.usersCollection
        .doc(partnerId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          
          final data = snapshot.data() as Map<String, dynamic>;
          return UserModel.fromMap(data, snapshot.id);
        });
  }).handleError((error) {
    print('❌ Partner user stream error: $error');
    return null;
  });
}

// Add these methods to your ChatService class

// Toggle message favorite status
Future<bool> toggleMessageFavorite(String chatId, String messageId) async {
  try {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return false;

    final messageRef = FirebaseService.getMessagesCollection(chatId).doc(messageId);
    final messageDoc = await messageRef.get();
    
    if (!messageDoc.exists) return false;

    final messageData = messageDoc.data() as Map<String, dynamic>;
    List<String> favoritedBy = List<String>.from(messageData['favoritedBy'] ?? []);
    
    bool isFavorited = favoritedBy.contains(currentUserId);
    
    if (isFavorited) {
      // Remove from favorites
      favoritedBy.remove(currentUserId);
    } else {
      // Add to favorites
      favoritedBy.add(currentUserId);
    }
    
    await messageRef.update({
      'favoritedBy': favoritedBy,
      'isFavorited': favoritedBy.isNotEmpty,
    });

    print('✅ Message favorite toggled: ${!isFavorited}');
    return true;
  } catch (e) {
    print('❌ Error toggling message favorite: $e');
    return false;
  }
}

// Check if message is favorited by current user
Future<bool> isMessageFavorited(String chatId, String messageId) async {
  try {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return false;

    final messageDoc = await FirebaseService.getMessagesCollection(chatId).doc(messageId).get();
    
    if (!messageDoc.exists) return false;

    final messageData = messageDoc.data() as Map<String, dynamic>;
    final favoritedBy = List<String>.from(messageData['favoritedBy'] ?? []);
    
    return favoritedBy.contains(currentUserId);
  } catch (e) {
    print('❌ Error checking message favorite status: $e');
    return false;
  }
}

// Get all favorited messages for current user
Future<List<MessageModel>> getFavoritedMessages() async {
  try {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return [];

    // Get all chats where user is participant
    final chatsQuery = await FirebaseService.chatsCollection
        .where('participants', arrayContains: currentUserId)
        .get();

    List<MessageModel> favoritedMessages = [];

    // For each chat, get favorited messages
    for (final chatDoc in chatsQuery.docs) {
      final chatId = chatDoc.id;
      
      final messagesQuery = await FirebaseService.getMessagesCollection(chatId)
          .where('favoritedBy', arrayContains: currentUserId)
          .orderBy('timestamp', descending: true)
          .get();

      for (final messageDoc in messagesQuery.docs) {
        final message = MessageModel.fromFirestore(messageDoc);
        favoritedMessages.add(message);
      }
    }

    // Sort all favorited messages by timestamp
    favoritedMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    print('✅ Found ${favoritedMessages.length} favorited messages');
    return favoritedMessages;
  } catch (e) {
    print('❌ Error getting favorited messages: $e');
    return [];
  }
}

// Get favorited messages stream for real-time updates
Stream<List<MessageModel>> getFavoritedMessagesStream() {
  final currentUserId = FirebaseService.currentUserId;
  if (currentUserId == null) return Stream.value([]);

  return FirebaseService.chatsCollection
      .where('participants', arrayContains: currentUserId)
      .snapshots()
      .asyncMap((chatsSnapshot) async {
        List<MessageModel> allFavoritedMessages = [];

        for (final chatDoc in chatsSnapshot.docs) {
          final chatId = chatDoc.id;
          
          try {
            final messagesQuery = await FirebaseService.getMessagesCollection(chatId)
                .where('favoritedBy', arrayContains: currentUserId)
                .get();

            for (final messageDoc in messagesQuery.docs) {
              final message = MessageModel.fromFirestore(messageDoc);
              allFavoritedMessages.add(message);
            }
          } catch (e) {
            print('❌ Error getting favorited messages for chat $chatId: $e');
          }
        }

        // Sort by timestamp
        allFavoritedMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return allFavoritedMessages;
      });
}
}
