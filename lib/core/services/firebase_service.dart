import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:onlyus/core/services/pressence_service.dart';

class FirebaseService {
  // Singleton instance
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();
  FirebaseService._();

  // Firebase instances
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;

  // Collection references
  static CollectionReference<Map<String, dynamic>> get usersCollection =>
      firestore.collection('users');
  static CollectionReference<Map<String, dynamic>> get chatsCollection =>
      firestore.collection('chats');
  static CollectionReference<Map<String, dynamic>> get messagesCollection =>
      firestore.collection('messages');

  // Initialize Firebase services
  static Future<void> initialize() async {
    try {
      // Enable Firestore offline persistence
      await firestore.enablePersistence(
        const PersistenceSettings(synchronizeTabs: true),
      );

      // Configure Firestore settings for better real-time performance
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // Initialize presence service
      await PresenceService.instance.initialize();

      print('✅ Firebase services initialized successfully');
    } catch (e) {
      print('❌ Error initializing Firebase: $e');
    }
  }

  // Get current user ID
  static String? get currentUserId => auth.currentUser?.uid;

  // Get current user
  static User? get currentUser => auth.currentUser;

  // Check if user is authenticated
  static bool get isAuthenticated => currentUser != null;

  // Get user document reference
  static DocumentReference? get currentUserDoc {
    final userId = currentUserId;
    if (userId == null) return null;
    return usersCollection.doc(userId);
  }

  // Generate unique message ID
  static String generateMessageId() {
    return messagesCollection.doc().id;
  }

  // Create or update user document
  static Future<void> createOrUpdateUser({
    required String uid,
    required String email,
    required String displayName,
    String? photoURL,
  }) async {
    try {
      final userDoc = usersCollection.doc(uid);
      final userData = {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoURL': photoURL,
        'isOnline': true, // Will be managed by PresenceService
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'oneSignalPlayerId': null, // Will be updated by NotificationService
        'notificationEnabled': true,
      };

      await userDoc.set(userData, SetOptions(merge: true));

      // Initialize presence for this user
      await PresenceService.instance.setUserOnline();

      // Update presence info
      await PresenceService.instance.updateUserInfo(
        displayName: displayName,
        photoURL: photoURL,
      );

      print('✅ User document created/updated for $displayName');
    } catch (e) {
      print('❌ Error creating/updating user: $e');
      rethrow;
    }
  }

  // Update user online status (now handled by PresenceService)
  static Future<void> updateUserOnlineStatus(bool isOnline) async {
    try {
      if (isOnline) {
        await PresenceService.instance.setUserOnline();
      } else {
        await PresenceService.instance.setUserOffline();
      }
    } catch (e) {
      print('❌ Error updating online status: $e');
    }
  }

  // Get user stream with real-time presence data
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getUserStream(String userId) {
    return usersCollection.doc(userId).snapshots();
  }

  // Get user presence stream from Realtime Database
  static Stream<Map<String, dynamic>?> getUserPresenceStream(String userId) {
    return PresenceService.instance.getUserPresenceStream(userId);
  }

  // Get combined user data stream (Firestore + Presence)
  static Stream<Map<String, dynamic>?> getCombinedUserStream(String userId) {
    // Combine Firestore user data with real-time presence data
    return getUserStream(userId).asyncMap((firestoreDoc) async {
      if (!firestoreDoc.exists) return null;

      final firestoreData = firestoreDoc.data() as Map<String, dynamic>;

      try {
        // Get real-time presence data
        final isOnline = await PresenceService.instance.isUserOnline(userId);
        final lastSeen = await PresenceService.instance.getUserLastSeen(userId);

        // Merge data
        return {
          ...firestoreData,
          'isOnline': isOnline,
          'realtimeLastSeen': lastSeen?.millisecondsSinceEpoch,
        };
      } catch (e) {
        print('❌ Error getting presence data for $userId: $e');
        return firestoreData;
      }
    });
  }

  // Enhanced get or create chat room between two users
  static Future<String> getOrCreateChatRoom(String otherUserId) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Create chat ID by sorting user IDs
      final List<String> userIds = [currentUserId, otherUserId];
      userIds.sort();
      final chatId = '${userIds[0]}_${userIds[1]}';

      final chatDoc = chatsCollection.doc(chatId);

      try {
        // Try to read the chat first
        final chatSnapshot = await chatDoc.get();

        if (chatSnapshot.exists) {
          print('✅ Chat room already exists: $chatId');
          return chatId;
        }
      } catch (e) {
        // If we can't read it, it probably doesn't exist, so we'll create it
        print('Chat doesn\'t exist or can\'t read, creating new one: $e');
      }

      // Create new chat room with enhanced structure
      try {
        await chatDoc.set({
          'id': chatId,
          'chatId': chatId,
          'participants': userIds,
          'participantNames': {}, // Will be populated later
          'participantPhotos': {}, // Will be populated later
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageSender': '',
          'lastMessageSenderId': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'typingUsers': {}, // For real-time typing indicators
          'isActive': true,
          'messageCount': 0,
        });

        print('✅ Created new chat room: $chatId');

        // Update with participant details after creation
        await _updateChatParticipantDetails(chatId, userIds);
      } catch (createError) {
        // If creation fails, try to get it again (might have been created by the other user)
        print('Creation failed, trying to get existing chat: $createError');
        final retrySnapshot = await chatDoc.get();
        if (retrySnapshot.exists) {
          print('✅ Found existing chat room: $chatId');
          return chatId;
        }
        throw createError;
      }

      return chatId;
    } catch (e) {
      print('❌ Error getting/creating chat room: $e');
      rethrow;
    }
  }

  // Helper method to update chat participant details
  static Future<void> _updateChatParticipantDetails(
    String chatId,
    List<String> userIds,
  ) async {
    try {
      final Map<String, String> participantNames = {};
      final Map<String, String> participantPhotos = {};

      for (final userId in userIds) {
        try {
          final userDoc = await usersCollection.doc(userId).get();
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            participantNames[userId] = userData['displayName'] ?? 'Unknown';
            participantPhotos[userId] = userData['photoURL'] ?? '';
          }
        } catch (e) {
          print('❌ Error fetching user data for $userId: $e');
          participantNames[userId] = 'Unknown';
          participantPhotos[userId] = '';
        }
      }

      // Update the chat with participant details
      await chatsCollection.doc(chatId).update({
        'participantNames': participantNames,
        'participantPhotos': participantPhotos,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Updated chat participant details for $chatId');
    } catch (e) {
      print('❌ Error updating chat participant details: $e');
      // Don't rethrow - this is not critical for chat functionality
    }
  }

  // Enhanced send message with better real-time support
  static Future<void> sendMessage({
  required String chatId,
  required String message,
  String? imageUrl,
  required String senderId,
  required String senderName,
  String? messageId,
}) async {
  try {
    print('🔍 FirebaseService.sendMessage starting...');
    print('📋 Chat ID: $chatId');
    print('📋 Sender ID: $senderId');
    
    // First, verify the chat exists
    final chatDoc = await chatsCollection.doc(chatId).get();
    if (!chatDoc.exists) {
      print('❌ Chat document does not exist: $chatId');
      throw Exception('Chat does not exist');
    }
    print('✅ Chat document exists');
    
    // Verify user is a participant
    final chatData = chatDoc.data() as Map<String, dynamic>;
    final participants = List<String>.from(chatData['participants'] ?? []);
    if (!participants.contains(senderId)) {
      print('❌ User $senderId is not a participant in chat $chatId');
      print('📋 Participants: $participants');
      throw Exception('User is not a participant in this chat');
    }
    print('✅ User is a participant');
    
    final docId = messageId ?? generateMessageId();
    
    final messageData = {
      'id': docId,
      'chatId': chatId,
      'message': message,
      'imageUrl': imageUrl,
      'senderId': senderId,
      'senderName': senderName,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'isDelivered': true,
      'deliveryStatus': 'sent',
      'type': imageUrl != null ? 'image' : 'text',
      'reactions': {},
      'editedAt': null,
      'isDeleted': false,
    };

    print('🔍 Creating message document...');
    // Add message to messages collection with specific ID
    await messagesCollection.doc(docId).set(messageData);
    print('✅ Message document created');

    print('🔍 Updating chat room...');
    // Update chat room with last message info and increment message count
    await chatsCollection.doc(chatId).update({
      'lastMessage': imageUrl != null ? '📷 Photo' : message,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSender': senderName,
      'lastMessageSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
      'messageCount': FieldValue.increment(1),
    });
    print('✅ Chat room updated');

    print('✅ Message sent successfully with ID: $docId');
  } catch (e, stackTrace) {
    print('❌ Error in FirebaseService.sendMessage: $e');
    print('📋 Stack trace: $stackTrace');
    rethrow;
  }
}

  // Mark messages as read with better batch handling
  static Future<void> markMessagesAsRead(String chatId, String userId) async {
    try {
      final unreadMessages = await messagesCollection
          .where('chatId', isEqualTo: chatId)
          .where('senderId', isNotEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      if (unreadMessages.docs.isEmpty) {
        print('✅ No unread messages to mark');
        return;
      }

      final batch = firestore.batch();

      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'readBy': userId,
        });
      }

      await batch.commit();
      print('✅ Marked ${unreadMessages.docs.length} messages as read');
    } catch (e) {
      print('❌ Error marking messages as read: $e');
    }
  }

  // Enhanced messages stream with better query optimization
  static Stream<QuerySnapshot<Map<String, dynamic>>> getMessagesStream(String chatId) {
    return messagesCollection
        .where('chatId', isEqualTo: chatId)
        .where('isDeleted', isEqualTo: false) // Exclude deleted messages
        .orderBy('timestamp', descending: true)
        .limit(100) // Increased for better UX, adjust as needed
        .snapshots();
  }

  // Get chat stream for typing indicators and chat metadata
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getChatStream(String chatId) {
    return chatsCollection.doc(chatId).snapshots();
  }

  // Update typing status in chat
  static Future<void> updateTypingStatus({
    required String chatId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      await chatsCollection.doc(chatId).update({
        'typingUsers.$userId': isTyping,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error updating typing status: $e');
      throw e;
    }
  }

  // Delete message (soft delete)
  static Future<void> deleteMessage(String messageId) async {
    try {
      await messagesCollection.doc(messageId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'message': 'This message was deleted',
        'imageUrl': null,
      });
      print('✅ Message deleted successfully');
    } catch (e) {
      print('❌ Error deleting message: $e');
      throw e;
    }
  }

  // Get unread message count for a chat
  static Future<int> getUnreadMessageCount(String chatId, String userId) async {
    try {
      final unreadMessages = await messagesCollection
          .where('chatId', isEqualTo: chatId)
          .where('senderId', isNotEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .where('isDeleted', isEqualTo: false)
          .get();

      return unreadMessages.docs.length;
    } catch (e) {
      print('❌ Error getting unread message count: $e');
      return 0;
    }
  }

  // Check if user has partner
  static Future<String?> getUserPartnerId(String userId) async {
    try {
      final userDoc = await usersCollection.doc(userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        return userData['partnerId'] as String?;
      }
      return null;
    } catch (e) {
      print('❌ Error getting user partner ID: $e');
      return null;
    }
  }

  // Connect two users as partners
  static Future<void> connectPartners(String userId1, String userId2) async {
    try {
      final batch = firestore.batch();

      // Update both users with partner IDs
      batch.update(usersCollection.doc(userId1), {
        'partnerId': userId2,
        'connectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(usersCollection.doc(userId2), {
        'partnerId': userId1,
        'connectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      print('✅ Partners connected successfully');
    } catch (e) {
      print('❌ Error connecting partners: $e');
      throw e;
    }
  }

  // App lifecycle methods
  static Future<void> onAppResumed() async {
    try {
      await PresenceService.instance.setUserOnline();
      print('✅ App resumed - user set online');
    } catch (e) {
      print('❌ Error handling app resume: $e');
    }
  }

  static Future<void> onAppPaused() async {
    try {
      await PresenceService.instance.setUserOffline();
      print('✅ App paused - user set offline');
    } catch (e) {
      print('❌ Error handling app pause: $e');
    }
  }

  // Enhanced sign out with better cleanup
  static Future<void> signOut() async {
    try {
      // Clean up presence service
      await PresenceService.instance.signOut();

      // Sign out from Firebase Auth
      await auth.signOut();

      print('✅ User signed out successfully');
    } catch (e) {
      print('❌ Error signing out: $e');
      rethrow;
    }
  }

  // Connection health check
  static Future<bool> checkConnectionHealth() async {
    try {
      await usersCollection.limit(1).get().timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      print('❌ Firebase connection health check failed: $e');
      return false;
    }
  }

  // Batch operations for better performance
  static WriteBatch createBatch() {
    return firestore.batch();
  }

  // Get server timestamp
  static FieldValue get serverTimestamp => FieldValue.serverTimestamp();
}