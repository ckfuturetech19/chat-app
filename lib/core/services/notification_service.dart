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

  // Validate API key format
  static bool _isValidApiKey(String apiKey) {
    // OneSignal REST API keys should be 32+ characters
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

        // ENHANCED: Check if user is currently viewing this specific chat
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

  // Track current active chat
  static String? _currentActiveChatId;
  static bool _isAppInForeground = true;

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
    // You might want to use a global navigation key or route management
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

  // ENHANCED: Direct REST API notification sending for instant delivery
  static Future<bool> sendInstantMessageNotification({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
    bool skipPresenceCheck =
        false, // Allow bypassing presence check for testing
  }) async {
    try {
      print('🚀 Sending INSTANT notification via REST API...');
      print('📝 To Player ID: $recipientPlayerId');
      print('📝 From: $senderName');
      print('📝 Message: $message');
      print('📝 Chat ID: $chatId');
      print('📝 Sender ID: $senderId');

      // Check if notification should be sent (skip for testing)
      if (!skipPresenceCheck) {
        final shouldSendNotification = await _shouldSendNotification(
          recipientPlayerId: recipientPlayerId,
          chatId: chatId,
          senderId: senderId,
        );

        if (!shouldSendNotification) {
          print('📱 Skipping notification - recipient is active in chat');
          return false;
        }
      } else {
        print('🧪 Skipping presence check for testing');
      }

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

      print('🔧 Creating notification payload...');

      // Create notification payload for OneSignal REST API
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
        // Remove android_channel_id - let OneSignal use default
        // 'android_channel_id': 'high_importance_channel',
        'android_accent_color': 'FF9C27B0',
        'android_led_color': 'FF9C27B0',
        'android_sound': 'default',
        'ios_sound': 'default',
        'ios_badgeType': 'Increase',
        'ios_badgeCount': 1,
      };

      print('📡 Sending HTTP request to OneSignal...');
      print('🔗 URL: $_oneSignalApiUrl');
      print('🔑 API Key Length: ${_oneSignalRestApiKey.length}');
      print('🔑 API Key Valid: ${_isValidApiKey(_oneSignalRestApiKey)}');
      print('🔑 App ID: $_oneSignalAppId');
      print('📦 Payload: ${jsonEncode(notificationPayload)}');

      // Validate API key before sending
      if (!_isValidApiKey(_oneSignalRestApiKey)) {
        print('❌ Invalid API key format');
        return false;
      }

      print('🚀 Making HTTP POST request...');

      // Send notification via REST API with timeout
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
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print('⏰ HTTP request timed out after 30 seconds');
              throw Exception('Request timed out');
            },
          );

      print('📨 HTTP request completed!');
      print('📋 HTTP Response Status: ${response.statusCode}');
      print('📋 HTTP Response Headers: ${response.headers}');
      print('📋 HTTP Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ INSTANT notification sent successfully!');
        print('📊 OneSignal ID: ${responseData['id']}');
        print('📊 Recipients: ${responseData['recipients']}');
        print('📊 External ID: ${responseData['external_id']}');

        // Also update unread count (skip for testing)
        if (!skipPresenceCheck) {
          await _updateUnreadCount(recipientPlayerId, chatId);
        }

        // Store notification record for tracking
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
        print('❌ Response Headers: ${response.headers}');
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
      print('❌ Error sending instant notification: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // Store notification record for tracking and analytics
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
        'method': 'rest_api_instant',
        'sentAt': FieldValue.serverTimestamp(),
        'appId': _oneSignalAppId,
      });

      print('✅ Notification record stored');
    } catch (e) {
      print('❌ Error storing notification record: $e');
    }
  }

  // FALLBACK: Original Firestore method as backup
  static Future<void> sendMessageNotification({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
  }) async {
    // First try instant REST API method
    final instantSuccess = await sendInstantMessageNotification(
      recipientPlayerId: recipientPlayerId,
      senderName: senderName,
      message: message,
      chatId: chatId,
      senderId: senderId,
    );

    // If instant method fails, use Firestore backup
    if (!instantSuccess) {
      print('🔄 Instant notification failed, using Firestore backup...');
      await _sendFirestoreNotification(
        recipientPlayerId: recipientPlayerId,
        senderName: senderName,
        message: message,
        chatId: chatId,
        senderId: senderId,
      );
    }
  }

  // Original Firestore method as backup
  static Future<void> _sendFirestoreNotification({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
  }) async {
    try {
      print('📤 Creating Firestore notification request...');

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

      // Create notification request with enhanced data
      await FirebaseService.firestore.collection('notificationRequests').add({
        'type': 'new_message',
        'recipientPlayerId': recipientPlayerId,
        'title': '💕 $senderName',
        'message': notificationMessage,
        'additionalData': {
          'type': 'new_message',
          'chatId': chatId,
          'senderId': senderId,
          'senderName': senderName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'messagePreview': notificationMessage,
        },
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'appId': _oneSignalAppId,
        'priority': 'high',
        'sound': 'default',
        'badge': 1,
      });

      print('✅ Firestore notification request created');
    } catch (e) {
      print('❌ Error creating Firestore notification request: $e');
    }
  }

  // ENHANCED: Send typing notification instantly
  static Future<bool> sendTypingNotification({
    required String recipientPlayerId,
    required String senderName,
    required String chatId,
    required String senderId,
  }) async {
    try {
      print('✍️ Sending typing notification...');

      // Create typing notification payload
      final Map<String, dynamic> notificationPayload = {
        'app_id': _oneSignalAppId,
        'include_player_ids': [recipientPlayerId],
        'headings': {'en': '✍️ $senderName'},
        'contents': {'en': 'is typing...'},
        'data': {
          'type': 'typing',
          'chatId': chatId,
          'senderId': senderId,
          'senderName': senderName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        'priority': 5, // Lower priority for typing
        'ttl': 30, // Short TTL for typing notifications
        // Remove android_channel_id
        // 'android_channel_id': 'typing_channel',
        'delayed_option': 'immediate',
      };

      final response = await http.post(
        Uri.parse(_oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $_oneSignalRestApiKey',
        },
        body: jsonEncode(notificationPayload),
      );

      if (response.statusCode == 200) {
        print('✅ Typing notification sent successfully!');
        return true;
      } else {
        print('❌ Failed to send typing notification: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error sending typing notification: $e');
      return false;
    }
  }

  // ENHANCED: Batch send notifications to multiple recipients
  static Future<bool> sendBatchNotifications({
    required List<String> recipientPlayerIds,
    required String title,
    required String message,
    required Map<String, dynamic> additionalData,
  }) async {
    try {
      print(
        '📢 Sending batch notification to ${recipientPlayerIds.length} recipients...',
      );

      final Map<String, dynamic> notificationPayload = {
        'app_id': _oneSignalAppId,
        'include_player_ids': recipientPlayerIds,
        'headings': {'en': title},
        'contents': {'en': message},
        'data': additionalData,
        'priority': 10,
        'ttl': 259200,
        // Remove android_channel_id for compatibility
        // 'android_channel_id': 'high_importance_channel',
        'ios_badgeType': 'Increase',
        'ios_badgeCount': 1,
      };

      final response = await http.post(
        Uri.parse(_oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $_oneSignalRestApiKey',
        },
        body: jsonEncode(notificationPayload),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ Batch notification sent successfully!');
        print('📊 Recipients: ${responseData['recipients']}');
        return true;
      } else {
        print('❌ Failed to send batch notification: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error sending batch notification: $e');
      return false;
    }
  }

  // Enhanced logic to determine if notification should be sent
  static Future<bool> _shouldSendNotification({
    required String recipientPlayerId,
    required String chatId,
    required String senderId,
  }) async {
    try {
      print('🔍 Checking if notification should be sent...');

      // Get recipient user ID from player ID mapping
      final recipientUserId = await _getRecipientUserIdFromPlayerId(
        recipientPlayerId,
      );

      if (recipientUserId == null) {
        print('⚠️ Could not find user ID for player ID: $recipientPlayerId');
        print('✅ Sending notification anyway (default behavior)');
        return true; // Send notification anyway since we can't check status
      }

      print(
        '✅ Found recipient user ID: $recipientUserId for player ID: $recipientPlayerId',
      );

      // Check if recipient user document exists with timeout
      try {
        final recipientDoc = await FirebaseService.usersCollection
            .doc(recipientUserId)
            .get()
            .timeout(const Duration(seconds: 5));

        if (!recipientDoc.exists) {
          print('⚠️ Recipient user document not found for: $recipientUserId');
          print('✅ Sending notification anyway (document not found)');
          return true; // Send notification anyway
        }

        final recipientData = recipientDoc.data() as Map<String, dynamic>;

        // Check if recipient is actively viewing this specific chat
        final recipientActiveChat = recipientData['activeChatId'] as String?;
        if (recipientActiveChat != chatId) {
          print(
            '📱 Recipient is not viewing this chat (active: $recipientActiveChat, target: $chatId)',
          );
          print('✅ Sending notification - different chat');
          return true;
        }

        // Check app state
        final isRecipientAppInBackground =
            recipientData['isAppInBackground'] as bool? ?? false;
        if (isRecipientAppInBackground) {
          print('📱 Recipient app is in background');
          print('✅ Sending notification - app in background');
          return true;
        }

        // Try to check if recipient is online with timeout (non-blocking)
        try {
          final isRecipientOnline = await PresenceService.instance
              .isUserOnline(recipientUserId)
              .timeout(const Duration(seconds: 3));

          if (!isRecipientOnline) {
            print('📱 Recipient is offline');
            print('✅ Sending notification - user offline');
            return true;
          }

          // Check when was recipient last seen with timeout
          try {
            final lastSeen = await PresenceService.instance
                .getUserLastSeen(recipientUserId)
                .timeout(const Duration(seconds: 3));

            if (lastSeen != null) {
              final timeSinceLastSeen = DateTime.now().difference(lastSeen);

              // If last seen more than 30 seconds ago, send notification
              if (timeSinceLastSeen.inSeconds > 30) {
                print(
                  '📱 Recipient last seen ${timeSinceLastSeen.inSeconds}s ago',
                );
                print('✅ Sending notification - last seen > 30s ago');
                return true;
              }
            }
          } catch (e) {
            print('⚠️ Timeout getting last seen: $e');
            print('✅ Sending notification anyway (timeout on last seen)');
            return true;
          }
        } catch (e) {
          print('⚠️ Timeout checking online status: $e');
          print('✅ Sending notification anyway (timeout on presence check)');
          return true;
        }

        print('📱 Recipient is active in this chat and app is in foreground');
        print('❌ Skipping notification - user is actively viewing chat');
        return false;
      } catch (e) {
        print('⚠️ Timeout getting user document: $e');
        print('✅ Sending notification anyway (timeout on document fetch)');
        return true;
      }
    } catch (e) {
      print('❌ Error checking notification conditions: $e');
      print('✅ Sending notification anyway (default on error)');
      return true; // Default to sending notification on error
    }
  }

  // Update unread message count for user
  static Future<void> _updateUnreadCount(
    String recipientPlayerId,
    String chatId,
  ) async {
    try {
      final recipientUserId = await _getRecipientUserIdFromPlayerId(
        recipientPlayerId,
      );

      if (recipientUserId == null) {
        print(
          '⚠️ Cannot update unread count - user ID not found for player ID: $recipientPlayerId',
        );
        return;
      }

      // Check if user document exists before updating
      final userDoc =
          await FirebaseService.usersCollection.doc(recipientUserId).get();

      if (!userDoc.exists) {
        print(
          '⚠️ Cannot update unread count - user document does not exist: $recipientUserId',
        );
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

      // Query users collection to find user with this OneSignal player ID
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
      // Check if user document exists
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
      // Check if user document exists
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();

      if (!userDoc.exists) {
        print(
          '⚠️ Cannot set active chat - user document does not exist: $userId',
        );
        return;
      }

      await FirebaseService.usersCollection.doc(userId).update({
        'activeChatId': chatId,
        'lastChatActivity': FieldValue.serverTimestamp(),
      });

      // Also set locally
      setActiveChatId(chatId);

      print('✅ Updated user active chat ID: $chatId for user: $userId');
    } catch (e) {
      print('❌ Error updating user active chat ID: $e');
    }
  }

  static Future<void> debugUserPlayerIdMapping() async {
    try {
      print('🔍 Debugging user and player ID mapping...');

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        print('❌ No current user ID');
        return;
      }

      // Get current user document
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(currentUserId).get();

      if (currentUserDoc.exists) {
        final userData = currentUserDoc.data() as Map<String, dynamic>;
        final currentUserPlayerId = userData['oneSignalPlayerId'] as String?;

        print('📋 Current user ID: $currentUserId');
        print('📋 Current user player ID: $currentUserPlayerId');
        print('📋 Current user name: ${userData['displayName']}');

        // Get partner info
        final partnerId = userData['partnerId'] as String?;
        if (partnerId != null) {
          final partnerDoc =
              await FirebaseService.usersCollection.doc(partnerId).get();

          if (partnerDoc.exists) {
            final partnerData = partnerDoc.data() as Map<String, dynamic>;
            final partnerPlayerId = partnerData['oneSignalPlayerId'] as String?;

            print('📋 Partner user ID: $partnerId');
            print('📋 Partner player ID: $partnerPlayerId');
            print('📋 Partner name: ${partnerData['displayName']}');

            // Test mapping both ways
            if (partnerPlayerId != null) {
              final mappedUserId = await _getRecipientUserIdFromPlayerId(
                partnerPlayerId,
              );
              print(
                '📋 Mapping test - Player ID $partnerPlayerId maps to User ID: $mappedUserId',
              );
            }
          } else {
            print('❌ Partner document not found: $partnerId');
          }
        } else {
          print('⚠️ No partner ID found for current user');
        }
      } else {
        print('❌ Current user document not found: $currentUserId');
      }
    } catch (e) {
      print('❌ Error in debug user player ID mapping: $e');
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
        'lastAppStateUpdate': FieldValue.serverTimestamp(),
      });

      // Also set locally
      setAppForegroundState(!isInBackground);

      print('✅ Updated user app background state: $isInBackground');
    } catch (e) {
      print('❌ Error updating user app background state: $e');
    }
  }

  // Existing utility methods...
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

  static Future<void> debugNotificationSetup() async {
    try {
      print('🔍 Debugging OneSignal setup with REST API...');

      final settings = await getNotificationSettings();
      print('📋 Notification settings: $settings');

      final permission = await areNotificationsEnabled();
      print('📋 Permission granted: $permission');

      final playerId = await getPlayerId();
      print('📋 Player ID: $playerId');

      if (playerId == null) {
        print('⚠️ No player ID - trying to initialize...');
        await updateUserPlayerId();
      }

      if (playerId != null) {
        print('🧪 Testing INSTANT notification via REST API...');
        final success = await sendInstantMessageNotification(
          recipientPlayerId: playerId,
          senderName: 'Debug Test',
          message: '🚀 Testing instant REST API notification!',
          chatId: 'debug_chat',
          senderId: 'debug_sender',
        );

        if (success) {
          print('✅ REST API test notification sent successfully!');
        } else {
          print(
            '❌ REST API test notification failed - check your API key and setup',
          );
        }
      }
    } catch (e) {
      print('❌ Error in debug: $e');
    }
  }

  // Method to set external user ID for better user tracking
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

  // ENHANCED: Test REST API connection with proper authentication
  static Future<bool> testRestApiConnection() async {
    try {
      print('🧪 Testing OneSignal REST API connection...');
      print('🔑 API Key Length: ${_oneSignalRestApiKey.length}');
      print('🔑 API Key Format Valid: ${_isValidApiKey(_oneSignalRestApiKey)}');

      if (!_isValidApiKey(_oneSignalRestApiKey)) {
        print('❌ Invalid API key format - must be 20+ characters');
        return false;
      }

      // Test with app info endpoint first
      print('📡 Testing with app info endpoint...');
      final appResponse = await http.get(
        Uri.parse('https://onesignal.com/api/v1/apps/$_oneSignalAppId'),
        headers: {
          'Authorization': 'Basic $_oneSignalRestApiKey',
          'Accept': 'application/json',
        },
      );

      print('📋 App Info Response Status: ${appResponse.statusCode}');
      print('📋 App Info Response Body: ${appResponse.body}');

      if (appResponse.statusCode == 200) {
        print('✅ REST API connection successful!');
        final appData = jsonDecode(appResponse.body);
        print('📱 App Name: ${appData['name']}');
        print('📱 App ID: ${appData['id']}');
        return true;
      } else if (appResponse.statusCode == 403) {
        print('❌ API Key authentication failed (403)');
        print('❌ This usually means:');
        print('   1. Invalid API key');
        print('   2. API key doesn\'t have permission for this app');
        print('   3. Using User Auth Key instead of REST API Key');
        return false;
      } else {
        print('❌ REST API connection failed: ${appResponse.statusCode}');
        print('❌ Response: ${appResponse.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error testing REST API connection: $e');
      return false;
    }
  }

  // 🔑 HELP METHOD: Check API key and provide instructions
  static void checkApiKeySetup() {
    print('🔑 ═══════════════════════════════════════');
    print('🔑 ONESIGNAL API KEY SETUP CHECK');
    print('🔑 ═══════════════════════════════════════');
    print('📋 Current API Key: $_oneSignalRestApiKey');
    print('📋 Key Length: ${_oneSignalRestApiKey.length}');
    print('📋 Key Format Valid: ${_isValidApiKey(_oneSignalRestApiKey)}');
    print('📋 App ID: $_oneSignalAppId');
    print('');
    print('❗ POSSIBLE ISSUES:');
    print('1. Using USER AUTH KEY instead of REST API KEY');
    print('2. API key doesn\'t have permission for this app');
    print('3. API key is invalid or expired');
    print('');
    print('🔧 HOW TO GET CORRECT API KEY:');
    print('1. Go to OneSignal Dashboard');
    print('2. Select your app: $_oneSignalAppId');
    print('3. Go to Settings > Keys & IDs');
    print('4. Copy the "REST API Key" (NOT User Auth Key)');
    print('5. REST API Key should be ~50 characters long');
    print('');
    print('📱 Current app ID seems correct: $_oneSignalAppId');
    print('🔑 But API key might be wrong: $_oneSignalRestApiKey');
    print('');
    print('🧪 Run testRestApiConnection() to verify');
    print('🔑 ═══════════════════════════════════════');
  }

  // 🔑 METHOD: Test with custom API key
  static Future<bool> testWithCustomApiKey(String customApiKey) async {
    try {
      print('🧪 Testing with custom API key...');
      print('🔑 Custom Key Length: ${customApiKey.length}');

      if (!_isValidApiKey(customApiKey)) {
        print('❌ Custom API key format invalid');
        return false;
      }

      final response = await http.get(
        Uri.parse('https://onesignal.com/api/v1/apps/$_oneSignalAppId'),
        headers: {
          'Authorization': 'Basic $customApiKey',
          'Accept': 'application/json',
        },
      );

      print('📋 Custom Key Test Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ Custom API key works!');
        print('🔧 Replace the API key in your code with: $customApiKey');
        return true;
      } else {
        print('❌ Custom API key failed: ${response.statusCode}');
        print('❌ Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error testing custom API key: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getNotificationReport(
    String notificationId,
  ) async {
    try {
      print('📊 Getting notification report for: $notificationId');

      final response = await http.get(
        Uri.parse(
          'https://onesignal.com/api/v1/notifications/$notificationId?app_id=$_oneSignalAppId',
        ),
        headers: {'Authorization': 'Basic $_oneSignalRestApiKey'},
      );

      if (response.statusCode == 200) {
        final reportData = jsonDecode(response.body);
        print('✅ Notification report retrieved');
        print('📊 Successful: ${reportData['successful']}');
        print('📊 Failed: ${reportData['failed']}');
        print('📊 Converted: ${reportData['converted']}');
        return reportData;
      } else {
        print('❌ Failed to get notification report: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error getting notification report: $e');
      return null;
    }
  }

  // ENHANCED: Cancel a scheduled notification
  static Future<bool> cancelNotification(String notificationId) async {
    try {
      print('🗑️ Cancelling notification: $notificationId');

      final response = await http.delete(
        Uri.parse(
          'https://onesignal.com/api/v1/notifications/$notificationId?app_id=$_oneSignalAppId',
        ),
        headers: {'Authorization': 'Basic $_oneSignalRestApiKey'},
      );

      if (response.statusCode == 200) {
        print('✅ Notification cancelled successfully');
        return true;
      } else {
        print('❌ Failed to cancel notification: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error cancelling notification: $e');
      return false;
    }
  }

  // ENHANCED: Schedule a notification for later
  static Future<String?> scheduleNotification({
    required String recipientPlayerId,
    required String title,
    required String message,
    required DateTime sendTime,
    required Map<String, dynamic> additionalData,
  }) async {
    try {
      print('⏰ Scheduling notification for: $sendTime');

      final Map<String, dynamic> notificationPayload = {
        'app_id': _oneSignalAppId,
        'include_player_ids': [recipientPlayerId],
        'headings': {'en': title},
        'contents': {'en': message},
        'data': additionalData,
        'send_after': sendTime.toUtc().toIso8601String(),
        'priority': 10,
        'ttl': 259200,
        // Remove android_channel_id for compatibility
      };

      final response = await http.post(
        Uri.parse(_oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $_oneSignalRestApiKey',
        },
        body: jsonEncode(notificationPayload),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final notificationId = responseData['id'];
        print('✅ Notification scheduled successfully: $notificationId');
        return notificationId;
      } else {
        print('❌ Failed to schedule notification: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error scheduling notification: $e');
      return null;
    }
  }

  // 🧪 COMPREHENSIVE TEST METHOD - Call this from your screen
  static Future<Map<String, dynamic>> runComprehensiveNotificationTest({
    String? testPlayerId,
    String? testMessage,
  }) async {
    final Map<String, dynamic> testResults = {
      'timestamp': DateTime.now().toIso8601String(),
      'tests': <String, dynamic>{},
      'overall_success': false,
    };

    try {
      print('🧪 ═══════════════════════════════════════');
      print('🧪 COMPREHENSIVE NOTIFICATION TEST STARTED');
      print('🧪 ═══════════════════════════════════════');

      // Test 1: Check OneSignal initialization
      print('\n🔍 TEST 1: OneSignal Initialization');
      try {
        final playerId = await getPlayerId();
        if (playerId != null) {
          testResults['tests']['initialization'] = {
            'success': true,
            'playerId': playerId,
            'message': 'OneSignal initialized successfully',
          };
          print('✅ OneSignal Player ID: $playerId');
        } else {
          testResults['tests']['initialization'] = {
            'success': false,
            'message': 'Could not get OneSignal Player ID',
          };
          print('❌ Could not get OneSignal Player ID');
        }
      } catch (e) {
        testResults['tests']['initialization'] = {
          'success': false,
          'error': e.toString(),
        };
        print('❌ Initialization error: $e');
      }

      // Test 2: Check notification permissions
      print('\n🔍 TEST 2: Notification Permissions');
      try {
        final hasPermission = await areNotificationsEnabled();
        testResults['tests']['permissions'] = {
          'success': hasPermission,
          'hasPermission': hasPermission,
          'message':
              hasPermission
                  ? 'Notifications enabled'
                  : 'Notifications disabled',
        };
        print(
          hasPermission
              ? '✅ Notifications enabled'
              : '❌ Notifications disabled',
        );
      } catch (e) {
        testResults['tests']['permissions'] = {
          'success': false,
          'error': e.toString(),
        };
        print('❌ Permission check error: $e');
      }

      // Test 3: Test REST API connection
      print('\n🔍 TEST 3: REST API Connection');
      try {
        final apiSuccess = await testRestApiConnection();
        testResults['tests']['api_connection'] = {
          'success': apiSuccess,
          'message':
              apiSuccess
                  ? 'REST API connection successful'
                  : 'REST API connection failed',
        };
        print(
          apiSuccess
              ? '✅ REST API connection successful'
              : '❌ REST API connection failed',
        );
      } catch (e) {
        testResults['tests']['api_connection'] = {
          'success': false,
          'error': e.toString(),
        };
        print('❌ API connection error: $e');
      }

      // Test 4: Get current user info
      print('\n🔍 TEST 4: Current User Info');
      try {
        final currentUserId = FirebaseService.currentUserId;
        if (currentUserId != null) {
          final userDoc =
              await FirebaseService.usersCollection.doc(currentUserId).get();
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            final userPlayerId = userData['oneSignalPlayerId'] as String?;
            final userName = userData['displayName'] as String?;

            testResults['tests']['user_info'] = {
              'success': true,
              'userId': currentUserId,
              'playerId': userPlayerId,
              'displayName': userName,
              'message': 'User info retrieved successfully',
            };

            print('✅ Current User ID: $currentUserId');
            print('✅ Current User Player ID: $userPlayerId');
            print('✅ Current User Name: $userName');
          } else {
            testResults['tests']['user_info'] = {
              'success': false,
              'message': 'User document not found',
            };
            print('❌ User document not found');
          }
        } else {
          testResults['tests']['user_info'] = {
            'success': false,
            'message': 'No current user ID',
          };
          print('❌ No current user ID');
        }
      } catch (e) {
        testResults['tests']['user_info'] = {
          'success': false,
          'error': e.toString(),
        };
        print('❌ User info error: $e');
      }

      // Test 5: Get partner info
      print('\n🔍 TEST 5: Partner Info');
      try {
        final currentUserId = FirebaseService.currentUserId;
        if (currentUserId != null) {
          final userDoc =
              await FirebaseService.usersCollection.doc(currentUserId).get();
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            final partnerId = userData['partnerId'] as String?;

            if (partnerId != null) {
              final partnerDoc =
                  await FirebaseService.usersCollection.doc(partnerId).get();
              if (partnerDoc.exists) {
                final partnerData = partnerDoc.data() as Map<String, dynamic>;
                final partnerPlayerId =
                    partnerData['oneSignalPlayerId'] as String?;
                final partnerName = partnerData['displayName'] as String?;

                testResults['tests']['partner_info'] = {
                  'success': true,
                  'partnerId': partnerId,
                  'partnerPlayerId': partnerPlayerId,
                  'partnerName': partnerName,
                  'message': 'Partner info retrieved successfully',
                };

                print('✅ Partner ID: $partnerId');
                print('✅ Partner Player ID: $partnerPlayerId');
                print('✅ Partner Name: $partnerName');
              } else {
                testResults['tests']['partner_info'] = {
                  'success': false,
                  'message': 'Partner document not found',
                };
                print('❌ Partner document not found');
              }
            } else {
              testResults['tests']['partner_info'] = {
                'success': false,
                'message': 'No partner ID in user document',
              };
              print('❌ No partner ID in user document');
            }
          }
        }
      } catch (e) {
        testResults['tests']['partner_info'] = {
          'success': false,
          'error': e.toString(),
        };
        print('❌ Partner info error: $e');
      }

      // Test 6: Test notification to self (if no test player ID provided)
      print('\n🔍 TEST 6: Self Notification Test');
      try {
        final currentUserId = FirebaseService.currentUserId;
        String? targetPlayerId = testPlayerId;

        // If no test player ID provided, use current user's player ID
        if (targetPlayerId == null && currentUserId != null) {
          final userDoc =
              await FirebaseService.usersCollection.doc(currentUserId).get();
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            targetPlayerId = userData['oneSignalPlayerId'] as String?;
          }
        }

        if (targetPlayerId != null) {
          final testMsg =
              testMessage ??
              '🧪 Test notification from ${DateTime.now().toIso8601String()}';

          print('📤 Sending test notification to: $targetPlayerId');
          print('📝 Test message: $testMsg');

          final success = await sendInstantMessageNotification(
            recipientPlayerId: targetPlayerId,
            senderName: 'Test Sender',
            message: testMsg,
            chatId: 'test_chat_${DateTime.now().millisecondsSinceEpoch}',
            senderId: currentUserId ?? 'test_sender',
            skipPresenceCheck: true, // Skip presence check for testing
          );

          testResults['tests']['self_notification'] = {
            'success': success,
            'targetPlayerId': targetPlayerId,
            'testMessage': testMsg,
            'message':
                success
                    ? 'Test notification sent successfully'
                    : 'Test notification failed',
          };

          print(
            success
                ? '✅ Test notification sent successfully!'
                : '❌ Test notification failed',
          );
        } else {
          testResults['tests']['self_notification'] = {
            'success': false,
            'message': 'No target player ID available for testing',
          };
          print('❌ No target player ID available for testing');
        }
      } catch (e) {
        testResults['tests']['self_notification'] = {
          'success': false,
          'error': e.toString(),
        };
        print('❌ Self notification test error: $e');
      }

      // Test 7: Test notification to partner (if available)
      print('\n🔍 TEST 7: Partner Notification Test');
      try {
        final currentUserId = FirebaseService.currentUserId;
        if (currentUserId != null) {
          final userDoc =
              await FirebaseService.usersCollection.doc(currentUserId).get();
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            final partnerId = userData['partnerId'] as String?;

            if (partnerId != null) {
              final partnerDoc =
                  await FirebaseService.usersCollection.doc(partnerId).get();
              if (partnerDoc.exists) {
                final partnerData = partnerDoc.data() as Map<String, dynamic>;
                final partnerPlayerId =
                    partnerData['oneSignalPlayerId'] as String?;
                final currentUserName =
                    userData['displayName'] as String? ?? 'Test User';

                if (partnerPlayerId != null) {
                  final testMsg =
                      testMessage ??
                      '🧪 Test notification to partner from ${DateTime.now().toIso8601String()}';

                  print(
                    '📤 Sending test notification to partner: $partnerPlayerId',
                  );
                  print('📝 Test message: $testMsg');

                  final success = await sendInstantMessageNotification(
                    recipientPlayerId: partnerPlayerId,
                    senderName: currentUserName,
                    message: testMsg,
                    chatId:
                        'test_partner_chat_${DateTime.now().millisecondsSinceEpoch}',
                    senderId: currentUserId,
                    skipPresenceCheck: true, // Skip presence check for testing
                  );

                  testResults['tests']['partner_notification'] = {
                    'success': success,
                    'partnerPlayerId': partnerPlayerId,
                    'testMessage': testMsg,
                    'message':
                        success
                            ? 'Partner notification sent successfully'
                            : 'Partner notification failed',
                  };

                  print(
                    success
                        ? '✅ Partner notification sent successfully!'
                        : '❌ Partner notification failed',
                  );
                } else {
                  testResults['tests']['partner_notification'] = {
                    'success': false,
                    'message': 'Partner has no OneSignal player ID',
                  };
                  print('❌ Partner has no OneSignal player ID');
                }
              }
            } else {
              testResults['tests']['partner_notification'] = {
                'success': false,
                'message': 'No partner available for testing',
              };
              print('ℹ️ No partner available for testing');
            }
          }
        }
      } catch (e) {
        testResults['tests']['partner_notification'] = {
          'success': false,
          'error': e.toString(),
        };
        print('❌ Partner notification test error: $e');
      }

      // Test 8: Test typing notification
      print('\n🔍 TEST 8: Typing Notification Test');
      try {
        final currentUserId = FirebaseService.currentUserId;
        String? targetPlayerId = testPlayerId;

        // Use current user's player ID if no test ID provided
        if (targetPlayerId == null && currentUserId != null) {
          final userDoc =
              await FirebaseService.usersCollection.doc(currentUserId).get();
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            targetPlayerId = userData['oneSignalPlayerId'] as String?;
          }
        }

        if (targetPlayerId != null) {
          print('📤 Sending typing notification to: $targetPlayerId');

          final success = await sendTypingNotification(
            recipientPlayerId: targetPlayerId,
            senderName: 'Test Typer',
            chatId: 'test_typing_chat_${DateTime.now().millisecondsSinceEpoch}',
            senderId: currentUserId ?? 'test_sender',
          );

          testResults['tests']['typing_notification'] = {
            'success': success,
            'targetPlayerId': targetPlayerId,
            'message':
                success
                    ? 'Typing notification sent successfully'
                    : 'Typing notification failed',
          };

          print(
            success
                ? '✅ Typing notification sent successfully!'
                : '❌ Typing notification failed',
          );
        } else {
          testResults['tests']['typing_notification'] = {
            'success': false,
            'message': 'No target player ID available for typing test',
          };
          print('❌ No target player ID available for typing test');
        }
      } catch (e) {
        testResults['tests']['typing_notification'] = {
          'success': false,
          'error': e.toString(),
        };
        print('❌ Typing notification test error: $e');
      }

      // Calculate overall success
      final successfulTests =
          testResults['tests'].values
              .where((test) => test is Map && test['success'] == true)
              .length;
      final totalTests = testResults['tests'].length;
      testResults['overall_success'] =
          successfulTests >= (totalTests * 0.6); // 60% success rate
      testResults['success_rate'] = '$successfulTests/$totalTests';

      print('\n🧪 ═══════════════════════════════════════');
      print('🧪 TEST RESULTS SUMMARY');
      print('🧪 ═══════════════════════════════════════');
      print('📊 Tests passed: $successfulTests/$totalTests');
      print(
        '📊 Success rate: ${((successfulTests / totalTests) * 100).toStringAsFixed(1)}%',
      );
      print('📊 Overall success: ${testResults['overall_success']}');
      print('🧪 ═══════════════════════════════════════');

      return testResults;
    } catch (e, stackTrace) {
      print('❌ Comprehensive test error: $e');
      print('❌ Stack trace: $stackTrace');

      testResults['tests']['test_framework'] = {
        'success': false,
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
      };

      return testResults;
    }
  }

  // 🧪 FORCE SEND - Bypass all presence checks and send notification
  static Future<bool> forceSendNotification({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
  }) async {
    try {
      print('🚀 FORCE SENDING notification (bypassing all checks)...');
      print('📝 To Player ID: $recipientPlayerId');
      print('📝 From: $senderName');
      print('📝 Message: $message');

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

      print('🔧 Creating force notification payload...');

      // Create notification payload for OneSignal REST API
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
        'priority': 10,
        'ttl': 259200,
        'android_accent_color': 'FF9C27B0',
        'android_led_color': 'FF9C27B0',
        'android_sound': 'default',
        'ios_sound': 'default',
        'ios_badgeType': 'Increase',
        'ios_badgeCount': 1,
      };

      print('📡 Force sending HTTP request to OneSignal...');
      print('🔗 URL: $_oneSignalApiUrl');
      print('🔑 API Key Length: ${_oneSignalRestApiKey.length}');
      print('📦 Payload: ${jsonEncode(notificationPayload)}');

      print('🚀 Making FORCE HTTP POST request...');

      // Send notification via REST API with timeout
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
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print('⏰ FORCE HTTP request timed out after 30 seconds');
              throw Exception('Request timed out');
            },
          );

      print('📨 FORCE HTTP request completed!');
      print('📋 HTTP Response Status: ${response.statusCode}');
      print('📋 HTTP Response Headers: ${response.headers}');
      print('📋 HTTP Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ FORCE NOTIFICATION SENT SUCCESSFULLY!');
        print('📊 OneSignal ID: ${responseData['id']}');
        print('📊 Recipients: ${responseData['recipients']}');
        print('📊 External ID: ${responseData['external_id']}');

        return true;
      } else {
        print('❌ FORCE notification failed: ${response.statusCode}');
        print('❌ Response Headers: ${response.headers}');
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
      print('❌ Error in force send notification: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  static Future<bool> sendDirectTestNotification(
    String playerID,
    String message,
  ) async {
    try {
      print('🧪 ═══════════════════════════════════════');
      print('🧪 DIRECT TEST NOTIFICATION');
      print('🧪 ═══════════════════════════════════════');
      print('📝 Target Player ID: $playerID');
      print('📝 Test Message: $message');

      // Create the simplest possible notification payload
      final Map<String, dynamic> payload = {
        'app_id': _oneSignalAppId,
        'include_player_ids': [playerID],
        'contents': {'en': message},
        'headings': {'en': 'Direct Test'},
      };

      print('📦 Simple Payload: ${jsonEncode(payload)}');
      print('🚀 Sending direct HTTP request...');

      final response = await http
          .post(
            Uri.parse(_oneSignalApiUrl),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Basic $_oneSignalRestApiKey',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      print('📨 Direct test response received!');
      print('📋 Status: ${response.statusCode}');
      print('📋 Body: ${response.body}');
      print('📋 Headers: ${response.headers}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ DIRECT TEST SUCCESS!');
        print('📊 Notification ID: ${responseData['id']}');
        print('📊 Recipients: ${responseData['recipients']}');
        print('🧪 ═══════════════════════════════════════');
        return true;
      } else {
        print('❌ DIRECT TEST FAILED!');
        print('❌ Status: ${response.statusCode}');
        print('❌ Error: ${response.body}');
        print('🧪 ═══════════════════════════════════════');
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ DIRECT TEST EXCEPTION: $e');
      print('❌ Stack trace: $stackTrace');
      print('🧪 ═══════════════════════════════════════');
      return false;
    }
  }

  // 🧪 COMPREHENSIVE DEBUG METHOD
  static Future<void> debugEverything() async {
    print('🧪 ═══════════════════════════════════════');
    print('🧪 COMPREHENSIVE DEBUG SESSION');
    print('🧪 ═══════════════════════════════════════');

    try {
      // 1. Check current user
      final currentUserId = FirebaseService.currentUserId;
      print('👤 Current User ID: $currentUserId');

      if (currentUserId != null) {
        final userDoc =
            await FirebaseService.usersCollection.doc(currentUserId).get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          final currentUserPlayerId = userData['oneSignalPlayerId'] as String?;
          final userName = userData['displayName'] as String?;
          final partnerId = userData['partnerId'] as String?;

          print('👤 Current User Name: $userName');
          print('👤 Current User Player ID: $currentUserPlayerId');
          print('👤 Partner ID: $partnerId');

          // 2. Check partner
          if (partnerId != null) {
            final partnerDoc =
                await FirebaseService.usersCollection.doc(partnerId).get();
            if (partnerDoc.exists) {
              final partnerData = partnerDoc.data() as Map<String, dynamic>;
              final partnerPlayerId =
                  partnerData['oneSignalPlayerId'] as String?;
              final partnerName = partnerData['displayName'] as String?;

              print('👥 Partner Name: $partnerName');
              print('👥 Partner Player ID: $partnerPlayerId');

              // 3. Test direct notification to partner
              if (partnerPlayerId != null) {
                print('\n🧪 Testing direct notification to partner...');
                final partnerSuccess = await sendDirectTestNotification(
                  partnerPlayerId,
                  '🧪 Direct test to partner - ${DateTime.now().millisecondsSinceEpoch}',
                );
                print('👥 Partner test result: $partnerSuccess');
              }
            }
          }

          // 4. Test direct notification to self
          if (currentUserPlayerId != null) {
            print('\n🧪 Testing direct notification to self...');
            final selfSuccess = await sendDirectTestNotification(
              currentUserPlayerId,
              '🧪 Direct test to self - ${DateTime.now().millisecondsSinceEpoch}',
            );
            print('👤 Self test result: $selfSuccess');
          }
        }
      }

      // 5. Test API connection
      print('\n🧪 Testing API connection...');
      final apiSuccess = await testRestApiConnection();
      print('🔗 API test result: $apiSuccess');
    } catch (e, stackTrace) {
      print('❌ Debug session error: $e');
      print('❌ Stack trace: $stackTrace');
    }

    print('🧪 ═══════════════════════════════════════');
    print('🧪 DEBUG SESSION COMPLETE');
    print('🧪 ═══════════════════════════════════════');
  }

  static Future<bool> testNotificationToSelf({String? customMessage}) async {
    try {
      print('🧪 Testing notification to self...');

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

      print('📤 Sending test notification...');
      print('📝 Player ID: $playerId');
      print('📝 Message: $testMessage');

      final success = await sendInstantMessageNotification(
        recipientPlayerId: playerId,
        senderName: userName,
        message: testMessage,
        chatId: 'self_test_${DateTime.now().millisecondsSinceEpoch}',
        senderId: currentUserId,
        skipPresenceCheck: true,
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

  // 🧪 TEST NOTIFICATION TO PARTNER - Call this to test partner notifications
  static Future<bool> testNotificationToPartner({String? customMessage}) async {
    try {
      print('🧪 Testing notification to partner...');

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

      final success = await sendInstantMessageNotification(
        recipientPlayerId: partnerPlayerId,
        senderName: currentUserName,
        message: testMessage,
        chatId: 'partner_test_${DateTime.now().millisecondsSinceEpoch}',
        senderId: currentUserId,
        skipPresenceCheck: true,
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

    print('📚 ENHANCED NOTIFICATION SERVICE USAGE:');
    print('');
    print('🚀 INSTANT NOTIFICATIONS (Primary Method):');
    print('NotificationService.sendInstantMessageNotification(');
    print('  recipientPlayerId: "player-id",');
    print('  senderName: "John",');
    print('  message: "Hello!",');
    print('  chatId: "chat-123",');
    print('  senderId: "user-456"');
    print(');');
    print('');
    print('📱 FALLBACK (Automatic):');
    print('NotificationService.sendMessageNotification(');
    print('  // Same parameters - will try REST API first, then Firestore');
    print(');');
    print('');
    print('✍️ TYPING NOTIFICATIONS:');
    print('NotificationService.sendTypingNotification(');
    print('  recipientPlayerId: "player-id",');
    print('  senderName: "John",');
    print('  chatId: "chat-123",');
    print('  senderId: "user-456"');
    print(');');
    print('');
    print('🧪 TESTING:');
    print('await NotificationService.testRestApiConnection();');
    print('await NotificationService.debugNotificationSetup();');
    print('');
    print('⚠️ IMPORTANT: Add http package to pubspec.yaml:');
    print('dependencies:');
    print('  http: ^1.1.0');
  }
}
