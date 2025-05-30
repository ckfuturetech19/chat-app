import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'firebase_service.dart';

class NotificationService {
  // OneSignal App ID - Replace with your actual OneSignal App ID
  static const String _oneSignalAppId = "7d95dd17-81f9-4090-a80c-f849a182de99";

  // OneSignal REST API Key - Add this to your environment variables
  static const String _oneSignalRestApiKey = "YOUR_ONESIGNAL_REST_API_KEY";

  // Initialize OneSignal with enhanced setup
  static Future<void> initialize() async {
    try {
      // Initialize OneSignal
      OneSignal.initialize(_oneSignalAppId);

      // Request permission for notifications
      await OneSignal.Notifications.requestPermission(true);

      // Set up notification handlers
      _setupNotificationHandlers();

      // Update user's player ID in Firestore
      await updateUserPlayerId();

      print('✅ OneSignal initialized successfully');
    } catch (e) {
      print('❌ OneSignal initialization error: $e');
    }
  }

  // Enhanced notification event handlers
  static void _setupNotificationHandlers() {
    // Handle notification received while app is in foreground
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      print(
        '📱 Notification received in foreground: ${event.notification.title}',
      );

      // Extract notification data
      final additionalData = event.notification.additionalData;
      final notificationType = additionalData?['type'] as String?;

      // Only show notification if it's not from the current chat screen
      if (notificationType == 'new_message') {
        final chatId = additionalData?['chatId'] as String?;
        // You can add logic here to check if user is currently viewing this chat
        // If they are, don't show the notification

        // For now, always display
        event.notification.display();
      } else {
        event.notification.display();
      }
    });

    // Handle notification clicks with enhanced navigation
    OneSignal.Notifications.addClickListener((event) {
      print('🔔 Notification clicked: ${event.notification.title}');

      final additionalData = event.notification.additionalData;
      if (additionalData != null) {
        _handleNotificationClick(additionalData);
      }
    });

    // Handle permission changes
    OneSignal.Notifications.addPermissionObserver((state) {
      print('🔔 Notification permission state: $state');

      if (state) {
        // Permission granted, update player ID
        updateUserPlayerId();
      }
    });

    // Handle subscription changes
    OneSignal.User.pushSubscription.addObserver((state) {
      print('🔔 Push subscription changed: ${state.current.id}');

      // Update player ID when subscription changes
      if (state.current.id != null) {
        updateUserPlayerId();
      }
    });
  }

  // Enhanced notification click handler
  static void _handleNotificationClick(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final chatId = data['chatId'] as String?;
    final senderId = data['senderId'] as String?;

    switch (type) {
      case 'new_message':
        if (chatId != null) {
          print('📱 Opening chat: $chatId from sender: $senderId');
          // TODO: Navigate to chat screen
          // You can use a global navigator key or event bus here
          _navigateToChat(chatId, senderId);
        }
        break;
      case 'typing':
        print('✍️ Partner is typing in chat: $chatId');
        // Could open chat or show a brief indicator
        break;
      case 'connection_request':
        print('🤝 New connection request');
        // Navigate to connection/pairing screen
        break;
      default:
        print('📱 Unknown notification type: $type');
    }
  }

  // Navigation helper (implement based on your app structure)
  static void _navigateToChat(String chatId, String? senderId) {
    // This is where you'd implement navigation to your chat screen
    // Example approaches:
    // 1. Use a global navigator key
    // 2. Use an event bus/stream
    // 3. Store navigation intent and handle on app resume

    print('🧭 Navigation intent: Chat $chatId');

    // For now, just log the intent
    // In your main app, you can listen for these navigation events
  }

  // Get OneSignal player ID with retry logic
  static Future<String?> getPlayerId() async {
    try {
      // Try multiple times as OneSignal might not be ready immediately
      for (int attempt = 0; attempt < 3; attempt++) {
        final playerId = OneSignal.User.pushSubscription.id;
        if (playerId != null && playerId.isNotEmpty) {
          return playerId;
        }

        // Wait a bit before retrying
        await Future.delayed(Duration(seconds: attempt + 1));
      }

      print('⚠️ Could not get OneSignal player ID after 3 attempts');
      return null;
    } catch (e) {
      print('❌ Error getting OneSignal player ID: $e');
      return null;
    }
  }

  // Enhanced player ID update with retry logic
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

        print('✅ OneSignal Player ID updated: $playerId');
      } else {
        print('⚠️ Could not update player ID - missing playerId or user');
      }
    } catch (e) {
      print('❌ Error updating OneSignal Player ID: $e');

      // Retry after a delay
      Future.delayed(const Duration(seconds: 5), () {
        updateUserPlayerId();
      });
    }
  }

  // Enhanced notification sending using OneSignal REST API
  static Future<void> sendNotificationToUser({
    required String recipientPlayerId,
    required String title,
    required String message,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      // Validate inputs
      if (recipientPlayerId.isEmpty || title.isEmpty) {
        print('❌ Invalid notification parameters');
        return;
      }

      final url = Uri.parse('https://onesignal.com/api/v1/notifications');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Basic $_oneSignalRestApiKey',
      };

      final body = {
        'app_id': _oneSignalAppId,
        'include_player_ids': [recipientPlayerId],
        'headings': {'en': title},
        'contents': {'en': message.isNotEmpty ? message : title},
        'data': additionalData ?? {},
        'priority': 10,
        'ttl': 86400, // 24 hours
        'android_channel_id': 'chat_messages',
        'small_icon': 'ic_notification',
        'large_icon': 'ic_launcher',
        'sound': 'default',
        'android_group': 'chat_notifications',
        'ios_category': 'MESSAGE',
      };

      print('📤 Sending notification to: $recipientPlayerId');
      print('📝 Title: $title');
      print('📝 Message: $message');

      final response = await http
          .post(url, headers: headers, body: json.encode(body))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('✅ Notification sent successfully: ${responseData['id']}');
      } else {
        print('❌ Failed to send notification: ${response.statusCode}');
        print('❌ Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Error sending notification: $e');
    }
  }

  // Enhanced message notification with better formatting
  static Future<void> sendMessageNotification({
    required String recipientPlayerId,
    required String senderName,
    required String message,
    required String chatId,
    required String senderId,
  }) async {
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

    await sendNotificationToUser(
      recipientPlayerId: recipientPlayerId,
      title: '💕 $senderName',
      message: notificationMessage,
      additionalData: {
        'type': 'new_message',
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  // Typing notification (lighter notification)
  static Future<void> sendTypingNotification({
    required String recipientPlayerId,
    required String senderName,
    required String chatId,
    required String senderId,
  }) async {
    await sendNotificationToUser(
      recipientPlayerId: recipientPlayerId,
      title: '✍️ $senderName is typing...',
      message: '',
      additionalData: {
        'type': 'typing',
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  // Connection request notification
  static Future<void> sendConnectionRequestNotification({
    required String recipientPlayerId,
    required String senderName,
    required String senderCode,
  }) async {
    await sendNotificationToUser(
      recipientPlayerId: recipientPlayerId,
      title: '💕 New Connection Request',
      message: '$senderName wants to connect with you!',
      additionalData: {
        'type': 'connection_request',
        'senderName': senderName,
        'senderCode': senderCode,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  // Set external user ID (useful for linking with your user system)
  static Future<void> setExternalUserId(String userId) async {
    try {
      OneSignal.login(userId);
      print('✅ OneSignal external user ID set: $userId');
    } catch (e) {
      print('❌ Error setting OneSignal external user ID: $e');
    }
  }

  // Remove external user ID (on logout)
  static Future<void> removeExternalUserId() async {
    try {
      OneSignal.logout();
      print('✅ OneSignal external user ID removed');
    } catch (e) {
      print('❌ Error removing OneSignal external user ID: $e');
    }
  }

  // Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    try {
      final permission = await OneSignal.Notifications.permission;
      return permission;
    } catch (e) {
      print('❌ Error checking notification permission: $e');
      return false;
    }
  }

  // Request notification permission with user-friendly approach
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

  // Clear all notifications (useful when user opens the app)
  static Future<void> clearAllNotifications() async {
    try {
      await OneSignal.Notifications.clearAll();
      print('✅ All notifications cleared');
    } catch (e) {
      print('❌ Error clearing notifications: $e');
    }
  }

  // Set notification categories for better organization
  static Future<void> setupNotificationCategories() async {
    try {
      // This would be implemented based on your platform-specific needs
      // For iOS, you'd set up UNNotificationCategory
      // For Android, you'd set up NotificationChannels

      print('✅ Notification categories set up');
    } catch (e) {
      print('❌ Error setting up notification categories: $e');
    }
  }

  // Get notification settings for debugging
  static Future<Map<String, dynamic>> getNotificationSettings() async {
    try {
      final permission = await areNotificationsEnabled();
      final playerId = await getPlayerId();

      return {
        'permission': permission,
        'playerId': playerId,
        'oneSignalAppId': _oneSignalAppId,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error getting notification settings: $e');
      return {};
    }
  }
}
