import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'core/constants/app_themes.dart';
import 'core/services/firebase_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/pressence_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Critical initialization only - keep launch time minimal
    await _initializeCriticalServices();

    // Set system UI style
    _setupSystemUI();

    // Set preferred orientations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    runApp(const ProviderScope(child: OnlyUsApp()));

    // Non-critical initialization after app starts
    _initializeNonCriticalServices();
  } catch (e) {
    print('❌ Critical error during app initialization: $e');
    // Still launch app with error handling
    runApp(const ProviderScope(child: OnlyUsApp()));
  }
}

/// Initialize only critical services needed for app launch
Future<void> _initializeCriticalServices() async {
  try {
    print('🚀 Initializing critical services...');

    // Initialize Firebase - This is critical
    await Firebase.initializeApp();

    // Initialize basic Firebase services - Critical for auth
    await FirebaseService.initialize();

    print('✅ Critical services initialized');
  } catch (e) {
    print('❌ Error initializing critical services: $e');
    rethrow; // Critical errors should prevent app launch
  }
}

/// Initialize non-critical services after app UI is shown
void _initializeNonCriticalServices() {
  // Run after a short delay to allow UI to render first
  Future.delayed(const Duration(milliseconds: 500), () async {
    try {
      print('🔧 Initializing non-critical services...');

      // Initialize OneSignal - Important but not critical for launch
      await NotificationService.initialize();

      // Initialize presence service - Can be delayed
      await PresenceService.instance.initialize();

      print('✅ All services initialized successfully');
    } catch (e) {
      print('❌ Error initializing non-critical services: $e');
      // Don't crash app for non-critical service failures
    }
  });
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

class OnlyUsApp extends ConsumerWidget {
  const OnlyUsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLifecycleWrapper(
      // Add lifecycle management
      child: MaterialApp(
        title: 'OnlyUs',
        debugShowCheckedModeBanner: false,
        theme: AppThemes.lightTheme,
        home: const SplashScreen(),
        navigatorKey:
            GlobalNavigationService.navigatorKey, // For notification navigation
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

  /// Generate routes for navigation from notifications
  Route<dynamic>? _generateRoute(RouteSettings settings) {
    try {
      switch (settings.name) {
        case '/':
          return MaterialPageRoute(
            builder: (context) => const SplashScreen(),
            settings: settings,
          );

        case '/chat':
          // Handle navigation from notifications
          final args = settings.arguments as Map<String, dynamic>?;
          final chatId = args?['chatId'] as String?;
          final senderId = args?['senderId'] as String?;

          print(
            '📱 Navigating to chat from notification - ChatID: $chatId, SenderID: $senderId',
          );

          // Import your ChatScreen here
          // return MaterialPageRoute(
          //   builder: (context) => const ChatScreen(),
          //   settings: settings,
          // );
          break;

        case '/profile':
          // Import your ProfileScreen here
          // return MaterialPageRoute(
          //   builder: (context) => const ProfileScreen(),
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

  /// Navigate to chat from notification
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

  /// Navigate to specific screen from notification
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

/// App lifecycle wrapper with optimized initialization
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
  bool _servicesInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize notification-related services after UI is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNotificationServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Initialize notification services after UI is rendered
  Future<void> _initializeNotificationServices() async {
    if (_servicesInitialized) return;

    try {
      print('🔔 Initializing notification services...');

      // Ensure OneSignal is fully initialized
      final notificationSettings =
          await NotificationService.getNotificationSettings();
      print('📋 Current notification settings: $notificationSettings');

      // Set up notification handlers if not already done
      await _setupNotificationHandlers();

      _servicesInitialized = true;
      print('✅ Notification services initialized');
    } catch (e) {
      print('❌ Error initializing notification services: $e');
    }
  }

  /// Setup notification click handlers
  Future<void> _setupNotificationHandlers() async {
    try {
      // Enhanced notification click handler
      OneSignal.Notifications.addClickListener((event) {
        print('🔔 Notification clicked: ${event.notification.title}');

        final additionalData = event.notification.additionalData;
        if (additionalData != null) {
          _handleNotificationClick(additionalData);
        }
      });

      // Handle notifications received in foreground
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        print(
          '📱 Notification received in foreground: ${event.notification.title}',
        );

        final additionalData = event.notification.additionalData;
        final notificationType = additionalData?['type'] as String?;

        if (notificationType == 'new_message') {
          final chatId = additionalData?['chatId'] as String?;

          // Check if user is currently viewing this chat
          if (_isUserViewingSpecificChat(chatId)) {
            print('📱 User is viewing chat, not showing notification');
            return; // Don't display notification
          }
        }

        // Display notification
        event.notification.display();
      });

      print('✅ Notification handlers setup complete');
    } catch (e) {
      print('❌ Error setting up notification handlers: $e');
    }
  }

  /// Handle notification click navigation
  void _handleNotificationClick(Map<String, dynamic> data) {
    try {
      final type = data['type'] as String?;
      final chatId = data['chatId'] as String?;
      final senderId = data['senderId'] as String?;

      print('📱 Handling notification click - Type: $type, ChatID: $chatId');

      switch (type) {
        case 'new_message':
          if (chatId != null) {
            // Use global navigation service
            GlobalNavigationService.navigateToChat(
              chatId: chatId,
              senderId: senderId,
            );
          }
          break;

        case 'typing':
          print('✍️ Partner is typing notification clicked');
          if (chatId != null) {
            GlobalNavigationService.navigateToChat(chatId: chatId);
          }
          break;

        case 'connection_request':
          print('🤝 Connection request notification clicked');
          GlobalNavigationService.navigateToScreen('/profile');
          break;

        default:
          print('📱 Unknown notification type: $type');
          GlobalNavigationService.navigateToScreen('/');
      }
    } catch (e) {
      print('❌ Error handling notification click: $e');
    }
  }

  /// Check if user is viewing specific chat (simplified check)
  bool _isUserViewingSpecificChat(String? chatId) {
    if (!_isAppInForeground || chatId == null) return false;

    // You can enhance this by checking current route or chat state
    // For now, return false to allow notifications
    return false;
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
      // Clear notifications when app comes to foreground
      if (_servicesInitialized) {
        await NotificationService.clearAllNotifications();
      }

      // Update user online status if services are ready
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null && _servicesInitialized) {
        await PresenceService.instance.setUserOnline();
        await NotificationService.setUserAppBackgroundState(
          currentUserId,
          false,
        );
      }

      print('✅ App resumed handling complete');
    } catch (e) {
      print('❌ Error handling app resume: $e');
    }
  }

  Future<void> _handleAppPaused() async {
    print('📱 App paused');
    _isAppInForeground = false;

    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null && _servicesInitialized) {
        await NotificationService.setUserAppBackgroundState(
          currentUserId,
          true,
        );
        await NotificationService.setUserActiveChatId(currentUserId, null);
        await PresenceService.instance.setUserOffline();
      }

      print('✅ App paused handling complete');
    } catch (e) {
      print('❌ Error handling app pause: $e');
    }
  }

  Future<void> _handleAppInactive() async {
    print('📱 App inactive');
    // App is temporarily inactive, just update timestamp
    try {
      if (_servicesInitialized) {
        await PresenceService.instance.updateLastSeen();
      }
    } catch (e) {
      print('❌ Error handling app inactive: $e');
    }
  }

  Future<void> _handleAppDetached() async {
    print('📱 App detached');
    await _cleanupOnExit();
  }

  Future<void> _handleAppHidden() async {
    print('📱 App hidden');
    _isAppInForeground = false;

    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId != null && _servicesInitialized) {
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

      if (currentUserId != null && _servicesInitialized) {
        await PresenceService.instance.setUserOffline();
        await NotificationService.setUserActiveChatId(currentUserId, null);
        await NotificationService.setUserAppBackgroundState(
          currentUserId,
          true,
        );
        await PresenceService.instance.signOut();
      }

      print('✅ Cleanup completed');
    } catch (e) {
      print('❌ Error during cleanup: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
