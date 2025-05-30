import 'package:flutter/material.dart';
import 'package:onlyus/core/services/pressence_service.dart';
import '../services/firebase_service.dart';
import '../services/chat_service.dart';

class AppLifecycleService extends WidgetsBindingObserver {
  // Singleton instance
  static AppLifecycleService? _instance;
  static AppLifecycleService get instance =>
      _instance ??= AppLifecycleService._();
  AppLifecycleService._();

  bool _isInitialized = false;
  AppLifecycleState? _currentState;

  // Initialize the lifecycle observer
  void initialize() {
    if (!_isInitialized) {
      WidgetsBinding.instance.addObserver(this);
      _isInitialized = true;
      _currentState = WidgetsBinding.instance.lifecycleState;

      // Initialize chat service
      ChatService.instance.initialize();

      print('✅ App lifecycle service initialized with state: $_currentState');
    }
  }

  // Dispose the lifecycle observer
  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;

      // Dispose chat service
      ChatService.instance.dispose();

      print('✅ App lifecycle service disposed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Only process if state actually changed
    if (_currentState == state) return;

    final previousState = _currentState;
    _currentState = state;

    print('📱 App lifecycle changed from $previousState to $state');

    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed(previousState);
        break;
      case AppLifecycleState.paused:
        _handleAppPaused(previousState);
        break;
      case AppLifecycleState.inactive:
        _handleAppInactive(previousState);
        break;
      case AppLifecycleState.detached:
        _handleAppDetached(previousState);
        break;
      case AppLifecycleState.hidden:
        _handleAppHidden(previousState);
        break;
    }
  }

  // Handle when app is resumed (user actively using the app)
  void _handleAppResumed(AppLifecycleState? previousState) async {
    try {
      print('✅ App resumed - setting user online');

      // Set user online in both Firestore and Realtime Database
      await FirebaseService.onAppResumed();

      // Clear any typing status that might be stuck
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.updateTypingStatus(false);
      }

      // Mark messages as read if coming from background
      if (previousState == AppLifecycleState.paused ||
          previousState == AppLifecycleState.hidden) {
        await _markMessagesAsReadWithDelay();
      }

      print('✅ App resume handling completed');
    } catch (e) {
      print('❌ Error handling app resume: $e');
    }
  }

  // Handle when app is paused (app in background but still running)
  void _handleAppPaused(AppLifecycleState? previousState) async {
    try {
      print('⚠️ App paused - setting user offline');

      // Clear typing status before going offline
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.updateTypingStatus(false);
      }

      // Set user offline in both Firestore and Realtime Database
      await FirebaseService.onAppPaused();

      // Additional cleanup for paused state
      await _performBackgroundCleanup();

      print('✅ App pause handling completed');
    } catch (e) {
      print('❌ Error handling app pause: $e');
    }
  }

  // Handle when app is inactive (transitioning between states)
  void _handleAppInactive(AppLifecycleState? previousState) async {
    try {
      print('⚠️ App inactive (transitioning)');

      // For inactive state, we usually don't change online status
      // as it's often just a temporary transition (like receiving a call)

      // However, clear typing status to avoid stuck indicators
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.updateTypingStatus(false);
      }
    } catch (e) {
      print('❌ Error handling app inactive: $e');
    }
  }

  // Handle when app is detached (app is terminated)
  void _handleAppDetached(AppLifecycleState? previousState) async {
    try {
      print('❌ App detached - cleaning up');

      // Clear typing status
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.updateTypingStatus(false);
      }

      // Set user offline and cleanup
      await PresenceService.instance.signOut();

      // Dispose chat service
      ChatService.instance.dispose();

      print('✅ App detached cleanup completed');
    } catch (e) {
      print('❌ Error handling app detached: $e');
    }
  }

  // Handle when app is hidden (on some platforms)
  void _handleAppHidden(AppLifecycleState? previousState) async {
    try {
      print('🔒 App hidden');

      // Clear typing status
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.updateTypingStatus(false);
      }

      // Similar to paused state
      await FirebaseService.onAppPaused();

      print('✅ App hidden handling completed');
    } catch (e) {
      print('❌ Error handling app hidden: $e');
    }
  }

  // Helper method to mark messages as read with delay
  Future<void> _markMessagesAsReadWithDelay() async {
    try {
      // Wait a bit to ensure the app is fully resumed
      await Future.delayed(const Duration(milliseconds: 500));

      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.markMessagesAsRead();
        print('✅ Messages marked as read after resume');
      }
    } catch (e) {
      print('❌ Error marking messages as read: $e');
    }
  }

  // Helper method to perform background cleanup
  Future<void> _performBackgroundCleanup() async {
    try {
      // Clear any temporary data that shouldn't persist in background
      // You can add more cleanup logic here as needed

      // Example: Clear any sensitive data from memory
      // Clear any active timers
      // Pause any ongoing operations

      print('✅ Background cleanup completed');
    } catch (e) {
      print('❌ Error in background cleanup: $e');
    }
  }

  // Manual methods to force online/offline state
  Future<void> forceOnline() async {
    try {
      await FirebaseService.onAppResumed();
      print('✅ Forced user online');
    } catch (e) {
      print('❌ Error forcing user online: $e');
    }
  }

  Future<void> forceOffline() async {
    try {
      // Clear typing status first
      if (ChatService.instance.activeChatId != null) {
        await ChatService.instance.updateTypingStatus(false);
      }

      await FirebaseService.onAppPaused();
      print('✅ Forced user offline');
    } catch (e) {
      print('❌ Error forcing user offline: $e');
    }
  }

  // Check current app state
  AppLifecycleState get currentState =>
      _currentState ??
      WidgetsBinding.instance.lifecycleState ??
      AppLifecycleState.resumed;

  bool get isAppActive => currentState == AppLifecycleState.resumed;

  bool get isAppInBackground =>
      currentState == AppLifecycleState.paused ||
      currentState == AppLifecycleState.hidden;

  bool get isAppInactive => currentState == AppLifecycleState.inactive;

  bool get isAppDetached => currentState == AppLifecycleState.detached;

  // Helper method to check if app state transition is valid
  bool isValidTransition(AppLifecycleState? from, AppLifecycleState to) {
    // Add any custom validation logic here if needed
    return true;
  }

  // Method to get state duration (how long in current state)
  Duration get timeInCurrentState {
    // You can implement this by tracking state change timestamps
    // For now, return a default duration
    return const Duration(seconds: 0);
  }
}
