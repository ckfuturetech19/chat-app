import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:onlyus/core/services/app_initialization_service.dart';
import 'package:onlyus/core/services/app_lifecycle_service.dart';

// Import your firebase_options.dart file
import 'firebase_options.dart';

import 'core/constants/app_themes.dart';
import 'core/services/firebase_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/pressence_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Critical initialization only
    await _initializeCriticalServices();

    // Set system UI style
    _setupSystemUI();

    // Set preferred orientations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
     // ADD this line for caching
  await AppInitializationService.instance.initialize();

    runApp(const ProviderScope(child: OnlyUsApp()));

    // Non-critical initialization after app starts
    _initializeNonCriticalServices();
  } catch (e) {
    print('❌ Critical error during app initialization: $e');
    // Still launch app with error handling
    runApp(
      ProviderScope(child: MaterialApp(home: _buildErrorScreen(e.toString()))),
    );
  }
}

/// IMPROVED: Initialize only critical services needed for app launch
Future<void> _initializeCriticalServices() async {
  try {
    print('🚀 Initializing critical services...');

    // Initialize Firebase with proper error handling
    await _initializeFirebase();

    // Test and configure database connections with timeout
    await _configureDatabaseConnections().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        print(
          '⚠️ Database configuration timed out, continuing with degraded mode',
        );
      },
    );

    // Initialize basic Firebase services with timeout
    await FirebaseService.initialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('⚠️ Firebase service initialization timed out');
        throw TimeoutException('Firebase service initialization timeout');
      },
    );

    print('✅ Critical services initialized');
  } catch (e) {
    print('❌ Error initializing critical services: $e');
    // For critical errors, we still want to show some UI
    if (e.toString().contains('timeout')) {
      print('⚠️ Initialization timeout - app will start in degraded mode');
      return; // Don't rethrow timeout errors
    }
    rethrow;
  }
}

/// IMPROVED: Initialize Firebase with better duplicate app handling
Future<void> _initializeFirebase() async {
  try {
    // Check if Firebase is already initialized
    try {
      final existingApp = Firebase.app();
      print('✅ Firebase already initialized: ${existingApp.options.projectId}');
      return;
    } catch (_) {
      // Firebase not initialized, proceed with initialization
    }

    // Initialize Firebase with timeout
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10));

    print('✅ Firebase initialized successfully');

    // Verify configuration
    final app = Firebase.app();
    if (app.options.databaseURL == null || app.options.databaseURL!.isEmpty) {
      throw Exception(
        'Database URL not configured! Please ensure databaseURL is set in firebase_options.dart',
      );
    }
    print('✅ Database URL configured: ${app.options.databaseURL}');
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      print('⚠️ Firebase duplicate app error (safe to ignore)');
      return;
    }
    throw Exception('Failed to initialize Firebase: $e');
  }
}

/// IMPROVED: Configure database connections with better error handling
Future<void> _configureDatabaseConnections() async {
  try {
    print('🔧 Configuring database connections...');

    // Configure services in parallel but with individual error handling
    final results = await Future.wait([
      _configureFirestore().catchError((e) {
        print('⚠️ Firestore configuration failed: $e');
        return false;
      }),
      _configureRealtimeDatabase().catchError((e) {
        print('⚠️ Realtime Database configuration failed: $e');
        return false;
      }),
    ]);

    // Test connections (non-critical)
    _testDatabaseConnections().catchError((e) {
      print('⚠️ Database connection tests failed: $e');
    });

    print('✅ Database connections configured');
  } catch (e) {
    print('❌ Error configuring database connections: $e');
    // Don't throw - allow app to start even with database issues
  }
}

/// IMPROVED: Configure Firestore with better error handling
Future<bool> _configureFirestore() async {
  try {
    final firestore = FirebaseFirestore.instance;

    // Check if settings are already configured
    try {
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      if (e.toString().contains('already been set')) {
        print('✅ Firestore settings already configured');
      } else {
        throw e;
      }
    }

    // Enable network with timeout
    await firestore.enableNetwork().timeout(const Duration(seconds: 5));

    print('✅ Firestore configured');
    return true;
  } catch (e) {
    print('❌ Failed to configure Firestore: $e');
    return false;
  }
}

/// IMPROVED: Configure Realtime Database with better error handling
Future<bool> _configureRealtimeDatabase() async {
  try {
    final database = FirebaseDatabase.instance;

    // Set persistence with error handling
    try {
      database.setPersistenceEnabled(true);
      print('✅ Realtime Database persistence enabled');
    } catch (e) {
      if (e.toString().contains('already been called')) {
        print('✅ Realtime Database persistence already enabled');
      } else {
        print('⚠️ Could not enable persistence: $e');
      }
    }

    // Set cache size with error handling
    try {
      database.setPersistenceCacheSizeBytes(10 * 1024 * 1024); // 10MB
    } catch (e) {
      print('⚠️ Could not set cache size: $e');
    }

    // Go online
    database.goOnline();

    print('✅ Realtime Database configured');
    return true;
  } catch (e) {
    print('❌ Failed to configure Realtime Database: $e');
    return false;
  }
}

/// IMPROVED: Test database connections with shorter timeouts
Future<void> _testDatabaseConnections() async {
  try {
    print('🧪 Testing database connections...');

    // Test connections in parallel with short timeouts
    await Future.wait([
      _testFirestoreConnection(),
      _testRealtimeDatabaseConnection(),
    ], eagerError: false);

    print('✅ Database connection tests completed');
  } catch (e) {
    print('⚠️ Some database connection tests failed: $e');
    // Don't throw - connection tests are informational
  }
}

/// IMPROVED: Test Firestore connection with shorter timeout
Future<void> _testFirestoreConnection() async {
  try {
    print('🧪 Testing Firestore connection...');

    // Use a very simple operation
    await FirebaseFirestore.instance
        .collection('_test')
        .limit(1)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 3));

    print('✅ Firestore connection test successful');
  } catch (e) {
    print('⚠️ Firestore connection test failed: $e');
    if (e.toString().contains('offline') || e.toString().contains('network')) {
      print('📱 Device may be offline');
    }
  }
}

/// IMPROVED: Test Realtime Database connection with shorter timeout
Future<void> _testRealtimeDatabaseConnection() async {
  try {
    print('🧪 Testing Realtime Database connection...');

    final database = FirebaseDatabase.instance;

    // Test with .info/connected (fastest test)
    final connectedRef = database.ref('.info/connected');
    final snapshot = await connectedRef.get().timeout(
      const Duration(seconds: 3),
    );

    final connected = snapshot.value as bool? ?? false;
    print(
      '🔗 Realtime Database connection status: ${connected ? "Connected" : "Disconnected"}',
    );

    if (connected) {
      print('✅ Realtime Database connection test successful');
    } else {
      print('⚠️ Realtime Database not connected');
    }
  } catch (e) {
    print('⚠️ Realtime Database connection test failed: $e');
  }
}

/// IMPROVED: Initialize non-critical services with better error isolation
void _initializeNonCriticalServices() {
  // Run after a longer delay to allow UI to render and stabilize
  Future.delayed(const Duration(seconds: 1), () async {
    try {
      print('🔧 Initializing non-critical services...');

      // Initialize services in sequence with individual error handling
      await _initializeNotificationService();
      await _initializePresenceService();
      await _initializeAppLifecycleService();

      print('✅ All non-critical services initialized');
    } catch (e) {
      print('❌ Error initializing non-critical services: $e');
      // Don't crash app for non-critical service failures
    }
  });
}

/// NEW: Initialize notification service with error handling
Future<void> _initializeNotificationService() async {
  try {
    await NotificationService.initialize().timeout(const Duration(seconds: 10));
    print('✅ Notification service initialized');
  } catch (e) {
    print('⚠️ Notification service initialization failed: $e');
  }
}

/// NEW: Initialize presence service with error handling
Future<void> _initializePresenceService() async {
  try {
    // Only initialize if user is authenticated
    if (FirebaseService.currentUser != null) {
      await PresenceService.instance.initialize().timeout(
        const Duration(seconds: 8),
      );
      print('✅ Presence service initialized');
    } else {
      print('ℹ️ Skipping presence initialization - no authenticated user');
    }
  } catch (e) {
    print('⚠️ Presence service initialization failed (non-critical): $e');
  }
}

/// NEW: Initialize app lifecycle service with error handling
Future<void> _initializeAppLifecycleService() async {
  try {
    AppLifecycleService.instance.initialize();
    print('✅ App lifecycle service initialized');
  } catch (e) {
    print('⚠️ App lifecycle service initialization failed: $e');
  }
}

/// Setup system UI overlay style
void _setupSystemUI() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
}

/// IMPROVED: Build error screen for critical failures
Widget _buildErrorScreen(String error) {
  return Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'App Initialization Error',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'The app encountered an error during startup. You can try restarting or continue in limited mode.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('Error Details'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    error,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    // Try to continue anyway
                    GlobalNavigationService.navigatorKey.currentState
                        ?.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const SplashScreen(),
                          ),
                        );
                  },
                  child: const Text('Continue'),
                ),
                OutlinedButton(
                  onPressed: () {
                    // Restart app
                    SystemNavigator.pop();
                  },
                  child: const Text('Restart'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class OnlyUsApp extends ConsumerWidget {
  const OnlyUsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLifecycleWrapper(
      child: MaterialApp(
        title: 'OnlyUs',
        debugShowCheckedModeBanner: false,
        theme: AppThemes.lightTheme,
        home: const SplashScreen(),
        navigatorKey: GlobalNavigationService.navigatorKey,
        onGenerateRoute: _generateRoute,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
            child: child!,
          );
        },
      ),
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    try {
      switch (settings.name) {
        case '/':
          return MaterialPageRoute(
            builder: (context) => const SplashScreen(),
            settings: settings,
          );

        case '/chat':
          final args = settings.arguments as Map<String, dynamic>?;
          final chatId = args?['chatId'] as String?;
          final senderId = args?['senderId'] as String?;

          print('📱 Navigating to chat - ChatID: $chatId, SenderID: $senderId');

          // Import and return your ChatScreen here
          // return MaterialPageRoute(
          //   builder: (context) => const ChatScreen(),
          //   settings: settings,
          // );
          break;

        default:
          return MaterialPageRoute(builder: (context) => const SplashScreen());
      }
    } catch (e) {
      print('❌ Error generating route for ${settings.name}: $e');
      return MaterialPageRoute(builder: (context) => const SplashScreen());
    }

    return null;
  }
}

/// Global navigation service for notification navigation
class GlobalNavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<void> navigateToChat({
    required String chatId,
    String? senderId,
  }) async {
    try {
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        print('📱 Navigating to chat: $chatId');

        await navigator.pushNamed(
          '/chat',
          arguments: {'chatId': chatId, 'senderId': senderId},
        );
      } else {
        print('⚠️ Navigator not available for chat navigation');
      }
    } catch (e) {
      print('❌ Error navigating to chat: $e');
    }
  }

  static Future<void> navigateToScreen(
    String routeName, {
    Object? arguments,
  }) async {
    try {
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        await navigator.pushNamed(routeName, arguments: arguments);
      }
    } catch (e) {
      print('❌ Error navigating to $routeName: $e');
    }
  }
}

/// IMPROVED: App lifecycle wrapper with better error handling
class AppLifecycleWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const AppLifecycleWrapper({Key? key, required this.child}) : super(key: key);

  @override
  ConsumerState<AppLifecycleWrapper> createState() =>
      _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends ConsumerState<AppLifecycleWrapper>
    with WidgetsBindingObserver {
  bool _isAppInForeground = true;
  AppLifecycleService? _lifecycleService;
  DateTime _lastStateChange = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize lifecycle service
    _lifecycleService = AppLifecycleService.instance;

    // Set initial online status with delay
    _setInitialOnlineStatusDelayed();
  }

  @override
  void dispose() {
    _handleAppExit();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// NEW: Set initial online status with delay to prevent race conditions
  Future<void> _setInitialOnlineStatusDelayed() async {
    // Wait for app to fully initialize
    await Future.delayed(const Duration(seconds: 2));

    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        await PresenceService.instance.setUserOnline();

        await FirebaseService.usersCollection
            .doc(currentUserId)
            .update({
              'isOnline': true,
              'isAppInBackground': false,
              'lastSeen': FieldValue.serverTimestamp(),
              'appState': 'active',
            })
            .timeout(const Duration(seconds: 8));

        print('✅ Initial online status set');
      }
    } catch (e) {
      print('❌ Error setting initial online status: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Prevent rapid state changes
    final now = DateTime.now();
    if (now.difference(_lastStateChange).inMilliseconds < 500) {
      print('⚠️ Ignoring rapid app state change');
      return;
    }
    _lastStateChange = now;

    print('📱 App lifecycle state changed to: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumedDelayed();
        break;
      case AppLifecycleState.paused:
        _handleAppPausedDelayed();
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

  /// NEW: Handle app resumed with delay to prevent race conditions
  Future<void> _handleAppResumedDelayed() async {
    _isAppInForeground = true;

    // Cancel any pending offline status updates
    PresenceDebouncer.cancelPendingUpdates();

    // Wait a bit before updating status to prevent rapid switching
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!_isAppInForeground) {
      print('⚠️ App state changed during delay, skipping resume handling');
      return;
    }

    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        // Update local state immediately
        NotificationService.setAppForegroundState(true);

        // Use debounced online status update
        PresenceDebouncer.setOnlineStatus(true, () async {
          try {
            await PresenceService.instance.setUserOnline();

            await FirebaseService.usersCollection
                .doc(currentUserId)
                .update({
                  'isOnline': true,
                  'isAppInBackground': false,
                  'lastSeen': FieldValue.serverTimestamp(),
                  'appState': 'active',
                  'appStateUpdatedAt': FieldValue.serverTimestamp(),
                })
                .timeout(const Duration(seconds: 8));

            await NotificationService.setUserAppBackgroundState(
              currentUserId,
              false,
            );
            print('✅ App resume handling completed');
          } catch (e) {
            print('❌ Error in debounced resume update: $e');
          }
        });

        // Clear notifications
        NotificationService.clearAllNotifications().catchError((e) {
          print('⚠️ Error clearing notifications: $e');
        });
      }
    } catch (e) {
      print('❌ Error handling app resume: $e');
    }
  }

  /// NEW: Handle app paused with delay
  Future<void> _handleAppPausedDelayed() async {
    _isAppInForeground = false;

    // Wait a bit to see if app comes back to foreground quickly
    await Future.delayed(const Duration(milliseconds: 1500));

    if (_isAppInForeground) {
      print('⚠️ App returned to foreground, skipping pause handling');
      return;
    }

    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        // Update local state immediately
        NotificationService.setAppForegroundState(false);

        // Use debounced offline status update
        PresenceDebouncer.setOnlineStatus(false, () async {
          try {
            await NotificationService.setUserAppBackgroundState(
              currentUserId,
              true,
            );
            await NotificationService.setUserActiveChatId(currentUserId, null);

            await PresenceService.instance.setUserOffline();

            await FirebaseService.usersCollection
                .doc(currentUserId)
                .update({
                  'isOnline': false,
                  'isAppInBackground': true,
                  'activeChatId': null,
                  'lastSeen': FieldValue.serverTimestamp(),
                  'appState': 'background',
                  'appStateUpdatedAt': FieldValue.serverTimestamp(),
                })
                .timeout(const Duration(seconds: 8));

            print('✅ App pause handling completed');
          } catch (e) {
            print('❌ Error in debounced pause update: $e');
          }
        });
      }
    } catch (e) {
      print('❌ Error handling app pause: $e');
    }
  }

  Future<void> _handleAppInactive() async {
    try {
      // Just update last seen timestamp
      await PresenceService.instance.updateLastSeen();
    } catch (e) {
      print('❌ Error handling app inactive: $e');
    }
  }

  Future<void> _handleAppDetached() async {
    await _handleAppExit();
  }

  Future<void> _handleAppHidden() async {
    _isAppInForeground = false;
    NotificationService.setAppForegroundState(false);
  }

  Future<void> _handleAppExit() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null) {
        // Quick cleanup without waiting for responses
        PresenceService.instance
            .setUserOffline()
            .timeout(const Duration(seconds: 3))
            .catchError((e) {
              print('⚠️ Error setting offline during exit: $e');
            });

        NotificationService.setUserActiveChatId(currentUserId, null).catchError(
          (e) {
            print('⚠️ Error clearing active chat during exit: $e');
          },
        );

        NotificationService.setUserAppBackgroundState(
          currentUserId,
          true,
        ).catchError((e) {
          print('⚠️ Error setting background state during exit: $e');
        });

        FirebaseService.usersCollection
            .doc(currentUserId)
            .update({
              'isOnline': false,
              'isAppInBackground': true,
              'lastSeen': FieldValue.serverTimestamp(),
              'appState': 'terminated',
              'appStateUpdatedAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 3))
            .catchError((e) {
              print('⚠️ Error updating user doc during exit: $e');
            });
      }
    } catch (e) {
      print('❌ Error during app exit cleanup: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
