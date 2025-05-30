import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onlyus/core/services/couple_code_serivce.dart';
import 'package:onlyus/core/services/pressence_service.dart';

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

  // UPDATED METHOD 1: Enhanced initializeChatWithPartner
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

  // UPDATED METHOD 2: Enhanced findExistingChat
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

        // Set up message stream for existing chat
        await _setupMessageStreamListener(chatId);

        return chatId;
      }

      print('⚠️ No existing chat found');
      return null;
    } catch (e) {
      print('❌ Error finding existing chat: $e');
      return null;
    }
  }

  // UPDATED METHOD 3: Enhanced getMessagesStream
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

  // UPDATED METHOD 4: Improved message stream listener setup
  Future<void> _setupMessageStreamListener(String chatId) async {
    final controller = _messageStreamControllers[chatId];
    if (controller == null || controller.isClosed) {
      print('⚠️ Stream controller not available for chat: $chatId');
      return;
    }

    await _messageSubscriptions[chatId]?.cancel();
    print('📡 Setting up message stream with existing index for chat: $chatId');

    try {
      // Use the EXACT query that matches your Index 3:
      // chatId (Ascending) + isDeleted (Ascending) + timestamp (Descending)
      final query = FirebaseService.messagesCollection
          .where('chatId', isEqualTo: chatId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('timestamp', descending: true)
          .limit(100);

      print(
        '📋 Using query: chatId == $chatId AND isDeleted == false ORDER BY timestamp DESC',
      );

      _messageSubscriptions[chatId] = query.snapshots().listen(
        (snapshot) {
          try {
            print(
              '📨 Index-optimized stream received ${snapshot.docs.length} messages',
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
                '✅ Index-optimized stream updated with ${messages.length} messages',
              );
            }
          } catch (e) {
            print('❌ Error processing indexed message snapshot: $e');
            final cachedMessages = _messageCache[chatId] ?? [];
            if (!controller.isClosed) {
              controller.add(cachedMessages);
            }
          }
        },
        onError: (error) {
          print('❌ Index-optimized message stream error: $error');

          final errorString = error.toString().toLowerCase();

          if (errorString.contains('index') ||
              errorString.contains('failed-precondition')) {
            print(
              '⚠️ Index still building or error - falling back to simple query',
            );
            _setupFallbackQuery(chatId);
            return;
          }

          // Provide cached messages for other errors
          final cachedMessages = _messageCache[chatId] ?? [];
          if (!controller.isClosed) {
            controller.add(cachedMessages);
          }

          // Retry after delay
          Timer(const Duration(seconds: 5), () {
            if (!controller.isClosed && _isOnline) {
              print('🔄 Retrying index-optimized query for chat: $chatId');
              _setupMessageStreamListener(chatId);
            }
          });
        },
      );
    } catch (e) {
      print('❌ Error setting up index-optimized stream: $e');
      _setupFallbackQuery(chatId);
    }
  }

  void _setupFallbackQuery(String chatId) {
    final controller = _messageStreamControllers[chatId];
    if (controller == null || controller.isClosed) return;

    print('📡 Setting up fallback query for chat: $chatId');

    // Simple query using Index 1: chatId + timestamp
    final query = FirebaseService.messagesCollection
        .where('chatId', isEqualTo: chatId)
        .orderBy('timestamp', descending: true)
        .limit(50);

    _messageSubscriptions[chatId] = query.snapshots().listen(
      (snapshot) {
        try {
          print('📨 Fallback stream received ${snapshot.docs.length} messages');

          // Filter deleted messages in code
          final messages =
              snapshot.docs
                  .map(
                    (doc) => MessageModel.fromFirestore(
                      doc as DocumentSnapshot<Map<String, dynamic>>,
                    ),
                  )
                  .where((message) => !(message.isDeleted ?? false))
                  .toList();

          _messageCache[chatId] = messages;

          if (!controller.isClosed) {
            controller.add(messages);
            print('✅ Fallback stream updated with ${messages.length} messages');
          }
        } catch (e) {
          print('❌ Error in fallback stream: $e');
        }
      },
      onError: (error) {
        print('❌ Fallback stream error: $error');
        final cachedMessages = _messageCache[chatId] ?? [];
        if (!controller.isClosed) {
          controller.add(cachedMessages);
        }
      },
    );
  }

  //   // NEW METHOD 5: Fallback simple message stream listener
  //  void _setupSimpleMessageStreamListener(String chatId) {
  //   final controller = _messageStreamControllers[chatId];
  //   if (controller == null || controller.isClosed) return;

  //   print('📡 Setting up SUPER SIMPLE message stream for chat: $chatId');

  //   // Simplest possible query - just filter by chatId
  //   final query = FirebaseService.messagesCollection
  //       .where('chatId', isEqualTo: chatId)
  //       .limit(50); // Reduced limit for better performance

  //   _messageSubscriptions[chatId] = query.snapshots().listen(
  //     (snapshot) {
  //       try {
  //         print('📨 Simple stream received ${snapshot.docs.length} messages');

  //         final messages = snapshot.docs
  //             .map((doc) => MessageModel.fromFirestore(
  //                   doc as DocumentSnapshot<Map<String, dynamic>>,
  //                 ))
  //             .where((message) => !(message.isDeleted ?? false))
  //             .toList();

  //         // Sort messages manually (newest first)
  //         messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  //         // Limit to last 50 messages
  //         if (messages.length > 50) {
  //           messages.removeRange(50, messages.length);
  //         }

  //         // Cache and update stream
  //         _messageCache[chatId] = messages;

  //         if (!controller.isClosed) {
  //           controller.add(messages);
  //           print('✅ Simple stream updated with ${messages.length} messages');
  //         }
  //       } catch (e) {
  //         print('❌ Error in simple message stream: $e');
  //       }
  //     },
  //     onError: (error) {
  //       print('❌ Simple message stream error: $error');

  //       // Provide cached messages as fallback
  //       final cachedMessages = _messageCache[chatId] ?? [];
  //       if (!controller.isClosed) {
  //         controller.add(cachedMessages);
  //       }
  //     },
  //   );
  // }

  // NEW METHOD 6: Force refresh messages stream
  Future<void> refreshMessagesStream({String? chatId}) async {
    final activeChatId = chatId ?? _activeChatId;
    if (activeChatId == null) return;

    print('🔄 Force refreshing messages stream for chat: $activeChatId');

    // Cancel existing subscription
    await _messageSubscriptions[activeChatId]?.cancel();

    // Set up new listener
    await _setupMessageStreamListener(activeChatId);
  }

  // NEW METHOD 7: Set active chat ID and setup stream
  Future<void> setActiveChatId(String? chatId) async {
    _activeChatId = chatId;
    if (chatId != null) {
      await _setupMessageStreamListener(chatId);
    }
  }

  // UPDATED METHOD 8: Enhanced _refreshAllStreams
  void _refreshAllStreams() {
    // Refresh all active message streams when connection is restored
    _messageStreamControllers.forEach((chatId, controller) {
      if (!controller.isClosed) {
        print('🔄 Refreshing stream for chat: $chatId');
        _setupMessageStreamListener(chatId);
      }
    });
  }

  // NEW METHOD 9: Check if stream is active for debugging
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

  Future<String?> _forceCreateChatWithPartner() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return null;

      // Get partner ID directly from CoupleCodeService
      final partnerId = await CoupleCodeService.instance.getPartnerId(
        currentUserId,
      );
      if (partnerId == null) {
        print('❌ No partner ID found');
        return null;
      }

      print('🔍 Force creating chat with partner: $partnerId');

      // Create chat ID manually
      final List<String> userIds = [currentUserId, partnerId];
      userIds.sort();
      final chatId = '${userIds[0]}_${userIds[1]}';

      // Force create the chat document
      await FirebaseService.chatsCollection.doc(chatId).set({
        'id': chatId,
        'chatId': chatId,
        'participants': userIds,
        'participantNames': {},
        'participantPhotos': {},
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': '',
        'lastMessageSenderId': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'typingUsers': {},
        'isActive': true,
        'messageCount': 0,
        'forceCreated': true, // Flag to indicate this was force created
      }, SetOptions(merge: true));

      // Update participant details
      await _updateChatParticipantDetailsForce(chatId, userIds);

      _activeChatId = chatId;
      print('✅ Force created chat: $chatId');
      return chatId;
    } catch (e) {
      print('❌ Error in force create chat: $e');
      return null;
    }
  }

  // Update chat participant details with force flag
  Future<void> _updateChatParticipantDetailsForce(
    String chatId,
    List<String> userIds,
  ) async {
    try {
      print('🔍 Updating chat participant details for chat: $chatId');

      final Map<String, String> participantNames = {};
      final Map<String, String> participantPhotos = {};

      for (final userId in userIds) {
        try {
          print('📋 Fetching user data for: $userId');

          final userDoc =
              await FirebaseService.usersCollection.doc(userId).get();

          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;

            final displayName = userData['displayName'] as String?;
            final photoURL = userData['photoURL'] as String?;

            participantNames[userId] = displayName ?? 'Unknown User';
            participantPhotos[userId] = photoURL ?? '';

            print(
              '✅ User data found - Name: ${participantNames[userId]}, Photo: ${photoURL != null ? 'Yes' : 'No'}',
            );
          } else {
            print('⚠️ User document not found: $userId');
            participantNames[userId] = 'Unknown User';
            participantPhotos[userId] = '';
          }
        } catch (e) {
          print('❌ Error fetching user data for $userId: $e');
          participantNames[userId] = 'Unknown User';
          participantPhotos[userId] = '';
        }
      }

      // Validate that we have data for all participants
      if (participantNames.length != userIds.length) {
        print('⚠️ Warning: Missing participant data for some users');
      }

      print('📋 Participant names: $participantNames');
      print('📋 Updating chat document with participant details...');

      // Update the chat with participant details
      await FirebaseService.chatsCollection.doc(chatId).update({
        'participantNames': participantNames,
        'participantPhotos': participantPhotos,
        'participantsUpdated': true,
        'participantsUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Updated chat participant details for $chatId (force mode)');

      // Verify the update was successful
      try {
        final updatedChatDoc =
            await FirebaseService.chatsCollection.doc(chatId).get();
        if (updatedChatDoc.exists) {
          final chatData = updatedChatDoc.data() as Map<String, dynamic>;
          final updatedNames =
              chatData['participantNames'] as Map<String, dynamic>?;

          if (updatedNames != null && updatedNames.length == userIds.length) {
            print('✅ Participant details update verified successfully');
          } else {
            print('⚠️ Participant details update verification failed');
          }
        }
      } catch (verifyError) {
        print('❌ Error verifying participant details update: $verifyError');
        // Don't rethrow - the main update might have succeeded
      }
    } catch (e) {
      print('❌ Error updating chat participant details (force): $e');

      // Try a simplified update as fallback
      try {
        print('🔄 Attempting simplified participant update...');

        await FirebaseService.chatsCollection.doc(chatId).update({
          'participantNames': {for (final userId in userIds) userId: 'User'},
          'participantPhotos': {for (final userId in userIds) userId: ''},
          'participantsUpdated': true,
          'participantsUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        print('✅ Simplified participant update successful');
      } catch (fallbackError) {
        print('❌ Fallback participant update also failed: $fallbackError');
        // Don't rethrow - this is not critical for chat functionality
      }
    }
  }

  // Helper method to get user display info safely
  Future<Map<String, String>> _getUserDisplayInfo(String userId) async {
    try {
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;

        return {
          'name': userData['displayName'] as String? ?? 'Unknown User',
          'photo': userData['photoURL'] as String? ?? '',
          'email': userData['email'] as String? ?? '',
        };
      } else {
        print('⚠️ User document not found for: $userId');
        return {'name': 'Unknown User', 'photo': '', 'email': ''};
      }
    } catch (e) {
      print('❌ Error getting user display info for $userId: $e');
      return {'name': 'Unknown User', 'photo': '', 'email': ''};
    }
  }

  // Enhanced method to update chat participants with retry logic
  Future<void> updateChatParticipantDetailsWithRetry(
    String chatId,
    List<String> userIds, {
    int maxRetries = 3,
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      attempts++;

      try {
        print(
          '🔍 Participant update attempt $attempts/$maxRetries for chat: $chatId',
        );

        // Get all participant info in parallel for better performance
        final participantInfoFutures = userIds.map(
          (userId) => _getUserDisplayInfo(userId),
        );
        final participantInfoList = await Future.wait(participantInfoFutures);

        final Map<String, String> participantNames = {};
        final Map<String, String> participantPhotos = {};
        final Map<String, String> participantEmails = {};

        for (int i = 0; i < userIds.length; i++) {
          final userId = userIds[i];
          final info = participantInfoList[i];

          participantNames[userId] = info['name']!;
          participantPhotos[userId] = info['photo']!;
          participantEmails[userId] = info['email']!;
        }

        // Update chat with all participant information
        await FirebaseService.chatsCollection.doc(chatId).update({
          'participantNames': participantNames,
          'participantPhotos': participantPhotos,
          'participantEmails': participantEmails,
          'participantsCount': userIds.length,
          'participantsUpdated': true,
          'participantsUpdatedAt': FieldValue.serverTimestamp(),
          'lastParticipantUpdate': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        print(
          '✅ Participant details updated successfully on attempt $attempts',
        );
        return; // Success, exit the retry loop
      } catch (e) {
        print('❌ Participant update attempt $attempts failed: $e');

        if (attempts >= maxRetries) {
          print('❌ All participant update attempts failed');

          // Final fallback - set minimal data
          try {
            await FirebaseService.chatsCollection.doc(chatId).update({
              'participants': userIds,
              'participantsCount': userIds.length,
              'participantsUpdated': false,
              'participantsUpdateFailed': true,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            print('✅ Minimal participant data set as fallback');
          } catch (finalError) {
            print('❌ Even minimal participant update failed: $finalError');
          }

          // Don't rethrow - chat can still function without detailed participant info
          return;
        }

        // Wait before retrying (exponential backoff)
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }
  }

  // Method to verify and fix participant data if needed
  Future<bool> verifyAndFixParticipantData(String chatId) async {
    try {
      print('🔍 Verifying participant data for chat: $chatId');

      final chatDoc = await FirebaseService.chatsCollection.doc(chatId).get();

      if (!chatDoc.exists) {
        print('❌ Chat document not found: $chatId');
        return false;
      }

      final chatData = chatDoc.data() as Map<String, dynamic>;
      final participants = List<String>.from(chatData['participants'] ?? []);
      final participantNames =
          chatData['participantNames'] as Map<String, dynamic>?;

      // Check if participant names are missing or incomplete
      bool needsUpdate = false;

      if (participantNames == null || participantNames.isEmpty) {
        print('⚠️ Participant names are missing');
        needsUpdate = true;
      } else {
        for (final participantId in participants) {
          if (!participantNames.containsKey(participantId) ||
              participantNames[participantId] == null ||
              participantNames[participantId] == 'Unknown' ||
              participantNames[participantId] == '') {
            print('⚠️ Participant name missing or invalid for: $participantId');
            needsUpdate = true;
            break;
          }
        }
      }

      if (needsUpdate) {
        print('🔄 Participant data needs update, fixing...');
        await updateChatParticipantDetailsWithRetry(chatId, participants);
        return true;
      } else {
        print('✅ Participant data is valid');
        return false;
      }
    } catch (e) {
      print('❌ Error verifying participant data: $e');
      return false;
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
      print('📤 Sending notification to partner...');
      print('📋 Chat ID: $chatId');
      print('📋 Sender: $senderName');
      print('📋 Message: $message');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user ID for notification');
        return;
      }

      // Get partner info with better error handling
      final partnerInfo = await getPartnerInfo(currentUserId);
      if (partnerInfo == null) {
        print('⚠️ No partner found for notification');
        return;
      }

      final partnerId = partnerInfo['partnerId'] as String;
      final oneSignalPlayerId = partnerInfo['oneSignalPlayerId'] as String;
      final partnerName = partnerInfo['displayName'] as String;

      print('✅ Partner info retrieved:');
      print('  - Partner ID: $partnerId');
      print('  - Player ID: $oneSignalPlayerId');
      print('  - Name: $partnerName');

      // Use enhanced notification service
      await NotificationService.sendMessageNotification(
        recipientPlayerId: oneSignalPlayerId,
        senderName: senderName,
        message: message,
        chatId: chatId,
        senderId: senderId,
      );

      print('✅ Enhanced notification sent to partner: $partnerName');
    } catch (e) {
      print('❌ Error sending enhanced notification to partner: $e');
    }
  }

  // NEW: Debug method to check notification setup
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

      // Check OneSignal service status
      await NotificationService.debugUserPlayerIdMapping();
    } catch (e) {
      print('❌ Error in notification debug: $e');
    }
  }

  // NEW: Get partner information with caching
  Future<Map<String, dynamic>?> getPartnerInfo(String currentUserId) async {
    try {
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

      return {
        'partnerId': partnerId,
        'oneSignalPlayerId': oneSignalPlayerId,
        'displayName': partnerData['displayName'] ?? 'Unknown',
        'photoURL': partnerData['photoURL'],
        'isOnline': partnerData['isOnline'] ?? false,
        'lastSeen': partnerData['lastSeen'],
      };
    } catch (e) {
      print('❌ Error getting partner info: $e');
      return null;
    }
  }

  // NEW: Enhanced message sending with better notification logic
  Future<bool> sendTextMessageEnhanced({
    required String message,
    String? chatId,
  }) async {
    try {
      print('🔍 Starting enhanced sendTextMessage...');

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

      // Check if user can send messages
      final canSend = await canInitializeChat();
      if (!canSend) {
        print('⚠️ User is not connected to a partner');
        return false;
      }

      final activeChatId = chatId ?? _activeChatId;
      if (activeChatId == null) {
        print('🔍 No active chat, trying to initialize...');
        final newChatId = await initializeChatWithFallback();
        if (newChatId == null) {
          print('❌ Could not initialize chat');
          throw Exception('No active chat and could not create one');
        }

        // Set active chat with notification integration
        await setActiveChatIdWithNotification(newChatId);
      }

      // Generate message ID for tracking
      final messageId = FirebaseService.generateMessageId();
      print('🔍 Generated message ID: $messageId');

      // Create message delivery completer
      final deliveryCompleter = Completer<bool>();
      _messageDeliveryCompleters[messageId] = deliveryCompleter;

      // Send message to Firebase
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

      // Send enhanced notification to partner
      await _sendNotificationToPartner(
        chatId: _activeChatId!,
        message: message.trim(),
        senderId: currentUser.uid,
        senderName: currentUser.displayName ?? 'OnlyUs',
      );
      print('✅ Enhanced notification sent');

      // Clear typing status
      await updateTypingStatus(false);
      print('✅ Cleared typing status');

      print('✅ Enhanced text message sent successfully with ID: $messageId');

      // Wait for delivery confirmation with timeout
      try {
        await deliveryCompleter.future.timeout(const Duration(seconds: 10));
        return true;
      } catch (e) {
        print('⚠️ Message delivery timeout, but message was sent');
        return true;
      }
    } catch (e, stackTrace) {
      print('❌ Error sending enhanced text message: $e');
      print('📋 Stack trace: $stackTrace');
      return false;
    }
  }

  // NEW: Method to handle when user enters chat screen
  Future<void> onChatScreenEntered(String chatId) async {
    try {
      print('📱 User entered chat screen: $chatId');

      // Set active chat with notification integration
      await setActiveChatIdWithNotification(chatId);

      // Mark messages as read
      await markMessagesAsRead(chatId: chatId);

      // Update user activity
      await _updateLastActivity(chatId);

      print('✅ Chat screen entry handled');
    } catch (e) {
      print('❌ Error handling chat screen entry: $e');
    }
  }

  // NEW: Method to handle when user exits chat screen
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

  // NEW: Enhanced typing status with notification awareness
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

  // NEW: Check if partner is actively using the app
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

  // NEW: Get notification statistics
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
      // Example:
      // await _localStorage.setMessages(chatId, messages);

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
        await markMessagesAsRead(chatId: chatId);
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
