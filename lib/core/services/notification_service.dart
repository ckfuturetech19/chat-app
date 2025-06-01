import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'firebase_service.dart';
import 'pressence_service.dart';

class NotificationService {
  static const String _oneSignalAppId = "7d95dd17-81f9-4090-a80c-f849a182de99";
  static const String _oneSignalRestApiKey =
      "os_v2_app_pwk52f4b7fajbkam7be2daw6thcqgldxmiwuxznkwlugxfa66ahqgd4e25o5vrjnuy2cri7xb6ve2qpazujoegedxwiynosvw522gsa";
  static const String _oneSignalApiUrl =
      "https://onesignal.com/api/v1/notifications";

  // Track current active chat
  static String? _currentActiveChatId;
  static bool _isAppInForeground = true;

  // Validate API key format
  static bool _isValidApiKey(String apiKey) {
    return apiKey.isNotEmpty && apiKey.length >= 20;
  }

  // Initialize OneSignal with enhanced setup
  static Future<void> initialize() async {
    try {
      print('🔍 Initializing OneSignal with App ID: $_oneSignalAppId');

      OneSignal.initialize(_oneSignalAppId);
      await OneSignal.Notifications.requestPermission(true);
      _setupNotificationHandlers();
      await updateUserPlayerId();

      print('✅ OneSignal initialized successfully');
    } catch (e) {
      print('❌ OneSignal initialization error: $e');
    }
  }

  static void _setupNotificationHandlers() {
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      print(
        '📱 Notification received in foreground: ${event.notification.title}',
      );

      final additionalData = event.notification.additionalData;
      final notificationType = additionalData?['type'] as String?;

      if (notificationType == 'new_message') {
        final chatId = additionalData?['chatId'] as String?;

        // Check if user is currently viewing this specific chat
        if (_isUserViewingChat(chatId)) {
          print('📱 User is viewing chat, not showing notification');
          return; // Don't display notification
        }
      }

      // Display notification if user is not in the specific chat
      event.notification.display();
    });

    OneSignal.Notifications.addClickListener((event) {
      print('🔔 Notification clicked: ${event.notification.title}');
      final additionalData = event.notification.additionalData;
      if (additionalData != null) {
        _handleNotificationClick(additionalData);
      }
    });

    OneSignal.Notifications.addPermissionObserver((state) {
      print('🔔 Notification permission state: $state');
      if (state) updateUserPlayerId();
    });

    OneSignal.User.pushSubscription.addObserver((state) {
      print('🔔 Push subscription changed: ${state.current.id}');
      if (state.current.id != null) updateUserPlayerId();
    });
  }

  // Set current active chat ID
  static void setActiveChatId(String? chatId) {
    _currentActiveChatId = chatId;
    print('📱 Active chat set to: $chatId');
  }

  // Set app foreground state
  static void setAppForegroundState(bool isInForeground) {
    _isAppInForeground = isInForeground;
    print('📱 App foreground state: $isInForeground');
  }

  // Check if user is viewing specific chat
  static bool _isUserViewingChat(String? chatId) {
    if (!_isAppInForeground) return false;
    if (chatId == null || _currentActiveChatId == null) return false;
    return _currentActiveChatId == chatId;
  }

  static void _handleNotificationClick(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final chatId = data['chatId'] as String?;
    final senderId = data['senderId'] as String?;

    switch (type) {
      case 'new_message':
        if (chatId != null) {
          print('📱 Opening chat: $chatId from sender: $senderId');
          _navigateToChat(chatId, senderId);
        }
        break;
      case 'typing':
        print('✍️ Partner is typing in chat: $chatId');
        break;
      case 'connection_request':
        print('🤝 New connection request');
        break;
      default:
        print('📱 Unknown notification type: $type');
    }
  }

  static void _navigateToChat(String chatId, String? senderId) {
    print('🧭 Navigation intent: Chat $chatId');
    // TODO: Implement navigation logic here
  }

  static Future<String?> getPlayerId() async {
    try {
      for (int attempt = 0; attempt < 5; attempt++) {
        final playerId = OneSignal.User.pushSubscription.id;
        if (playerId != null && playerId.isNotEmpty) {
          print('✅ OneSignal Player ID obtained: $playerId');
          return playerId;
        }

        print('⏳ Attempt ${attempt + 1}: Waiting for OneSignal Player ID...');
        await Future.delayed(Duration(seconds: (attempt + 1) * 2));
      }

      print('⚠️ Could not get OneSignal player ID after 5 attempts');
      return null;
    } catch (e) {
      print('❌ Error getting OneSignal player ID: $e');
      return null;
    }
  }

  static Future<void> updateUserPlayerId() async {
    try {
      final playerId = await getPlayerId();
      final currentUser = FirebaseService.currentUser;

      if (playerId != null && currentUser != null) {
        await FirebaseService.usersCollection.doc(currentUser.uid).update({
          'oneSignalPlayerId': playerId,
          'notificationEnabled': true,
          'lastPlayerIdUpdate': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        print('✅ OneSignal Player ID updated in Firestore: $playerId');
      } else {
        print(
          '⚠️ Could not update player ID - playerId: $playerId, user: ${currentUser?.uid}',
        );

        if (playerId == null) {
          print('🔄 Retrying player ID update in 5 seconds...');
          Future.delayed(const Duration(seconds: 5), () {
            updateUserPlayerId();
          });
        }
      }
    } catch (e) {
      print('❌ Error updating OneSignal Player ID: $e');
      Future.delayed(const Duration(seconds: 5), () {
        updateUserPlayerId();
      });
    }
  }

  /// MAIN NOTIFICATION SENDING METHOD - This is what gets called when sending messages
  static Future<bool> sendMessageNotification({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
  }) async {
    print('🚀 === STARTING MESSAGE NOTIFICATION PROCESS ===');
    print('📱 Recipient Player ID: $recipientPlayerId');
    print('👤 Sender: $senderName');
    print('💬 Message: $message');
    print('🗣️ Chat ID: $chatId');
    print('👤 Sender ID: $senderId');

    try {
      // STEP 1: Check if we should send notification
      final shouldSend = await _shouldSendNotificationFixed(
        recipientPlayerId: recipientPlayerId,
        chatId: chatId,
        senderId: senderId,
      );

      print('🤔 Should send notification: $shouldSend');

      if (!shouldSend) {
        print('❌ SKIPPING notification - user is actively viewing this chat');
        return false;
      }

      // STEP 2: Send the notification
      print('✅ PROCEEDING to send notification');
      final success = await _sendNotificationDirectly(
        recipientPlayerId: recipientPlayerId,
        senderName: senderName,
        message: message,
        chatId: chatId,
        senderId: senderId,
      );

      print(
        success
            ? '✅ === NOTIFICATION SENT SUCCESSFULLY ==='
            : '❌ === NOTIFICATION SENDING FAILED ===',
      );

      return success;
    } catch (e, stackTrace) {
      print('❌ Error in sendMessageNotification: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  /// FIXED: Simplified and more reliable notification decision logic
 static Future<bool> _shouldSendNotificationFixed({
  required String recipientPlayerId,
  required String chatId,
  required String senderId,
}) async {
  try {
    print('🔍 === CHECKING IF NOTIFICATION SHOULD BE SENT (WITH PRIVACY) ===');

    // Get recipient user ID from player ID
    final recipientUserId = await _getRecipientUserIdFromPlayerId(recipientPlayerId);
    if (recipientUserId == null) {
      print('✅ SEND: No user ID found for player - sending notification');
      return true;
    }

    print('🔍 Recipient User ID: $recipientUserId');

    // Check user document for notification preferences and status
    final recipientDoc = await FirebaseService.usersCollection
        .doc(recipientUserId)
        .get()
        .timeout(const Duration(seconds: 3));

    if (!recipientDoc.exists) {
      print('✅ SEND: User document not found - sending notification');
      return true;
    }

    final recipientData = recipientDoc.data() as Map<String, dynamic>;

    // 🔥 NEW: Check if user has notifications enabled
    final notificationEnabled = recipientData['notificationEnabled'] as bool? ?? true;
    if (!notificationEnabled) {
      print('❌ DON\'T SEND: User has disabled notifications');
      return false;
    }

    // Extract other status variables
    final isOnlineFirestore = recipientData['isOnline'] as bool? ?? false;
    final activeChatId = recipientData['activeChatId'] as String?;
    final isAppInBackground = recipientData['isAppInBackground'] as bool? ?? true;
    final appState = recipientData['appState'] as String? ?? 'unknown';
    final lastSeen = recipientData['lastSeen'] as Timestamp?;

    print('📊 === USER STATUS FROM FIRESTORE (WITH PRIVACY) ===');
    print('📊 Notifications Enabled: $notificationEnabled');
    print('📊 Is Online (Firestore): $isOnlineFirestore');
    print('📊 Active Chat ID: $activeChatId');
    print('📊 Target Chat ID: $chatId');
    print('📊 App In Background: $isAppInBackground');
    print('📊 App State: $appState');
    print('📊 Last Seen: $lastSeen');

    print('📊 === PRIVACY-AWARE DECISION LOGIC ===');

    // RULE 1: Notifications disabled - don't send
    if (!notificationEnabled) {
      print('❌ DON\'T SEND: User has notifications disabled');
      return false;
    }

    // RULE 2: If user is offline in Firestore, send notification
    if (!isOnlineFirestore) {
      print('✅ SEND: User is offline in Firestore');
      return true;
    }

    // RULE 3: If last seen is more than 1 minute ago, send notification
    if (lastSeen != null) {
      final timeSinceLastSeen = DateTime.now().difference(lastSeen.toDate());
      if (timeSinceLastSeen.inMinutes >= 1) {
        print('✅ SEND: Last seen ${timeSinceLastSeen.inMinutes} minutes ago (stale)');
        return true;
      } else {
        print('🕐 Last seen: ${timeSinceLastSeen.inSeconds} seconds ago (recent)');
      }
    }

    // RULE 4: If app is in background, send notification
    if (isAppInBackground) {
      print('✅ SEND: App is in background');
      return true;
    }

    // RULE 5: If app state is not active, send notification
    if (appState != 'active') {
      print('✅ SEND: App state is not active ($appState)');
      return true;
    }

    // RULE 6: If user is not in any chat, send notification
    if (activeChatId == null || activeChatId.isEmpty) {
      print('✅ SEND: User is not in any chat');
      return true;
    }

    // RULE 7: If user is in a different chat, send notification
    if (activeChatId != chatId) {
      print('✅ SEND: User is in different chat ($activeChatId vs $chatId)');
      return true;
    }

    // If we reach here, user is online, app is active, viewing this chat, AND has notifications enabled
    print('❌ DON\'T SEND: User is actively viewing this chat');
    return false;

  } catch (e) {
    print('❌ Error in notification check: $e');
    print('✅ SEND: Error occurred - defaulting to send notification (safety first)');
    return true; // Default to sending on error for safety
  }
}

// 🔥 ADD: Method to update user notification preferences and OneSignal subscription
static Future<void> updateNotificationPreference(String userId, bool enabled) async {
  try {
    print('🔔 Updating notification preference for $userId: $enabled');

    // Update in Firestore
    await FirebaseService.usersCollection.doc(userId).update({
      'notificationEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 🔥 NEW: Update OneSignal subscription status
    if (enabled) {
      // Enable notifications
      await OneSignal.User.pushSubscription.optIn();
      await updateUserPlayerId(); // Refresh player ID
      print('✅ OneSignal notifications enabled');
    } else {
      // Disable notifications  
      await OneSignal.User.pushSubscription.optOut();
      print('✅ OneSignal notifications disabled');
    }

    print('✅ Notification preference updated successfully');
  } catch (e) {
    print('❌ Error updating notification preference: $e');
    rethrow;
  }
}

// 🔥 ADD: Method to check if user has notifications enabled
static Future<bool> isNotificationEnabledForUser(String userId) async {
  try {
    final userDoc = await FirebaseService.usersCollection.doc(userId).get();
    
    if (!userDoc.exists) return true; // Default to enabled
    
    final userData = userDoc.data() as Map<String, dynamic>;
    return userData['notificationEnabled'] as bool? ?? true;
  } catch (e) {
    print('❌ Error checking notification preference: $e');
    return true; // Default to enabled on error
  }
}

// 🔥 ADD: Get notification status for current user
static Future<Map<String, dynamic>> getCurrentUserNotificationStatus() async {
  try {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) {
      return {'enabled': false, 'hasPlayerId': false, 'permission': false};
    }

    // Check Firestore preference
    final isEnabled = await isNotificationEnabledForUser(currentUserId);
    
    // Check OneSignal permission
    final hasPermission = await areNotificationsEnabled();
    
    // Check if user has player ID
    final playerId = await getPlayerId();
    final hasPlayerId = playerId != null && playerId.isNotEmpty;

    return {
      'enabled': isEnabled,
      'hasPlayerId': hasPlayerId,
      'permission': hasPermission,
      'playerId': playerId,
    };
  } catch (e) {
    print('❌ Error getting notification status: $e');
    return {'enabled': false, 'hasPlayerId': false, 'permission': false};
  }
}

  /// Send notification directly via OneSignal REST API
  static Future<bool> _sendNotificationDirectly({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
  }) async {
    try {
      print('📡 === SENDING NOTIFICATION VIA REST API ===');

      // Format message for notification
      String notificationMessage = message;
      if (message.length > 100) {
        notificationMessage = '${message.substring(0, 97)}...';
      }

      // Handle special message types
      if (message.startsWith('📷')) {
        notificationMessage = '📷 Sent a photo';
      } else if (message.isEmpty) {
        notificationMessage = 'Sent a message';
      }

      // Create notification payload
      final Map<String, dynamic> notificationPayload = {
        'app_id': _oneSignalAppId,
        'include_player_ids': [recipientPlayerId],
        'headings': {'en': '💕 $senderName'},
        'contents': {'en': notificationMessage},
        'data': {
          'type': 'new_message',
          'chatId': chatId,
          'senderId': senderId,
          'senderName': senderName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'messagePreview': notificationMessage,
        },
        'priority': 10, // High priority
        'ttl': 259200, // 3 days
        'android_accent_color': 'FF9C27B0',
        'android_led_color': 'FF9C27B0',
        'android_sound': 'default',
        'ios_sound': 'default',
        'ios_badgeType': 'Increase',
        'ios_badgeCount': 1,
      };

      print('📡 Making HTTP POST request to OneSignal...');

      // Validate API key before sending
      if (!_isValidApiKey(_oneSignalRestApiKey)) {
        print('❌ Invalid API key format');
        return false;
      }

      // Send notification via REST API
      final response = await http
          .post(
            Uri.parse(_oneSignalApiUrl),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Basic $_oneSignalRestApiKey',
              'Accept': 'application/json',
            },
            body: jsonEncode(notificationPayload),
          )
          .timeout(const Duration(seconds: 30));

      print('📨 HTTP Response Status: ${response.statusCode}');
      print('📨 HTTP Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ NOTIFICATION SENT SUCCESSFULLY!');
        print('📊 OneSignal ID: ${responseData['id']}');
        print('📊 Recipients: ${responseData['recipients']}');

        // Update unread count
        await _updateUnreadCount(recipientPlayerId, chatId);

        // Store notification record
        await _storeNotificationRecord(
          recipientPlayerId: recipientPlayerId,
          senderName: senderName,
          message: notificationMessage,
          chatId: chatId,
          senderId: senderId,
          oneSignalId: responseData['id'] ?? 'unknown',
          recipients: responseData['recipients'] ?? 0,
        );

        return true;
      } else {
        print('❌ Failed to send notification: ${response.statusCode}');
        print('❌ Response Body: ${response.body}');

        // Try to parse error response
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['errors'] != null) {
            print('❌ OneSignal Errors: ${errorData['errors']}');
          }
        } catch (e) {
          print('❌ Could not parse error response: $e');
        }

        return false;
      }
    } catch (e, stackTrace) {
      print('❌ Error sending notification: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // Store notification record for tracking
  static Future<void> _storeNotificationRecord({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
    required String oneSignalId,
    required int recipients,
  }) async {
    try {
      await FirebaseService.firestore.collection('notificationLogs').add({
        'type': 'new_message',
        'recipientPlayerId': recipientPlayerId,
        'senderName': senderName,
        'message': message,
        'chatId': chatId,
        'senderId': senderId,
        'oneSignalId': oneSignalId,
        'recipients': recipients,
        'status': 'sent',
        'method': 'rest_api_direct',
        'sentAt': FieldValue.serverTimestamp(),
        'appId': _oneSignalAppId,
      });

      print('✅ Notification record stored');
    } catch (e) {
      print('❌ Error storing notification record: $e');
    }
  }

  // Update unread message count
  static Future<void> _updateUnreadCount(
    String recipientPlayerId,
    String chatId,
  ) async {
    try {
      final recipientUserId = await _getRecipientUserIdFromPlayerId(
        recipientPlayerId,
      );

      if (recipientUserId == null) {
        print('⚠️ Cannot update unread count - user ID not found');
        return;
      }

      // Check if user document exists
      final userDoc =
          await FirebaseService.usersCollection.doc(recipientUserId).get();

      if (!userDoc.exists) {
        print('⚠️ Cannot update unread count - user document does not exist');
        return;
      }

      // Update unread count
      await FirebaseService.usersCollection.doc(recipientUserId).update({
        'unreadChats.$chatId': FieldValue.increment(1),
        'totalUnreadMessages': FieldValue.increment(1),
        'lastUnreadUpdate': FieldValue.serverTimestamp(),
      });

      print('✅ Updated unread count for user: $recipientUserId');
    } catch (e) {
      print('❌ Error updating unread count: $e');
    }
  }

  // Get user ID from OneSignal player ID
  static Future<String?> _getRecipientUserIdFromPlayerId(
    String playerId,
  ) async {
    try {
      print('🔍 Looking up user ID for player ID: $playerId');

      final querySnapshot =
          await FirebaseService.usersCollection
              .where('oneSignalPlayerId', isEqualTo: playerId)
              .limit(1)
              .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userDoc = querySnapshot.docs.first;
        final userId = userDoc.id;
        print('✅ Found user ID: $userId for player ID: $playerId');
        return userId;
      } else {
        print('❌ No user found with player ID: $playerId');
        return null;
      }
    } catch (e) {
      print('❌ Error getting user ID from player ID: $e');
      return null;
    }
  }

  // Clear unread count when user opens chat
  static Future<void> clearUnreadCount(String userId, String chatId) async {
    try {
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();

      if (!userDoc.exists) {
        print(
          '⚠️ Cannot clear unread count - user document does not exist: $userId',
        );
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final unreadChats =
          userData['unreadChats'] as Map<String, dynamic>? ?? {};
      final currentUnreadForChat = unreadChats[chatId] as int? ?? 0;

      if (currentUnreadForChat > 0) {
        await FirebaseService.usersCollection.doc(userId).update({
          'unreadChats.$chatId': FieldValue.delete(),
          'totalUnreadMessages': FieldValue.increment(-currentUnreadForChat),
          'lastReadUpdate': FieldValue.serverTimestamp(),
        });

        print(
          '✅ Cleared $currentUnreadForChat unread messages for chat: $chatId',
        );
      } else {
        print('📋 No unread messages to clear for chat: $chatId');
      }
    } catch (e) {
      print('❌ Error clearing unread count: $e');
    }
  }

  // Track user's current active chat
  static Future<void> setUserActiveChatId(String userId, String? chatId) async {
    try {
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();

      if (!userDoc.exists) {
        print(
          '⚠️ Cannot set active chat - user document does not exist: $userId',
        );
        return;
      }

      await FirebaseService.usersCollection.doc(userId).update({
        'activeChatId': chatId,
        'isInChat': chatId != null,
        'lastChatActivity': FieldValue.serverTimestamp(),
      });

      // Also set locally
      setActiveChatId(chatId);

      print('✅ Updated user active chat ID: $chatId for user: $userId');
    } catch (e) {
      print('❌ Error updating user active chat ID: $e');
    }
  }

  // Set user app background state
  static Future<void> setUserAppBackgroundState(
    String userId,
    bool isInBackground,
  ) async {
    try {
      await FirebaseService.usersCollection.doc(userId).update({
        'isAppInBackground': isInBackground,
        'appState': isInBackground ? 'background' : 'active',
        'lastAppStateUpdate': FieldValue.serverTimestamp(),
      });

      // Also set locally
      setAppForegroundState(!isInBackground);

      print('✅ Updated user app background state: $isInBackground');
    } catch (e) {
      print('❌ Error updating user app background state: $e');
    }
  }

  // 🧪 TEST METHODS

  /// FORCE SEND - Bypass all checks and send notification
  static Future<bool> forceSendNotification({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
  }) async {
    print('🚀 === FORCE SENDING NOTIFICATION (BYPASSING ALL CHECKS) ===');

    return await _sendNotificationDirectly(
      recipientPlayerId: recipientPlayerId,
      senderName: senderName,
      message: message,
      chatId: chatId,
      senderId: senderId,
    );
  }

  /// Test notification to self
  static Future<bool> testNotificationToSelf({String? customMessage}) async {
    try {
      print('🧪 === TESTING NOTIFICATION TO SELF ===');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user ID');
        return false;
      }

      final userDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();
      if (!userDoc.exists) {
        print('❌ User document not found');
        return false;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final playerId = userData['oneSignalPlayerId'] as String?;
      final userName = userData['displayName'] as String? ?? 'Test User';

      if (playerId == null) {
        print('❌ No OneSignal player ID found');
        return false;
      }

      final testMessage =
          customMessage ??
          '🧪 Test notification - ${DateTime.now().toIso8601String()}';

      print('📤 Sending test notification to self...');
      print('📝 Player ID: $playerId');
      print('📝 Message: $testMessage');

      final success = await forceSendNotification(
        recipientPlayerId: playerId,
        senderName: userName,
        message: testMessage,
        chatId: 'self_test_${DateTime.now().millisecondsSinceEpoch}',
        senderId: currentUserId,
      );

      print(
        success
            ? '✅ Self test notification sent!'
            : '❌ Self test notification failed!',
      );
      return success;
    } catch (e) {
      print('❌ Self test error: $e');
      return false;
    }
  }

  /// Test notification to partner
  static Future<bool> testNotificationToPartner({String? customMessage}) async {
    try {
      print('🧪 === TESTING NOTIFICATION TO PARTNER ===');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user ID');
        return false;
      }

      final userDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();
      if (!userDoc.exists) {
        print('❌ User document not found');
        return false;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final partnerId = userData['partnerId'] as String?;
      final currentUserName = userData['displayName'] as String? ?? 'Test User';

      if (partnerId == null) {
        print('❌ No partner ID found');
        return false;
      }

      final partnerDoc =
          await FirebaseService.usersCollection.doc(partnerId).get();
      if (!partnerDoc.exists) {
        print('❌ Partner document not found');
        return false;
      }

      final partnerData = partnerDoc.data() as Map<String, dynamic>;
      final partnerPlayerId = partnerData['oneSignalPlayerId'] as String?;

      if (partnerPlayerId == null) {
        print('❌ Partner has no OneSignal player ID');
        return false;
      }

      final testMessage =
          customMessage ??
          '🧪 Test notification to partner - ${DateTime.now().toIso8601String()}';

      print('📤 Sending test notification to partner...');
      print('📝 Partner Player ID: $partnerPlayerId');
      print('📝 Message: $testMessage');

      final success = await forceSendNotification(
        recipientPlayerId: partnerPlayerId,
        senderName: currentUserName,
        message: testMessage,
        chatId: 'partner_test_${DateTime.now().millisecondsSinceEpoch}',
        senderId: currentUserId,
      );

      print(
        success
            ? '✅ Partner test notification sent!'
            : '❌ Partner test notification failed!',
      );
      return success;
    } catch (e) {
      print('❌ Partner test error: $e');
      return false;
    }
  }

  // Utility methods
  static Future<bool> areNotificationsEnabled() async {
    try {
      final permission = await OneSignal.Notifications.permission;
      return permission;
    } catch (e) {
      print('❌ Error checking notification permission: $e');
      return false;
    }
  }

  static Future<bool> requestNotificationPermission() async {
    try {
      final permission = await OneSignal.Notifications.requestPermission(true);

      if (permission) {
        await updateUserPlayerId();
        print('✅ Notification permission granted');
      } else {
        print('⚠️ Notification permission denied');
      }

      return permission;
    } catch (e) {
      print('❌ Error requesting notification permission: $e');
      return false;
    }
  }

  static Future<void> clearAllNotifications() async {
    try {
      await OneSignal.Notifications.clearAll();
      print('✅ All notifications cleared');
    } catch (e) {
      print('❌ Error clearing notifications: $e');
    }
  }

  static Future<Map<String, dynamic>> getNotificationSettings() async {
    try {
      final permission = await areNotificationsEnabled();
      final playerId = await getPlayerId();

      return {
        'permission': permission,
        'playerId': playerId,
        'oneSignalAppId': _oneSignalAppId,
        'restApiKey': '${_oneSignalRestApiKey.substring(0, 8)}...',
        'sdkVersion': 'OneSignal Flutter SDK',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error getting notification settings: $e');
      return {};
    }
  }

  static Future<void> setExternalUserId(String userId) async {
    try {
      OneSignal.login(userId);
      print('✅ OneSignal external user ID set: $userId');
    } catch (e) {
      print('❌ Error setting OneSignal external user ID: $e');
    }
  }

  static Future<void> removeExternalUserId() async {
    try {
      OneSignal.logout();
      print('✅ OneSignal external user ID removed');
    } catch (e) {
      print('❌ Error removing OneSignal external user ID: $e');
    }
  }

  
}
