import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:onlyus/core/services/pressence_service.dart';
import 'dart:async';

class FirebaseService {
  // Singleton instance
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();
  FirebaseService._();

  // Firebase instances
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;
  static FirebaseDatabase get realtimeDatabase => FirebaseDatabase.instance;

  // Collection references
  static CollectionReference<Map<String, dynamic>> get usersCollection =>
      firestore.collection('users');
  static CollectionReference<Map<String, dynamic>> get chatsCollection =>
      firestore.collection('chats');

  // Connection monitoring
  static StreamSubscription<User?>? _authStateSubscription;
  static Timer? _connectionHealthCheckTimer;
  static bool _isFirestoreConnected = true;
  static bool _isRealtimeDbConnected = true;

  // Helper method to get messages subcollection
  static CollectionReference<Map<String, dynamic>> getMessagesCollection(
    String chatId,
  ) => chatsCollection.doc(chatId).collection('messages');

  // Initialize Firebase services with robust error handling
  static Future<void> initialize() async {
    try {
      print('🔍 Initializing Firebase services...');

      // Initialize Firestore with proper settings
      await _initializeFirestore();

      // Initialize Realtime Database
      await _initializeRealtimeDatabase();

      // Set up auth state monitoring
      _setupAuthStateMonitoring();

      // Start connection health monitoring
      _startConnectionHealthMonitoring();

      // Initialize presence service after Firebase is ready
      await _initializePresenceService();

      print('✅ Firebase services initialized successfully');
    } catch (e) {
      print('❌ Error initializing Firebase: $e');
      throw e;
    }
  }

  /// Initialize Firestore with production settings
  static Future<void> _initializeFirestore() async {
    try {
      // Configure Firestore settings
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // Enable network
      await firestore.enableNetwork();

      // Test connection
      await firestore
          .runTransaction((transaction) async {
            // Simple test transaction
            return null;
          })
          .timeout(const Duration(seconds: 5));

      _isFirestoreConnected = true;
      print('✅ Firestore initialized and connected');
    } catch (e) {
      _isFirestoreConnected = false;
      if (!e.toString().contains('already been set')) {
        print('⚠️ Firestore initialization warning: $e');
      }
    }
  }

  /// Initialize Realtime Database with production settings
  static Future<void> _initializeRealtimeDatabase() async {
    try {
      // Go online
      realtimeDatabase.goOnline();

      // Set persistence
      try {
        realtimeDatabase.setPersistenceEnabled(true);
        realtimeDatabase.setPersistenceCacheSizeBytes(10 * 1024 * 1024); // 10MB
      } catch (e) {
        if (!e.toString().contains('already been called')) {
          throw e;
        }
      }

      // Test connection
      final connectedRef = realtimeDatabase.ref('.info/connected');
      final snapshot = await connectedRef.get().timeout(
        const Duration(seconds: 5),
      );
      _isRealtimeDbConnected = snapshot.value as bool? ?? false;

      print(
        '✅ Realtime Database initialized. Connected: $_isRealtimeDbConnected',
      );
    } catch (e) {
      _isRealtimeDbConnected = false;
      print('⚠️ Realtime Database initialization warning: $e');
    }
  }

  /// Initialize presence service with error handling
  static Future<void> _initializePresenceService() async {
    try {
      if (currentUser != null) {
        await PresenceService.instance.initialize();
        print('✅ Presence service initialized');
      }
    } catch (e) {
      print('⚠️ Presence service initialization failed (non-critical): $e');
      // Don't throw - presence is not critical for app functionality
    }
  }

  /// Set up auth state monitoring
  static void _setupAuthStateMonitoring() {
    _authStateSubscription?.cancel();

    _authStateSubscription = auth.authStateChanges().listen(
      (User? user) async {
        if (user != null) {
          print('👤 User authenticated: ${user.uid}');

          // Initialize presence for authenticated user
          try {
            await PresenceService.instance.initialize();
          } catch (e) {
            print('⚠️ Error initializing presence for user: $e');
          }
        } else {
          print('👤 User signed out');

          // Cleanup presence
          try {
            await PresenceService.instance.signOut();
          } catch (e) {
            print('⚠️ Error cleaning up presence: $e');
          }
        }
      },
      onError: (error) {
        print('❌ Auth state error: $error');
      },
    );
  }

  /// Start connection health monitoring
  static void _startConnectionHealthMonitoring() {
    _connectionHealthCheckTimer?.cancel();

    // Start with more frequent checks, then reduce frequency
    int checkCount = 0;
    const initialInterval = Duration(seconds: 15);
    const normalInterval = Duration(seconds: 45);

    void scheduleNextCheck() {
      checkCount++;
      final interval = checkCount < 4 ? initialInterval : normalInterval;

      _connectionHealthCheckTimer = Timer(interval, () async {
        await _checkConnectionHealth();
        scheduleNextCheck();
      });
    }

    // Initial check
    _checkConnectionHealth().then((_) => scheduleNextCheck());
  }

  /// Check connection health for all Firebase services
  static Future<void> _checkConnectionHealth() async {
    // Check Firestore with better error handling
    try {
      // Use a simple document read instead of health collection
      final testDoc = await firestore
          .collection('users')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5)); // Increased timeout

      _isFirestoreConnected =
          testDoc.docs.isNotEmpty || testDoc.metadata.isFromCache == false;
    } catch (e) {
      _isFirestoreConnected = false;
      print('⚠️ Firestore health check failed: $e');

      // Try to re-enable network
      try {
        await firestore.enableNetwork();
      } catch (_) {}
    }

    // IMPROVED: Check Realtime Database with better approach
    try {
      // Use .info/connected as primary check
      final connectedRef = realtimeDatabase.ref('.info/connected');
      final connectedSnapshot = await connectedRef.get().timeout(
        const Duration(seconds: 4),
      );

      if (connectedSnapshot.exists) {
        _isRealtimeDbConnected = connectedSnapshot.value as bool? ?? false;
      } else {
        // Fallback: try a simple read operation
        try {
          final testRef = realtimeDatabase.ref('_health');
          await testRef.get().timeout(const Duration(seconds: 3));
          _isRealtimeDbConnected = true;
        } catch (e) {
          _isRealtimeDbConnected = false;
          print('⚠️ Realtime Database read test failed: $e');
        }
      }
    } catch (e) {
      _isRealtimeDbConnected = false;
      print('⚠️ Realtime Database health check failed: $e');

      // Try to reconnect
      try {
        realtimeDatabase.goOnline();
      } catch (_) {}
    }

    // Only log significant changes
    bool _lastFirestoreState = true;
    bool _lastRealtimeState = true;

    if (_lastFirestoreState != _isFirestoreConnected ||
        _lastRealtimeState != _isRealtimeDbConnected) {
      print(
        '🏥 Connection Health Changed - Firestore: $_isFirestoreConnected, RealtimeDB: $_isRealtimeDbConnected',
      );
      _lastFirestoreState = _isFirestoreConnected;
      _lastRealtimeState = _isRealtimeDbConnected;
    }
  }

  // Get current user ID
  static String? get currentUserId => auth.currentUser?.uid;

  // Get current user
  static User? get currentUser => auth.currentUser;

  // Check if user is authenticated
  static bool get isAuthenticated => currentUser != null;

  // Get connection status
  static bool get isFirestoreConnected => _isFirestoreConnected;
  static bool get isRealtimeDbConnected => _isRealtimeDbConnected;
  static bool get isFullyConnected =>
      _isFirestoreConnected && _isRealtimeDbConnected;

  // Get user document reference
  static DocumentReference? get currentUserDoc {
    final userId = currentUserId;
    if (userId == null) return null;
    return usersCollection.doc(userId);
  }

  // Generate unique message ID
  static String generateMessageId() {
    return firestore.collection('temp').doc().id;
  }

  /// Create or update user document with presence initialization
  static Future<void> createOrUpdateUser({
    required String uid,
    required String email,
    required String displayName,
    String? photoURL,
  }) async {
    try {
      final userDoc = usersCollection.doc(uid);

      // Check if user exists
      final docSnapshot = await userDoc.get();
      final isNewUser = !docSnapshot.exists;

      final userData = {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoURL': photoURL,
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'oneSignalPlayerId': null,
        'notificationEnabled': true,
        'isAppInBackground': false,
        'appState': 'active',
      };

      if (isNewUser) {
        userData['createdAt'] = FieldValue.serverTimestamp();
      }

      await userDoc.set(userData, SetOptions(merge: true));

      // Initialize presence for this user
      await PresenceService.instance.initialize();
      await PresenceService.instance.setUserOnline();

      print('✅ User document created/updated for $displayName');
    } catch (e) {
      print('❌ Error creating/updating user: $e');
      throw e;
    }
  }

  /// Update user online status through presence service
  static Future<void> updateUserOnlineStatus(bool isOnline) async {
    try {
      if (isOnline) {
        await PresenceService.instance.setUserOnline();
      } else {
        await PresenceService.instance.setUserOffline();
      }
    } catch (e) {
      print('❌ Error updating online status: $e');

      // Fallback to direct Firestore update
      try {
        if (currentUserId != null) {
          await usersCollection.doc(currentUserId!).update({
            'isOnline': isOnline,
            'lastSeen': FieldValue.serverTimestamp(),
          });
        }
      } catch (fallbackError) {
        print('❌ Fallback update also failed: $fallbackError');
      }
    }
  }

  /// Get user stream
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getUserStream(
    String userId,
  ) {
    return usersCollection.doc(userId).snapshots();
  }

  /// Get user presence stream from Realtime Database
  static Stream<Map<String, dynamic>?> getUserPresenceStream(String userId) {
    return PresenceService.instance.getUserPresenceStream(userId);
  }

  /// Get combined user data stream (Firestore + Presence)
  static Stream<Map<String, dynamic>?> getCombinedUserStream(String userId) {
    return getUserStream(userId).asyncMap((firestoreDoc) async {
      if (!firestoreDoc.exists) return null;

      final firestoreData = firestoreDoc.data() as Map<String, dynamic>;

      try {
        // Get real-time presence data
        final isOnline = await PresenceService.instance.isUserOnline(userId);
        final lastSeen = await PresenceService.instance.getUserLastSeen(userId);

        // Merge data with presence taking precedence
        return {
          ...firestoreData,
          'isOnline': isOnline,
          'realtimeLastSeen': lastSeen?.millisecondsSinceEpoch,
          'presenceVerified': true,
        };
      } catch (e) {
        print('⚠️ Error getting presence data for $userId: $e');
        return {...firestoreData, 'presenceVerified': false};
      }
    });
  }

  /// Send message with retry logic
  static Future<void> sendMessage({
    required String chatId,
    required String message,
    String? imageUrl,
    required String senderId,
    required String senderName,
    String? messageId,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        await _sendMessageInternal(
          chatId: chatId,
          message: message,
          imageUrl: imageUrl,
          senderId: senderId,
          senderName: senderName,
          messageId: messageId,
        );
        return; // Success
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          print('❌ Failed to send message after $maxRetries attempts');
          throw e;
        }

        print('⚠️ Message send attempt $retryCount failed, retrying...');
        await Future.delayed(Duration(seconds: retryCount));
      }
    }
  }

  static Future<void> markReceivedMessagesAsRead(
    String chatId,
    String currentUserId,
  ) async {
    try {
      print(
        '📖 Marking received messages as read for user: $currentUserId in chat: $chatId',
      );

      // Get messages that were sent TO current user (not BY current user) and are unread
      final unreadReceivedQuery =
          await getMessagesCollection(chatId)
              .where(
                'senderId',
                isNotEqualTo: currentUserId,
              ) // Not sent by current user
              .where('isRead', isEqualTo: false) // Unread
              .where('isDeleted', isEqualTo: false) // Not deleted
              .get();

      if (unreadReceivedQuery.docs.isEmpty) {
        // Don't spam logs when no unread messages
        return;
      }

      print(
        '📖 Found ${unreadReceivedQuery.docs.length} unread received messages to mark as read',
      );

      // Update messages in batch
      final batch = firestore.batch();

      for (final doc in unreadReceivedQuery.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'readBy': currentUserId,
          'deliveryStatus': 'read',
        });
      }

      await batch.commit();

      // Update user's last read timestamp for this chat
      await usersCollection.doc(currentUserId).update({
        'lastReadAt.$chatId': FieldValue.serverTimestamp(),
        'unreadChats.$chatId':
            FieldValue.delete(), // Remove unread count for this chat
      });

      print(
        '✅ Marked ${unreadReceivedQuery.docs.length} received messages as read',
      );
    } catch (e) {
      print('❌ Error marking received messages as read: $e');
      rethrow;
    }
  }

  /// Get or create chat room with retry logic
  static Future<String> getOrCreateChatRoom(String otherUserId) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Create deterministic chat ID
      final List<String> userIds = [currentUserId, otherUserId];
      userIds.sort();
      final chatId = '${userIds[0]}_${userIds[1]}';

      // Try to get existing chat
      final chatDoc = await chatsCollection.doc(chatId).get();

      if (chatDoc.exists) {
        final chatData = chatDoc.data() as Map<String, dynamic>;
        final deletedBy = List<String>.from(chatData['deletedBy'] ?? []);

        if (deletedBy.contains(currentUserId)) {
          await restoreChatForUser(chatId, currentUserId);
        }

        return chatId;
      }

      // Create new chat
      await chatsCollection.doc(chatId).set({
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
        'isDeleted': false,
        'deletedBy': [],
        'deletedAt': null,
      });

      // Update participant details
      await _updateChatParticipantDetails(chatId, userIds);

      return chatId;
    } catch (e) {
      print('❌ Error getting/creating chat room: $e');
      throw e;
    }
  }

  /// Update chat participant details
  static Future<void> _updateChatParticipantDetails(
    String chatId,
    List<String> userIds,
  ) async {
    try {
      final Map<String, String> participantNames = {};
      final Map<String, String> participantPhotos = {};

      // Get user details with retry
      for (final userId in userIds) {
        try {
          final userDoc = await usersCollection
              .doc(userId)
              .get()
              .timeout(const Duration(seconds: 3));

          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            participantNames[userId] = userData['displayName'] ?? 'Unknown';
            participantPhotos[userId] = userData['photoURL'] ?? '';
          }
        } catch (e) {
          print('⚠️ Error fetching user data for $userId: $e');
          participantNames[userId] = 'Unknown';
          participantPhotos[userId] = '';
        }
      }

      await chatsCollection.doc(chatId).update({
        'participantNames': participantNames,
        'participantPhotos': participantPhotos,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('⚠️ Error updating participant details: $e');
      // Non-critical error
    }
  }

  /// Restore chat for user
  static Future<void> restoreChatForUser(String chatId, String userId) async {
    try {
      final chatDoc = await chatsCollection.doc(chatId).get();
      if (!chatDoc.exists) return;

      final chatData = chatDoc.data() as Map<String, dynamic>;
      final deletedBy = List<String>.from(chatData['deletedBy'] ?? []);

      deletedBy.remove(userId);

      await chatsCollection.doc(chatId).update({
        'deletedBy': deletedBy,
        'isDeleted': deletedBy.isNotEmpty,
        'restoredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Chat restored for user: $userId');
    } catch (e) {
      print('❌ Error restoring chat: $e');
      throw e;
    }
  }

  /// Delete chat for user (soft delete)
  static Future<void> deleteChatForUser(String chatId, String userId) async {
    try {
      final chatDoc = await chatsCollection.doc(chatId).get();
      if (!chatDoc.exists) {
        print('❌ Chat not found: $chatId');
        return;
      }

      final chatData = chatDoc.data() as Map<String, dynamic>;
      final deletedBy = List<String>.from(chatData['deletedBy'] ?? []);

      if (!deletedBy.contains(userId)) {
        deletedBy.add(userId);
      }

      await chatsCollection.doc(chatId).update({
        'deletedBy': deletedBy,
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Chat soft deleted for user: $userId');
    } catch (e) {
      print('❌ Error deleting chat: $e');
      throw e;
    }
  }

  /// Get user's active chats stream
  static Stream<List<DocumentSnapshot<Map<String, dynamic>>>>
  getUserChatsStreamFiltered(String userId) {
    return chatsCollection
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) {
          // Filter out chats deleted by this user
          return snapshot.docs.where((doc) {
            final data = doc.data();
            final deletedBy = List<String>.from(data['deletedBy'] ?? []);
            return !deletedBy.contains(userId);
          }).toList();
        });
  }

  /// Mark messages as read with batch processing
  static Future<void> markMessagesAsRead(String chatId, String userId) async {
    try {
      // print('📖 Marking messages as read for chat: $chatId');

      // Check connection first
      if (!_isFirestoreConnected) {
        print('⚠️ Firestore not connected, skipping mark as read');
        return;
      }

      // Get unread messages with timeout
      final unreadMessages = await getMessagesCollection(chatId)
          .where('isRead', isEqualTo: false)
          .where('senderId', isNotEqualTo: userId)
          .limit(50) // Process in batches
          .get()
          .timeout(const Duration(seconds: 8));

      if (unreadMessages.docs.isEmpty) {
        // print('✅ No unread messages to mark');
        return;
      }

      // Batch update for performance
      final batch = firestore.batch();
      int count = 0;

      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'readBy': userId,
          'deliveryStatus': 'read',
        });
        count++;

        // Commit batch if it reaches limit
        if (count >= 400) {
          // Reduced batch size
          await batch.commit().timeout(const Duration(seconds: 10));
          count = 0;
        }
      }

      // Commit remaining updates
      if (count > 0) {
        await batch.commit().timeout(const Duration(seconds: 10));
      }

      // Update user's last read timestamp (async to prevent blocking)
      usersCollection
          .doc(userId)
          .update({'lastReadAt.$chatId': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 5))
          .catchError((e) {
            print('⚠️ Error updating last read timestamp: $e');
          });

      print('✅ Marked ${unreadMessages.docs.length} messages as read');
    } catch (e) {
      print('❌ Error marking messages as read: $e');
    }
  }

  /// Get messages stream with error handling
  static Stream<QuerySnapshot<Map<String, dynamic>>> getMessagesStream(
    String chatId,
  ) {
    return getMessagesCollection(chatId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .handleError((error) {
          print('❌ Error in messages stream: $error');
          // Return empty snapshot on error
          return QuerySnapshot<Map<String, dynamic>>;
        });
  }

  /// Get chat stream
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getChatStream(
    String chatId,
  ) {
    return chatsCollection.doc(chatId).snapshots();
  }

  /// Update typing status with debouncing
  static Timer? _typingTimer;

  static Future<void> updateTypingStatus({
    required String chatId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      // Check connection first
      if (!_isFirestoreConnected) {
        print('⚠️ Firestore not connected, skipping typing status update');
        return;
      }

      // Cancel previous timer
      _typingTimer?.cancel();

      if (isTyping) {
        // Set typing immediately
        await chatsCollection
            .doc(chatId)
            .update({
              'typingUsers.$userId': true,
              'updatedAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 4));

        // Clear after 4 seconds of no activity (increased from 3)
        _typingTimer = Timer(const Duration(seconds: 4), () async {
          try {
            await chatsCollection
                .doc(chatId)
                .update({'typingUsers.$userId': false})
                .timeout(const Duration(seconds: 3));
          } catch (e) {
            print('⚠️ Error clearing typing status: $e');
          }
        });
      } else {
        // Clear typing immediately
        await chatsCollection
            .doc(chatId)
            .update({'typingUsers.$userId': false})
            .timeout(const Duration(seconds: 4));
      }
    } catch (e) {
      print('❌ Error updating typing status: $e');
    }
  }

  /// Delete message (soft delete)
  static Future<void> deleteMessage(String chatId, String messageId) async {
    try {
      await getMessagesCollection(chatId).doc(messageId).update({
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

  /// Get unread message count
  static Future<int> getUnreadMessageCount(String chatId, String userId) async {
    try {
      // Check connection first
      if (!_isFirestoreConnected) {
        print('⚠️ Firestore not connected, returning cached unread count');
        return 0; // Could implement caching here
      }

      final unreadMessages = await getMessagesCollection(chatId)
          .where('senderId', isNotEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .where('isDeleted', isEqualTo: false)
          .count()
          .get()
          .timeout(const Duration(seconds: 6));

      return unreadMessages.count ?? 0;
    } catch (e) {
      print('❌ Error getting unread count: $e');
      return 0;
    }
  }

  /// Check if user has partner
  static Future<String?> getUserPartnerId(String userId) async {
    try {
      final userDoc = await usersCollection
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 3));

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        return userData['partnerId'] as String?;
      }
      return null;
    } catch (e) {
      print('❌ Error getting partner ID: $e');
      return null;
    }
  }

  /// Connect two users as partners
  static Future<void> connectPartners(String userId1, String userId2) async {
    try {
      final batch = firestore.batch();

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

  /// App lifecycle methods with presence integration
  static Future<void> onAppResumed() async {
    try {
      print('📱 App resumed - updating presence');

      // IMPORTANT: Add delay to prevent race conditions
      await Future.delayed(const Duration(milliseconds: 800));

      // Re-enable networks first
      if (!_isFirestoreConnected) {
        try {
          await firestore.enableNetwork().timeout(const Duration(seconds: 3));
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('⚠️ Error enabling Firestore network: $e');
        }
      }

      if (!_isRealtimeDbConnected) {
        try {
          realtimeDatabase.goOnline();
          // Wait for connection to establish
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          print('⚠️ Error going online Realtime DB: $e');
        }
      }

      // Update presence service (it will handle connection checks internally)
      try {
        await PresenceService.instance.setUserOnline();
      } catch (e) {
        print('⚠️ Error setting presence online: $e');
      }

      // Update Firestore user document with better retry logic
      if (currentUserId != null) {
        await _updateUserDocumentWithRetry(currentUserId!, {
          'isOnline': true,
          'isAppInBackground': false,
          'lastSeen': FieldValue.serverTimestamp(),
          'appState': 'active',
          'appStateUpdatedAt': FieldValue.serverTimestamp(),
        });
      }

      print('✅ App resumed handling complete');
    } catch (e) {
      print('❌ Error handling app resume: $e');
    }
  }

  static Future<void> _updateUserDocumentWithRetry(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    int retries = 0;
    const maxRetries = 2;

    while (retries < maxRetries) {
      try {
        await usersCollection
            .doc(userId)
            .update(updates)
            .timeout(const Duration(seconds: 8)); // Increased timeout

        print('✅ User document updated successfully');
        return;
      } catch (e) {
        retries++;
        print('⚠️ User document update attempt $retries failed: $e');

        if (retries >= maxRetries) {
          print('❌ Failed to update user document after $maxRetries retries');
          throw e;
        }

        // Wait before retry
        await Future.delayed(Duration(seconds: retries));
      }
    }
  }

  static Future<void> onAppPaused() async {
    try {
      print('📱 App paused - updating presence');

      // Update presence service first
      try {
        await PresenceService.instance.setUserOffline();
      } catch (e) {
        print('⚠️ Error setting presence offline: $e');
      }

      // Update Firestore user document
      if (currentUserId != null) {
        try {
          await _updateUserDocumentWithRetry(currentUserId!, {
            'isOnline': false,
            'isAppInBackground': true,
            'lastSeen': FieldValue.serverTimestamp(),
            'appState': 'background',
            'appStateUpdatedAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          print('⚠️ Error updating user document on pause: $e');
        }
      }

      print('✅ App paused handling complete');
    } catch (e) {
      print('❌ Error handling app pause: $e');
    }
  }

  /// IMPROVED: Send message with better retry logic and connection handling
  static Future<void> _sendMessageInternal({
    required String chatId,
    required String message,
    String? imageUrl,
    required String senderId,
    required String senderName,
    String? messageId,
  }) async {
    print('📤 Sending message to chat: $chatId');

    // Check connection health before proceeding
    if (!_isFirestoreConnected) {
      print('⚠️ Firestore not connected, attempting to reconnect...');
      try {
        await firestore.enableNetwork();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print('❌ Failed to reconnect Firestore: $e');
        throw Exception('No connection to Firestore');
      }
    }

    // Verify chat exists and restore if needed
    final chatDoc = await chatsCollection
        .doc(chatId)
        .get()
        .timeout(const Duration(seconds: 8)); // Increased timeout

    if (!chatDoc.exists) {
      throw Exception('Chat does not exist');
    }

    final chatData = chatDoc.data() as Map<String, dynamic>;
    final deletedBy = List<String>.from(chatData['deletedBy'] ?? []);

    if (deletedBy.contains(senderId)) {
      // Restore chat for sender
      await restoreChatForUser(chatId, senderId);
    }

    // Verify user is participant
    final participants = List<String>.from(chatData['participants'] ?? []);
    if (!participants.contains(senderId)) {
      throw Exception('User is not a participant in this chat');
    }

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

    // Use batch for atomic operation with better timeout
    final batch = firestore.batch();

    // Add message
    batch.set(getMessagesCollection(chatId).doc(docId), messageData);

    // Update chat
    batch.update(chatsCollection.doc(chatId), {
      'lastMessage': imageUrl != null ? '📷 Photo' : message,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSender': senderName,
      'lastMessageSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
      'messageCount': FieldValue.increment(1),
      'isDeleted': false,
      'deletedBy': [],
    });

    // Commit with increased timeout
    await batch.commit().timeout(const Duration(seconds: 10));
    print('✅ Message sent successfully');
  }

  /// Enhanced sign out with proper cleanup
  static Future<void> signOut() async {
    try {
      print('🔴 Signing out user...');

      // Clean up presence first (with timeout)
      try {
        await PresenceService.instance.signOut().timeout(
          const Duration(seconds: 5),
        );
      } catch (e) {
        print('⚠️ Error during presence cleanup: $e');
      }

      // Update user document (with timeout and fallback)
      if (currentUserId != null) {
        try {
          await usersCollection
              .doc(currentUserId!)
              .update({
                'isOnline': false,
                'lastSeen': FieldValue.serverTimestamp(),
                'appState': 'signed_out',
                'appStateUpdatedAt': FieldValue.serverTimestamp(),
              })
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          print('⚠️ Error updating user document during signout: $e');
        }
      }

      // Cancel timers and subscriptions
      _typingTimer?.cancel();
      _connectionHealthCheckTimer?.cancel();
      await _authStateSubscription?.cancel();

      // Reset connection states
      _isFirestoreConnected = true;
      _isRealtimeDbConnected = true;

      // Sign out from Firebase Auth
      await auth.signOut().timeout(const Duration(seconds: 5));

      print('✅ User signed out successfully');
    } catch (e) {
      print('❌ Error signing out: $e');

      // Force sign out even if cleanup fails
      try {
        await auth.signOut();
      } catch (_) {}

      throw e;
    }
  }

  /// NEW: Connection recovery methods
  static Future<void> attemptConnectionRecovery() async {
    print('🔄 Attempting connection recovery...');

    try {
      // Reset Firestore connection
      if (!_isFirestoreConnected) {
        await firestore.disableNetwork();
        await Future.delayed(const Duration(milliseconds: 500));
        await firestore.enableNetwork();
        await Future.delayed(const Duration(seconds: 1));
      }

      // Reset Realtime DB connection
      if (!_isRealtimeDbConnected) {
        realtimeDatabase.goOffline();
        await Future.delayed(const Duration(milliseconds: 500));
        realtimeDatabase.goOnline();
        await Future.delayed(const Duration(seconds: 1));
      }

      // Check health after recovery attempt
      await _checkConnectionHealth();

      print('✅ Connection recovery attempt completed');
    } catch (e) {
      print('❌ Error during connection recovery: $e');
    }
  }

  /// NEW: Get connection quality info
  static Map<String, dynamic> getConnectionInfo() {
    return {
      'firestore': {
        'connected': _isFirestoreConnected,
        'lastCheck': DateTime.now().toIso8601String(),
      },
      'realtimeDatabase': {
        'connected': _isRealtimeDbConnected,
        'lastCheck': DateTime.now().toIso8601String(),
      },
      'presence': {
        'connected': PresenceService.instance.isConnectedToRealtimeDB,
        'initialized': PresenceService.instance.isInitialized,
      },
      'overall': {
        'healthy': _isFirestoreConnected && _isRealtimeDbConnected,
        'degraded': _isFirestoreConnected != _isRealtimeDbConnected,
      },
    };
  }

  /// Check if services are healthy
  static Future<Map<String, bool>> checkServicesHealth() async {
    await _checkConnectionHealth();

    return {
      'firestore': _isFirestoreConnected,
      'realtimeDatabase': _isRealtimeDbConnected,
      'presence': PresenceService.instance.isConnectedToRealtimeDB,
      'auth': currentUser != null,
    };
  }

  /// Get debug information
  static Map<String, dynamic> getDebugInfo() {
    return {
      'currentUserId': currentUserId,
      'isAuthenticated': isAuthenticated,
      'firestoreConnected': _isFirestoreConnected,
      'realtimeDbConnected': _isRealtimeDbConnected,
      'presenceService': PresenceService.instance.getDebugInfo(),
    };
  }

  /// Batch operations for better performance
  static WriteBatch createBatch() => firestore.batch();

  /// Server timestamp
  static FieldValue get serverTimestamp => FieldValue.serverTimestamp();
}
