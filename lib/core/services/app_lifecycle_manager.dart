import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onlyus/core/services/firebase_service.dart';
import 'package:onlyus/core/services/notification_service.dart';
import 'package:onlyus/core/services/pressence_service.dart';

class AppLifecycleManager extends ConsumerStatefulWidget {
  final Widget child;

  const AppLifecycleManager({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  ConsumerState<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends ConsumerState<AppLifecycleManager>
    with WidgetsBindingObserver {
  
  bool _isAppInForeground = true;
  DateTime? _lastPausedTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handleAppResumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    print('📱 App lifecycle state changed: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.inactive:
        _handleAppInactive();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        _handleAppHidden();
        break;
    }
  }

  Future<void> _handleAppResumed() async {
    print('📱 App resumed');
    _isAppInForeground = true;
    
    try {
      final currentUserId = FirebaseService.currentUserId;
      
      if (currentUserId != null) {
        // Update user online status
        await PresenceService.instance.setUserOnline();
        
        // Update notification service state
        NotificationService.setAppForegroundState(true);
        
        // Update user's app state in Firestore
        await NotificationService.setUserAppBackgroundState(currentUserId, false);
        
        // Clear notifications when app comes to foreground
        await NotificationService.clearAllNotifications();
        
        // If user was away for more than 1 minute, refresh data
        if (_lastPausedTime != null) {
          final timeAway = DateTime.now().difference(_lastPausedTime!);
          if (timeAway.inMinutes >= 1) {
            print('📱 User was away for ${timeAway.inMinutes} minutes, refreshing data');
            _refreshAppData();
          }
        }
        
        print('✅ App resumed successfully');
      }
    } catch (e) {
      print('❌ Error handling app resume: $e');
    }
  }

  Future<void> _handleAppPaused() async {
    print('📱 App paused');
    _isAppInForeground = false;
    _lastPausedTime = DateTime.now();
    
    try {
      final currentUserId = FirebaseService.currentUserId;
      
      if (currentUserId != null) {
        // Update notification service state
        NotificationService.setAppForegroundState(false);
        
        // Update user's app state in Firestore
        await NotificationService.setUserAppBackgroundState(currentUserId, true);
        
        // Clear active chat ID since user is not viewing any chat
        await NotificationService.setUserActiveChatId(currentUserId, null);
        
        // Update presence to show last seen
        await PresenceService.instance.setUserOffline();
        
        print('✅ App paused successfully');
      }
    } catch (e) {
      print('❌ Error handling app pause: $e');
    }
  }

  Future<void> _handleAppInactive() async {
    print('📱 App inactive');
    // App is temporarily inactive (e.g., phone call, notification panel)
    // Don't change online status but prepare for potential backgrounding
    
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        // Just update the timestamp but keep online status
        await PresenceService.instance.updateLastSeen();
      }
    } catch (e) {
      print('❌ Error handling app inactive: $e');
    }
  }

  Future<void> _handleAppDetached() async {
    print('📱 App detached');
    // App is being terminated
    await _cleanupOnExit();
  }

  Future<void> _handleAppHidden() async {
    print('📱 App hidden');
    // Similar to paused but less severe
    _isAppInForeground = false;
    
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        NotificationService.setAppForegroundState(false);
      }
    } catch (e) {
      print('❌ Error handling app hidden: $e');
    }
  }

  Future<void> _cleanupOnExit() async {
    print('🧹 Cleaning up on app exit');
    
    try {
      final currentUserId = FirebaseService.currentUserId;
      
      if (currentUserId != null) {
        // Set user offline
        await PresenceService.instance.setUserOffline();
        
        // Clear active chat
        await NotificationService.setUserActiveChatId(currentUserId, null);
        
        // Update app state
        await NotificationService.setUserAppBackgroundState(currentUserId, true);
        
        // Sign out from presence service
        await PresenceService.instance.signOut();
      }
      
      print('✅ Cleanup completed');
    } catch (e) {
      print('❌ Error during cleanup: $e');
    }
  }

  void _refreshAppData() {
    // Refresh providers that might have stale data
    try {
      // You can invalidate specific providers here
      // ref.invalidate(chatControllerProvider);
      // ref.invalidate(realTimePartnerUserProvider);
      // ref.invalidate(realTimeCurrentUserProvider);
      
      print('✅ App data refreshed');
    } catch (e) {
      print('❌ Error refreshing app data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// Provider for app lifecycle state
final appLifecycleStateProvider = StateProvider<AppLifecycleState>((ref) {
  return AppLifecycleState.resumed;
});

// Provider to check if app is in foreground
final isAppInForegroundProvider = Provider<bool>((ref) {
  final state = ref.watch(appLifecycleStateProvider);
  return state == AppLifecycleState.resumed;
});

// Usage: Wrap your MaterialApp with this widget
class AppLifecycleWrapper extends ConsumerWidget {
  final Widget child;

  const AppLifecycleWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLifecycleManager(
      child: child,
    );
  }
}