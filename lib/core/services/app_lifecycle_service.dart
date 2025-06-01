import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:onlyus/core/services/notification_service.dart';
import 'package:onlyus/core/services/pressence_service.dart';
import '../services/firebase_service.dart';
import '../services/chat_service.dart';

class AppLifecycleService extends WidgetsBindingObserver {
  // Singleton instance
  static AppLifecycleService? _instance;
  static AppLifecycleService get instance =>
      _instance ??= AppLifecycleService._();
  AppLifecycleService._();

  // State management
  Timer? _presenceTimer;
  Timer? _messageReadTimer;
  Timer? _connectionMonitorTimer;
  
  bool _isInitialized = false;
  AppLifecycleState? _currentState;
  AppLifecycleState? _previousState;
  DateTime? _lastStateChange;
  
  // Track background time
  DateTime? _backgroundTime;
  static const Duration _refreshThreshold = Duration(minutes: 1);
  
  // Connection state
  bool _wasConnectedBeforePause = true;

  /// Initialize the lifecycle observer
  void initialize() {
    if (!_isInitialized) {
      WidgetsBinding.instance.addObserver(this);
      _isInitialized = true;
      _currentState = WidgetsBinding.instance.lifecycleState;
      _lastStateChange = DateTime.now();

      // Initialize services
      ChatService.instance.initialize();
      
      // Start monitoring
      _startPresenceUpdates();
      _startMessageReadTracking();
      _startConnectionMonitoring();

      print('✅ App lifecycle service initialized');
    }
  }

  /// Dispose the lifecycle observer
  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
      
      // Cancel all timers
      _presenceTimer?.cancel();
      _messageReadTimer?.cancel();
      _connectionMonitorTimer?.cancel();

      // Dispose services
      ChatService.instance.dispose();

      print('✅ App lifecycle service disposed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Track state changes
    _previousState = _currentState;
    _currentState = state;
    _lastStateChange = DateTime.now();

    print('📱 App lifecycle: $_previousState → $_currentState');

    // Handle state transitions
    _handleStateTransition(_previousState, state);
  }

  /// Handle state transitions with proper logic
  void _handleStateTransition(AppLifecycleState? from, AppLifecycleState to) {
    switch (to) {
      case AppLifecycleState.resumed:
        _handleAppResumed(from);
        break;
      case AppLifecycleState.paused:
        _handleAppPaused(from);
        break;
      case AppLifecycleState.inactive:
        _handleAppInactive(from);
        break;
      case AppLifecycleState.detached:
        _handleAppDetached(from);
        break;
      case AppLifecycleState.hidden:
        _handleAppHidden(from);
        break;
    }
  }

  /// Handle app resumed state
  void _handleAppResumed(AppLifecycleState? previousState) async {
    try {
      print('✅ App resumed from ${previousState?.name ?? 'unknown'}');

      // Calculate time spent in background
      Duration? timeInBackground;
      if (_backgroundTime != null) {
        timeInBackground = DateTime.now().difference(_backgroundTime!);
        print('⏱️ Time in background: ${timeInBackground.inSeconds} seconds');
      }

      // Force online status update
      await _forceOnlineStatus();

      // Clear notifications
      await NotificationService.clearAllNotifications();

      // Refresh data if needed
      if (timeInBackground != null && timeInBackground > _refreshThreshold) {
        await _refreshAppData();
      }

      // Mark messages as read if in chat
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.markMessagesAsReadEnhanced();
      }

      // Restart monitoring
      _startPresenceUpdates();
      _startMessageReadTracking();

      print('✅ App resume handled successfully');
    } catch (e) {
      print('❌ Error handling app resume: $e');
    }
  }

  /// Handle app paused state
  void _handleAppPaused(AppLifecycleState? previousState) async {
    try {
      print('⏸️ App paused from ${previousState?.name ?? 'unknown'}');

      // Record background time
      _backgroundTime = DateTime.now();

      // Store connection state
      _wasConnectedBeforePause = FirebaseService.isFullyConnected;

      // Stop timers
      _presenceTimer?.cancel();
      _messageReadTimer?.cancel();

      // Clear typing status
      await _clearTypingStatus();

      // Force offline status update
      await _forceOfflineStatus();

      print('✅ App pause handled successfully');
    } catch (e) {
      print('❌ Error handling app pause: $e');
    }
  }

  /// Handle app inactive state
  void _handleAppInactive(AppLifecycleState? previousState) async {
    try {
      print('⚠️ App inactive (transitioning)');

      // Just update last seen, don't go offline yet
      await PresenceService.instance.updateLastSeen();

      // Clear typing status
      await _clearTypingStatus();
    } catch (e) {
      print('❌ Error handling app inactive: $e');
    }
  }

  /// Handle app detached state
  void _handleAppDetached(AppLifecycleState? previousState) async {
    try {
      print('🔴 App detached - cleaning up');

      // Final cleanup
      await _performFinalCleanup();
    } catch (e) {
      print('❌ Error handling app detached: $e');
    }
  }

  /// Handle app hidden state
  void _handleAppHidden(AppLifecycleState? previousState) async {
    try {
      print('🔒 App hidden');

      // Similar to paused
       _handleAppPaused(previousState);
    } catch (e) {
      print('❌ Error handling app hidden: $e');
    }
  }

  /// Force online status update
  Future<void> _forceOnlineStatus() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return;

      // Update presence service
      await PresenceService.instance.setUserOnline();

      // Force update Firestore
      await FirebaseService.usersCollection.doc(currentUserId).update({
        'isOnline': true,
        'isAppInBackground': false,
        'lastSeen': FieldValue.serverTimestamp(),
        'appState': 'active',
        'appStateUpdatedAt': FieldValue.serverTimestamp(),
      });

      // Update notification service
      await NotificationService.setUserAppBackgroundState(currentUserId, false);
      NotificationService.setAppForegroundState(true);

      print('✅ Forced online status update');
    } catch (e) {
      print('❌ Error forcing online status: $e');
    }
  }

  /// Force offline status update
  Future<void> _forceOfflineStatus() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return;

      // Update notification service first
      NotificationService.setAppForegroundState(false);
      await NotificationService.setUserAppBackgroundState(currentUserId, true);
      await NotificationService.setUserActiveChatId(currentUserId, null);

      // Update presence service
      await PresenceService.instance.setUserOffline();

      // Force update Firestore
      await FirebaseService.usersCollection.doc(currentUserId).update({
        'isOnline': false,
        'isAppInBackground': true,
        'activeChatId': null,
        'lastSeen': FieldValue.serverTimestamp(),
        'appState': 'background',
        'appStateUpdatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Forced offline status update');
    } catch (e) {
      print('❌ Error forcing offline status: $e');
    }
  }

  /// Clear typing status
  Future<void> _clearTypingStatus() async {
    try {
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.updateTypingStatus(false);
      }
    } catch (e) {
      print('⚠️ Error clearing typing status: $e');
    }
  }

  /// Refresh app data after being in background
  Future<void> _refreshAppData() async {
    try {
      print('🔄 Refreshing app data...');

      // Refresh presence for current user
      if (FirebaseService.currentUserId != null) {
        await PresenceService.instance.refreshUserPresence(
          FirebaseService.currentUserId!,
        );
      }

      // Check for missed messages
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.checkForMissedMessages();
      }

      print('✅ App data refreshed');
    } catch (e) {
      print('❌ Error refreshing app data: $e');
    }
  }

  /// Start presence updates
  void _startPresenceUpdates() {
    _presenceTimer?.cancel();
    
    // Update presence every 30 seconds
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (isAppActive && FirebaseService.currentUserId != null) {
        try {
          // Update presence
          await PresenceService.instance.updateLastSeen();
          
          // Update Firestore heartbeat
          await FirebaseService.usersCollection
              .doc(FirebaseService.currentUserId!)
              .update({
                'lastSeen': FieldValue.serverTimestamp(),
                'presenceHeartbeat': FieldValue.serverTimestamp(),
              });
          
          print('💓 Presence heartbeat sent');
        } catch (e) {
          print('❌ Error in presence heartbeat: $e');
        }
      }
    });
  }

  /// Start message read tracking
  void _startMessageReadTracking() {
    _messageReadTimer?.cancel();
    
    // Check every 2 seconds when chat is active
    _messageReadTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (isAppActive && ChatService.instance.activeChatId != null) {
        try {
          final currentUserId = FirebaseService.currentUserId;
          final chatId = ChatService.instance.activeChatId;
          
          if (currentUserId != null && chatId != null) {
            // Mark messages as read
            await FirebaseService.markMessagesAsRead(chatId, currentUserId);
            
            // Check partner presence for instant read receipts
            await _checkPartnerPresenceForReadReceipts(chatId, currentUserId);
          }
        } catch (e) {
          print('❌ Error in message read tracking: $e');
        }
      }
    });
  }

  /// Start connection monitoring
  void _startConnectionMonitoring() {
    _connectionMonitorTimer?.cancel();
    
    // Monitor connection health every 10 seconds
    _connectionMonitorTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) async {
        if (isAppActive) {
          final health = await FirebaseService.checkServicesHealth();
          
          bool allHealthy = health.values.every((v) => v);
          if (!allHealthy) {
            print('⚠️ Connection issues detected: $health');
            
            // Try to reconnect unhealthy services
            if (!health['realtimeDatabase']!) {
              FirebaseService.realtimeDatabase.goOnline();
            }
            
            if (!health['firestore']!) {
              await FirebaseService.firestore.enableNetwork();
            }
            
            if (!health['presence']!) {
              await PresenceService.instance.initialize();
            }
          }
        }
      },
    );
  }

  /// Check partner presence for instant read receipts
  Future<void> _checkPartnerPresenceForReadReceipts(
    String chatId,
    String currentUserId,
  ) async {
    try {
      final partnerInfo = await ChatService.instance.getPartnerInfo(currentUserId);
      if (partnerInfo == null) return;
      
      final partnerId = partnerInfo['partnerId'] as String;
      
      // Check if partner is also in the same chat
      final partnerDoc = await FirebaseService.usersCollection
          .doc(partnerId)
          .get();
          
      if (partnerDoc.exists) {
        final partnerData = partnerDoc.data() as Map<String, dynamic>;
        final partnerActiveChat = partnerData['activeChatId'] as String?;
        final isPartnerOnline = await PresenceService.instance.isUserOnline(partnerId);
        
        // If both users are in the same chat, mark messages as read instantly
        if (isPartnerOnline && partnerActiveChat == chatId) {
          await FirebaseService.markMessagesAsRead(chatId, partnerId);
          print('✅ Instant read receipts: Both users in chat');
        }
      }
    } catch (e) {
      print('⚠️ Error checking partner presence: $e');
    }
  }

  /// Perform final cleanup
  Future<void> _performFinalCleanup() async {
    try {
      // Clear typing status
      await _clearTypingStatus();
      
      // Force offline status
      await _forceOfflineStatus();
      
      // Sign out from presence
      await PresenceService.instance.signOut();
      
      // Dispose chat service
      ChatService.instance.dispose();
      
      print('✅ Final cleanup completed');
    } catch (e) {
      print('❌ Error in final cleanup: $e');
    }
  }

  /// Manual force online (for testing)
  Future<void> forceOnline() async {
    await _forceOnlineStatus();
  }

  /// Manual force offline (for testing)
  Future<void> forceOffline() async {
    await _forceOfflineStatus();
  }

  /// Get current state info
  AppLifecycleState get currentState =>
      _currentState ?? AppLifecycleState.resumed;

  bool get isAppActive => currentState == AppLifecycleState.resumed;

  bool get isAppInBackground =>
      currentState == AppLifecycleState.paused ||
      currentState == AppLifecycleState.hidden;

  Duration? get timeSinceLastStateChange =>
      _lastStateChange != null
          ? DateTime.now().difference(_lastStateChange!)
          : null;

  /// Get debug info
  Map<String, dynamic> getDebugInfo() {
    return {
      'isInitialized': _isInitialized,
      'currentState': currentState.name,
      'previousState': _previousState?.name,
      'lastStateChange': _lastStateChange?.toIso8601String(),
      'backgroundTime': _backgroundTime?.toIso8601String(),
      'timeSinceLastChange': timeSinceLastStateChange?.inSeconds,
      'presenceTimerActive': _presenceTimer?.isActive ?? false,
      'messageReadTimerActive': _messageReadTimer?.isActive ?? false,
      'connectionMonitorActive': _connectionMonitorTimer?.isActive ?? false,
      'firebaseHealth': FirebaseService.getDebugInfo(),
    };
  }
}