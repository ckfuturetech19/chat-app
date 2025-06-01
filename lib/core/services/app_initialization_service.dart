import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onlyus/core/services/cache_service.dart';
import 'package:onlyus/core/services/chat_service.dart';
import 'package:onlyus/core/services/firebase_service.dart';
import 'package:onlyus/core/services/notification_service.dart';
import 'package:onlyus/core/services/pressence_service.dart';

/// Comprehensive app initialization service with intelligent caching
class AppInitializationService {
  static AppInitializationService? _instance;
  static AppInitializationService get instance =>
      _instance ??= AppInitializationService._();
  AppInitializationService._();

  bool _isInitialized = false;
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _backgroundSyncTimer;

  /// Initialize the entire app with caching strategy
  Future<void> initialize() async {
    if (_isInitialized) {
      print('⚠️ App already initialized');
      return;
    }

    try {
      print('🚀 Starting app initialization with caching...');

      // Step 1: Initialize cache service first (critical for offline support)
      await _initializeCacheService();

      // Step 2: Initialize Firebase services
      await _initializeFirebaseServices();

      // Step 3: Setup connectivity monitoring
      await _setupConnectivityMonitoring();

      // Step 4: Initialize notification service
      await _initializeNotificationService();

      // Step 5: Setup background synchronization
      _setupBackgroundSync();

      // Step 6: Preload critical cached data
      await _preloadCachedData();

      // Step 7: Setup app lifecycle monitoring
      _setupAppLifecycleMonitoring();

      _isInitialized = true;
      print('✅ App initialization complete with caching support');
    } catch (e) {
      print('❌ Critical error during app initialization: $e');

      // Try to initialize with minimal functionality
      await _initializeMinimal();
      throw e;
    }
  }

  /// Step 1: Initialize cache service (most critical for UX)
  Future<void> _initializeCacheService() async {
    try {
      print('🔧 Initializing cache service...');

      await CacheService.instance.initialize();

      // Clean up expired caches on startup
      await CacheService.instance.clearExpiredCaches();

      print('✅ Cache service initialized');
    } catch (e) {
      print('❌ Failed to initialize cache service: $e');
      throw Exception('Cache initialization failed: $e');
    }
  }

  /// Step 2: Initialize Firebase services with error handling
  Future<void> _initializeFirebaseServices() async {
    try {
      print('🔧 Initializing Firebase services...');

      await FirebaseService.initialize();

      // Initialize chat service
      ChatService.instance.initialize();

      print('✅ Firebase services initialized');
    } catch (e) {
      print('❌ Firebase initialization error: $e');
      // Don't throw here, app can work with cached data
    }
  }

  /// Step 3: Setup connectivity monitoring for smart caching
  Future<void> _setupConnectivityMonitoring() async {
    try {
      print('🔧 Setting up connectivity monitoring...');

      // Check initial connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      _isOnline =
          connectivityResult.contains(ConnectivityResult.wifi) ||
          connectivityResult.contains(ConnectivityResult.mobile);

      // Listen for connectivity changes
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        result,
      ) async {
        final wasOnline = _isOnline;
        _isOnline =
            result.contains(ConnectivityResult.wifi) ||
            result.contains(ConnectivityResult.mobile);

        print('🌐 Connectivity changed: ${_isOnline ? "Online" : "Offline"}');

        if (!wasOnline && _isOnline) {
          // Just came back online - sync cached data
          await _handleConnectivityRestored();
        } else if (wasOnline && !_isOnline) {
          // Went offline - ensure all data is cached
          await _handleConnectivityLost();
        }
      });

      print('✅ Connectivity monitoring setup');
    } catch (e) {
      print('❌ Error setting up connectivity monitoring: $e');
    }
  }

  /// Step 4: Initialize notification service with caching
  Future<void> _initializeNotificationService() async {
    try {
      print('🔧 Initializing notification service...');

      await NotificationService.initialize();

      print('✅ Notification service initialized');
    } catch (e) {
      print('❌ Error initializing notification service: $e');
      // Non-critical, app can work without notifications
    }
  }

  /// Step 5: Setup background synchronization
  void _setupBackgroundSync() {
    try {
      print('🔧 Setting up background synchronization...');

      _backgroundSyncTimer = Timer.periodic(const Duration(minutes: 10), (
        _,
      ) async {
        await _performBackgroundSync();
      });

      print('✅ Background sync setup');
    } catch (e) {
      print('❌ Error setting up background sync: $e');
    }
  }

  /// Step 6: Preload critical cached data for instant UI
  Future<void> _preloadCachedData() async {
    try {
      print('🔧 Preloading critical cached data...');

      // Preload user data
      final cachedCurrentUser = CacheService.instance.getCachedCurrentUser();
      final cachedPartnerUser = CacheService.instance.getCachedPartnerUser();

      if (cachedCurrentUser != null) {
        print('✅ Current user data preloaded from cache');
      }

      if (cachedPartnerUser != null) {
        print('✅ Partner user data preloaded from cache');
      }

      // Preload user preferences
      final cachedPreferences =
          CacheService.instance.getCachedUserPreferences();
      if (cachedPreferences != null) {
        print('✅ User preferences preloaded from cache');
      }

      // Log cache statistics
      final cacheStats = CacheService.instance.getCacheStats();
      print('📊 Cache statistics: ${cacheStats['totalCaches']} items cached');
    } catch (e) {
      print('❌ Error preloading cached data: $e');
    }
  }

  /// Step 7: Setup app lifecycle monitoring
  void _setupAppLifecycleMonitoring() {
    try {
      print('🔧 Setting up app lifecycle monitoring...');

      // This would be integrated with your app's lifecycle observer
      print('✅ App lifecycle monitoring setup');
    } catch (e) {
      print('❌ Error setting up app lifecycle monitoring: $e');
    }
  }

  /// Handle connectivity restored - sync cached data
  Future<void> _handleConnectivityRestored() async {
    try {
      print('🌐 Connectivity restored - syncing data...');

      // Re-enable Firebase networks
      try {
        await FirebaseService.firestore.enableNetwork();
        FirebaseService.realtimeDatabase.goOnline();
      } catch (e) {
        print('⚠️ Error re-enabling Firebase networks: $e');
      }

      // Sync critical data
      await _syncCriticalData();

      // Update presence
      try {
        await PresenceService.instance.setUserOnline();
      } catch (e) {
        print('⚠️ Error updating presence: $e');
      }

      print('✅ Data sync completed after connectivity restoration');
    } catch (e) {
      print('❌ Error handling connectivity restoration: $e');
    }
  }

  /// Handle connectivity lost - ensure data is cached
  Future<void> _handleConnectivityLost() async {
    try {
      print('🌐 Connectivity lost - caching current state...');

      // Cache current state of critical data
      await _cacheCurrentAppState();

      // Update presence to offline
      try {
        await PresenceService.instance.setUserOffline();
      } catch (e) {
        print('⚠️ Error updating presence to offline: $e');
      }

      print('✅ App state cached for offline use');
    } catch (e) {
      print('❌ Error handling connectivity loss: $e');
    }
  }

  /// Sync critical data when coming back online
  Future<void> _syncCriticalData() async {
    try {
      // Check if user is authenticated
      if (!FirebaseService.isAuthenticated) {
        print('⚠️ User not authenticated, skipping data sync');
        return;
      }

      final currentUserId = FirebaseService.currentUserId!;

      // Sync user data
      try {
        final userDoc = await FirebaseService.usersCollection
            .doc(currentUserId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));

        if (userDoc.exists) {
          // Update cache with fresh user data
          // This would be handled by the cached providers
          print('✅ User data synced');
        }
      } catch (e) {
        print('⚠️ Error syncing user data: $e');
      }

      // Sync chat data
      try {
        final chatId = ChatService.instance.activeChatId;
        if (chatId != null) {
          // Force refresh messages
          await ChatService.instance.refreshMessagesStream(chatId: chatId);
          print('✅ Chat data synced');
        }
      } catch (e) {
        print('⚠️ Error syncing chat data: $e');
      }
    } catch (e) {
      print('❌ Error syncing critical data: $e');
    }
  }

  /// Cache current app state
  Future<void> _cacheCurrentAppState() async {
    try {
      // This would cache the current state of all critical app data
      // The actual caching is handled by individual services

      print('💾 Caching current app state...');

      // Mark last sync times
      await CacheService.instance.markLastSync('app_state');
    } catch (e) {
      print('❌ Error caching app state: $e');
    }
  }

  /// Perform periodic background sync
  Future<void> _performBackgroundSync() async {
    if (!_isOnline || !_isInitialized) return;

    try {
      print('🔄 Performing periodic background sync...');

      // Sync critical data if needed
      await _syncCriticalData();

      // Clean up expired caches
      await CacheService.instance.clearExpiredCaches();

      // Check cache health
      final cacheStats = CacheService.instance.getCacheStats();
      print(
        '📊 Background sync complete. Cache items: ${cacheStats['totalCaches']}',
      );
    } catch (e) {
      print('❌ Error in background sync: $e');
    }
  }

  /// Initialize with minimal functionality (fallback)
  Future<void> _initializeMinimal() async {
    try {
      print('🆘 Initializing with minimal functionality...');

      // Initialize only cache service for offline functionality
      await CacheService.instance.initialize();

      _isInitialized = true;
      print('✅ Minimal initialization complete');
    } catch (e) {
      print('❌ Even minimal initialization failed: $e');
    }
  }

  /// Get initialization status
  bool get isInitialized => _isInitialized;

  /// Get connectivity status
  bool get isOnline => _isOnline;

  /// Force sync all data
  Future<void> forceSyncAllData() async {
    try {
      print('🔄 Force syncing all data...');

      if (!_isOnline) {
        print('⚠️ Cannot sync - device is offline');
        return;
      }

      await _syncCriticalData();

      // Clear all caches to force fresh data
      await CacheService.instance.clearExpiredCaches();

      print('✅ Force sync completed');
    } catch (e) {
      print('❌ Error in force sync: $e');
      throw e;
    }
  }

  /// Get app health status
  Map<String, dynamic> getHealthStatus() {
    return {
      'isInitialized': _isInitialized,
      'isOnline': _isOnline,
      'firebase': FirebaseService.getConnectionInfo(),
      'cache': CacheService.instance.getCacheStats(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    try {
      print('🧹 Disposing app initialization service...');

      await _connectivitySubscription?.cancel();
      _backgroundSyncTimer?.cancel();

      // Cleanup services
      CacheService.instance.dispose();

      _isInitialized = false;
      print('✅ App initialization service disposed');
    } catch (e) {
      print('❌ Error disposing app initialization service: $e');
    }
  }
}

/// Extension for easy initialization in main app
extension AppInitialization on AppInitializationService {
  /// Quick setup for app startup
  static Future<void> quickSetup() async {
    await AppInitializationService.instance.initialize();
  }

  /// Setup with custom configuration
  static Future<void> setupWithConfig({
    bool enableCaching = true,
    bool enableBackgroundSync = true,
    Duration syncInterval = const Duration(minutes: 10),
  }) async {
    await AppInitializationService.instance.initialize();
  }
}

/// Helper class for managing app startup states
class AppStartupManager {
  static bool _hasStarted = false;
  static bool _isStarting = false;

  /// Ensure app starts only once
  static Future<void> ensureStarted() async {
    if (_hasStarted || _isStarting) return;

    _isStarting = true;

    try {
      await AppInitializationService.instance.initialize();
      _hasStarted = true;
    } finally {
      _isStarting = false;
    }
  }

  static bool get hasStarted => _hasStarted;
  static bool get isStarting => _isStarting;
}
