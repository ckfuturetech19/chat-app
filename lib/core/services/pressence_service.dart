import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PresenceService {
  // Singleton instance
  static PresenceService? _instance;
  static PresenceService get instance => _instance ??= PresenceService._();
  PresenceService._();

  // Firebase Realtime Database instance
  static FirebaseDatabase get database => FirebaseDatabase.instance;

  // References
  DatabaseReference? _userPresenceRef;
  DatabaseReference? _userConnectionsRef;

  // Connection state
  StreamSubscription<DatabaseEvent>? _connectionStateSubscription;
  StreamSubscription<DatabaseEvent>? _presenceSubscription;

  // State tracking
  bool _isConnectedToRealtimeDB = false;
  bool _isInitialized = false;
  String? _currentUserId;

  // Connection retry logic - IMPROVED
  Timer? _connectionRetryTimer;
  int _connectionRetryCount = 0;
  static const int _maxRetryAttempts = 3; // Reduced from 5
  static const Duration _retryDelay = Duration(seconds: 3); // Reduced from 5

  // Heartbeat timer - IMPROVED
  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(
    seconds: 45,
  ); // Increased from 30

  // Cache for presence data
  final Map<String, Map<String, dynamic>> _presenceCache = {};
  final Map<String, DateTime> _presenceCacheTime = {};
  static const Duration _presenceCacheTimeout = Duration(
    seconds: 45,
  ); // Increased

  // Operation tracking to prevent concurrent operations
  bool _isUpdatingPresence = false;
  Timer? _operationTimeoutTimer;

  String _sanitizeUserId(String userId) {
    // Firebase Realtime Database paths cannot contain: . $ # [ ] / \
    return userId
        .replaceAll('.', '_dot_')
        .replaceAll('\$', '_dollar_')
        .replaceAll('#', '_hash_')
        .replaceAll('[', '_lbracket_')
        .replaceAll(']', '_rbracket_')
        .replaceAll('/', '_slash_')
        .replaceAll('\\', '_backslash_');
  }

  /// Initialize presence system with robust error handling
  Future<void> initialize() async {
    if (_isInitialized) {
      print('⚠️ Presence service already initialized');
      return;
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('⚠️ No authenticated user for presence initialization');
        return;
      }

      _currentUserId = currentUser.uid;
      final sanitizedUserId = _sanitizeUserId(_currentUserId!);
      print(
        '🔍 Initializing PresenceService for user: $_currentUserId (sanitized: $sanitizedUserId)',
      );

      // Ensure database is online with better error handling
      try {
        database.goOnline();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print('⚠️ Error going online: $e');
      }

      // Set up presence references with sanitized user ID
      _userPresenceRef = database.ref('presence/$sanitizedUserId');
      _userConnectionsRef = database.ref(
        'presence/$sanitizedUserId/connections',
      );

      // Set up connection state monitoring with improved logic
      await _setupConnectionStateMonitoring();

      // Start heartbeat with delay
      _startHeartbeat();

      _isInitialized = true;
      print('✅ Presence service initialized successfully');
    } catch (e) {
      print('❌ Error initializing presence service: $e');
      _scheduleConnectionRetry();
    }
  }

  /// IMPROVED: Set up connection state monitoring with better retry logic
  Future<void> _setupConnectionStateMonitoring() async {
    try {
      // Cancel existing subscription
      await _connectionStateSubscription?.cancel();

      final connectedRef = database.ref('.info/connected');

      _connectionStateSubscription = connectedRef.onValue.listen(
        (event) async {
          try {
            final isConnected = event.snapshot.value as bool? ?? false;

            // Only process if state actually changed
            if (_isConnectedToRealtimeDB != isConnected) {
              _isConnectedToRealtimeDB = isConnected;

              print(
                '🔗 Realtime DB connection status changed: ${isConnected ? "Connected" : "Disconnected"}',
              );

              if (isConnected) {
                _connectionRetryCount = 0;
                // Add delay before handling connection to avoid race conditions
                await Future.delayed(const Duration(milliseconds: 1000));
                await _handleConnectionEstablished();
              } else {
                await _handleConnectionLost();
              }
            }
          } catch (e) {
            print('❌ Error processing connection state: $e');
          }
        },
        onError: (error) {
          print('❌ Connection state listener error: $error');
          _isConnectedToRealtimeDB = false;
          _scheduleConnectionRetry();
        },
      );
    } catch (e) {
      print('❌ Error setting up connection monitoring: $e');
      _scheduleConnectionRetry();
    }
  }

  /// IMPROVED: Handle when connection is established
  Future<void> _handleConnectionEstablished() async {
    // Prevent concurrent operations
    if (_isUpdatingPresence) {
      print('⚠️ Presence update already in progress, skipping');
      return;
    }

    _isUpdatingPresence = true;

    try {
      if (_userPresenceRef == null || _currentUserId == null) return;

      print('🟢 Handling connection established...');

      // Generate a unique connection ID
      final connectionId = database.ref().push().key;
      if (connectionId == null) return;

      final connectionRef = _userConnectionsRef?.child(connectionId);
      if (connectionRef == null) return;

      // IMPROVED: Set connection with longer timeout
      await connectionRef
          .set({
            'connected': true,
            'lastSeen': ServerValue.timestamp,
            'connectionId': connectionId,
            'deviceInfo': 'mobile', // Add device info
          })
          .timeout(const Duration(seconds: 8)); // Increased timeout

      // Remove connection on disconnect
      await connectionRef.onDisconnect().remove();

      // Update main presence node with improved data
      final presenceData = {
        'online': true,
        'lastSeen': ServerValue.timestamp,
        'uid': _currentUserId,
        'updatedAt': ServerValue.timestamp,
        'activeConnection': connectionId,
        'connectionMethod': 'auto',
      };

      // IMPROVED: Update with longer timeout and retry
      await _updatePresenceWithRetry(presenceData);

      // Set up onDisconnect for main presence
      await _userPresenceRef!.onDisconnect().update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
        'activeConnection': null,
      });

      // Update Firestore for redundancy (with separate error handling)
      _updateFirestorePresenceAsync(true);

      // Monitor presence changes
      _setupPresenceMonitoring();

      print('✅ User marked as online with connection ID: $connectionId');
    } catch (e) {
      print('❌ Error handling connection established: $e');
      // Don't schedule retry immediately to avoid loops
    } finally {
      _isUpdatingPresence = false;
    }
  }

  /// NEW: Update presence with retry logic
  Future<void> _updatePresenceWithRetry(Map<String, dynamic> data) async {
    int attempts = 0;
    const maxAttempts = 2; // Reduced attempts

    while (attempts < maxAttempts) {
      try {
        await _userPresenceRef!
            .update(data)
            .timeout(const Duration(seconds: 8));
        return; // Success
      } catch (e) {
        attempts++;
        if (attempts >= maxAttempts) {
          throw e;
        }
        print('⚠️ Presence update attempt $attempts failed, retrying...');
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  /// IMPROVED: Handle when connection is lost
  Future<void> _handleConnectionLost() async {
    try {
      print('⚠️ Connection lost - user will be marked offline automatically');

      // Update Firestore immediately when connection is lost (async)
      _updateFirestorePresenceAsync(false);

      // Don't schedule retry immediately to avoid rapid reconnection attempts
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isConnectedToRealtimeDB) {
          _scheduleConnectionRetry();
        }
      });
    } catch (e) {
      print('❌ Error handling connection lost: $e');
    }
  }

  /// NEW: Async Firestore update to prevent blocking
  void _updateFirestorePresenceAsync(bool isOnline) {
    Future.delayed(Duration.zero, () async {
      await _updateFirestorePresence(isOnline);
    });
  }

  /// IMPROVED: Schedule connection retry with better backoff
  void _scheduleConnectionRetry() {
    if (_connectionRetryTimer?.isActive ?? false) return;

    if (_connectionRetryCount >= _maxRetryAttempts) {
      print('❌ Max retry attempts reached. Will retry after longer delay.');
      // Schedule a longer delay retry
      _connectionRetryTimer = Timer(const Duration(minutes: 1), () {
        _connectionRetryCount = 0; // Reset counter
        _scheduleConnectionRetry();
      });
      return;
    }

    _connectionRetryCount++;
    final delay = Duration(
      seconds: _retryDelay.inSeconds * _connectionRetryCount,
    );

    print(
      '🔄 Scheduling connection retry #$_connectionRetryCount in ${delay.inSeconds} seconds',
    );

    _connectionRetryTimer = Timer(delay, () async {
      if (!_isConnectedToRealtimeDB) {
        print('🔄 Retrying connection...');
        try {
          database.goOnline();
          await Future.delayed(const Duration(milliseconds: 500));
          await _setupConnectionStateMonitoring();
        } catch (e) {
          print('❌ Retry failed: $e');
        }
      }
    });
  }

  /// IMPROVED: Update Firestore presence with better error handling
  Future<void> _updateFirestorePresence(bool isOnline) async {
    try {
      if (_currentUserId == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .update({
            'isOnline': isOnline,
            'lastSeen': FieldValue.serverTimestamp(),
            'presenceUpdatedAt': FieldValue.serverTimestamp(),
            'presenceSource': 'realtime_db',
          })
          .timeout(const Duration(seconds: 8)); // Increased timeout

      print('✅ Firestore presence updated: ${isOnline ? "Online" : "Offline"}');
    } catch (e) {
      print('⚠️ Error updating Firestore presence: $e');
      // Store for retry if needed
      _scheduleFirestoreRetry(isOnline);
    }
  }

  /// NEW: Schedule Firestore retry
  void _scheduleFirestoreRetry(bool isOnline) {
    Future.delayed(const Duration(seconds: 10), () async {
      try {
        await _updateFirestorePresence(isOnline);
        print('✅ Firestore retry successful');
      } catch (e) {
        print('❌ Firestore retry failed: $e');
      }
    });
  }

  /// IMPROVED: Update last seen with better timeout handling
  Future<void> updateLastSeen() async {
    try {
      if (!_isInitialized || _userPresenceRef == null) return;

      // Check if we're actually connected
      if (!_isConnectedToRealtimeDB) {
        print('⚠️ Not connected to Realtime DB, skipping last seen update');
        return;
      }

      // Prevent operation timeout
      _operationTimeoutTimer?.cancel();
      _operationTimeoutTimer = Timer(const Duration(seconds: 10), () {
        print('⚠️ Last seen update timed out');
      });

      await _userPresenceRef!
          .update({
            'lastSeen': ServerValue.timestamp,
            'updatedAt': ServerValue.timestamp,
          })
          .timeout(const Duration(seconds: 8)); // Increased timeout

      _operationTimeoutTimer?.cancel();

      // Also update Firestore (async)
      if (_currentUserId != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .update({'lastSeen': FieldValue.serverTimestamp()})
            .timeout(const Duration(seconds: 5))
            .catchError((e) {
              print('⚠️ Firestore last seen update failed: $e');
            });
      }
    } catch (e) {
      print('❌ Error updating last seen: $e');
      _operationTimeoutTimer?.cancel();
    }
  }

  /// IMPROVED: Start heartbeat with better logic
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (_isConnectedToRealtimeDB &&
          _userPresenceRef != null &&
          !_isUpdatingPresence) {
        try {
          await _userPresenceRef!
              .update({
                'heartbeat': ServerValue.timestamp,
                'lastSeen': ServerValue.timestamp,
              })
              .timeout(const Duration(seconds: 6));

          print('💓 Presence heartbeat sent');
        } catch (e) {
          print('❌ Error sending heartbeat: $e');
          // If heartbeat fails, check connection
          if (e.toString().contains('timeout') ||
              e.toString().contains('network')) {
            _isConnectedToRealtimeDB = false;
          }
        }
      }
    });
  }

  /// IMPROVED: Manually set user as online with better connection handling
  Future<void> setUserOnline() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (_userPresenceRef == null || _currentUserId == null) return;

      print('🟢 Setting user online...');

      // Check connection with timeout
      bool connectionEstablished = false;
      if (!_isConnectedToRealtimeDB) {
        print('⚠️ Not connected to Realtime DB, attempting connection...');
        database.goOnline();

        // Wait for connection with reasonable timeout
        for (int i = 0; i < 8; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_isConnectedToRealtimeDB) {
            connectionEstablished = true;
            break;
          }
        }

        if (!connectionEstablished) {
          print(
            '⚠️ Could not establish Realtime DB connection, updating Firestore only',
          );
          await _updateFirestorePresence(true);
          return;
        }
      } else {
        connectionEstablished = true;
      }

      if (connectionEstablished) {
        // Set up the presence data
        final presenceData = {
          'online': true,
          'lastSeen': ServerValue.timestamp,
          'updatedAt': ServerValue.timestamp,
          'manualUpdate': true,
          'connectionId': database.ref().push().key,
        };

        // Update with retry logic
        await _updatePresenceWithRetry(presenceData);

        // Re-establish onDisconnect handler
        await _userPresenceRef!
            .onDisconnect()
            .update({
              'online': false,
              'lastSeen': ServerValue.timestamp,
              'updatedAt': ServerValue.timestamp,
            })
            .timeout(const Duration(seconds: 6));

        print('✅ User set online in Realtime DB');
      }

      // Always update Firestore as backup (async)
      _updateFirestorePresenceAsync(true);

      print('✅ User online status update complete');
    } catch (e) {
      print('❌ Error setting user online: $e');
      // Try Firestore as final fallback
      await _updateFirestorePresence(true);
    }
  }

  /// IMPROVED: Set user offline with better error handling
  Future<void> setUserOffline() async {
    try {
      if (_userPresenceRef == null || _currentUserId == null) return;

      print('🔴 Setting user offline...');

      // Update Realtime Database with timeout
      if (_isConnectedToRealtimeDB) {
        try {
          await _userPresenceRef!
              .update({
                'online': false,
                'lastSeen': ServerValue.timestamp,
                'updatedAt': ServerValue.timestamp,
              })
              .timeout(const Duration(seconds: 6));

          // Clear all connections
          if (_userConnectionsRef != null) {
            await _userConnectionsRef!.remove().timeout(
              const Duration(seconds: 4),
            );
          }
        } catch (e) {
          print('⚠️ Error updating Realtime DB offline status: $e');
        }
      }

      // Update Firestore (async to prevent blocking)
      _updateFirestorePresenceAsync(false);

      print('✅ User set offline');
    } catch (e) {
      print('❌ Error setting user offline: $e');
      // Ensure Firestore is updated even if Realtime DB fails
      await _updateFirestorePresence(false);
    }
  }

  /// Get user presence stream with fallback
  Stream<Map<String, dynamic>?> getUserPresenceStream(String userId) {
    final sanitizedUserId = _sanitizeUserId(userId);

    return database
        .ref('presence/$sanitizedUserId')
        .onValue
        .map((event) {
          try {
            if (event.snapshot.exists) {
              final data = event.snapshot.value as Map<dynamic, dynamic>?;
              if (data != null) {
                final presenceData = Map<String, dynamic>.from(data);

                // Cache the data
                _presenceCache[sanitizedUserId] = presenceData;
                _presenceCacheTime[sanitizedUserId] = DateTime.now();

                // Enhance with connection count
                final connections =
                    presenceData['connections'] as Map<dynamic, dynamic>?;
                if (connections != null) {
                  presenceData['connectionCount'] = connections.length;
                  presenceData['hasActiveConnection'] = connections.isNotEmpty;
                }

                return presenceData;
              }
            }

            // Return cached data if available
            return _getCachedPresence(sanitizedUserId);
          } catch (e) {
            print('❌ Error processing presence stream for $userId: $e');
            return _getCachedPresence(sanitizedUserId);
          }
        })
        .handleError((error) {
          print('❌ Error in presence stream for $userId: $error');
          return _getCachedPresence(sanitizedUserId);
        });
  }

  /// Check if user is currently online with multiple verification methods
  Future<bool> isUserOnline(String userId) async {
    try {
      final sanitizedUserId = _sanitizeUserId(userId);

      // Check cache first (fastest)
      final cachedData = _getCachedPresence(sanitizedUserId);
      if (cachedData != null) {
        final cacheAge = DateTime.now().difference(
          _presenceCacheTime[sanitizedUserId]!,
        );
        if (cacheAge < const Duration(seconds: 10)) {
          return _evaluateOnlineStatus(cachedData);
        }
      }

      // Check main presence node with sanitized user ID
      try {
        final presenceSnapshot = await database
            .ref('presence/$sanitizedUserId')
            .get()
            .timeout(const Duration(seconds: 2));

        if (presenceSnapshot.exists) {
          final data = presenceSnapshot.value as Map<dynamic, dynamic>?;
          if (data != null) {
            final presenceData = Map<String, dynamic>.from(data);

            // Cache the result
            _presenceCache[sanitizedUserId] = presenceData;
            _presenceCacheTime[sanitizedUserId] = DateTime.now();

            return _evaluateOnlineStatus(presenceData);
          }
        }
      } catch (e) {
        print('⚠️ Realtime DB presence check failed for $userId: $e');
      }

      // Fallback to Firestore
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId) // Use original user ID for Firestore
            .get()
            .timeout(const Duration(seconds: 2));

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          return _evaluateFirestoreOnlineStatus(data);
        }
      } catch (e) {
        print('⚠️ Firestore presence check failed: $e');
      }

      // If all methods fail, return false (user offline)
      return false;
    } catch (e) {
      print('❌ Error checking if user is online: $e');
      return false;
    }
  }

  /// Evaluate online status from presence data
  bool _evaluateOnlineStatus(Map<String, dynamic> presenceData) {
    final isOnline = presenceData['online'] as bool? ?? false;

    if (!isOnline) return false;

    // Additional checks for stale data
    final lastSeenTimestamp = presenceData['lastSeen'] as int?;
    final heartbeatTimestamp = presenceData['heartbeat'] as int?;

    if (lastSeenTimestamp != null) {
      final lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp);
      final timeSinceLastSeen = DateTime.now().difference(lastSeen);

      // Consider offline if last seen is more than 2 minutes ago
      if (timeSinceLastSeen.inMinutes > 2) {
        return false;
      }
    }

    if (heartbeatTimestamp != null) {
      final lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(
        heartbeatTimestamp,
      );
      final timeSinceHeartbeat = DateTime.now().difference(lastHeartbeat);

      // Consider offline if no heartbeat for more than 1 minute
      if (timeSinceHeartbeat.inMinutes > 1) {
        return false;
      }
    }

    return true;
  }

  /// Evaluate online status from Firestore data
  bool _evaluateFirestoreOnlineStatus(Map<String, dynamic> data) {
    final isOnline = data['isOnline'] as bool? ?? false;

    if (!isOnline) return false;

    final lastSeen = data['lastSeen'] as Timestamp?;
    if (lastSeen != null) {
      final timeSinceLastSeen = DateTime.now().difference(lastSeen.toDate());

      // Consider offline if last seen is more than 2 minutes ago
      return timeSinceLastSeen.inMinutes <= 2;
    }

    return isOnline;
  }

  /// Get cached presence data
  Map<String, dynamic>? _getCachedPresence(String userId) {
    final cachedData = _presenceCache[userId];
    final cacheTime = _presenceCacheTime[userId];

    if (cachedData != null && cacheTime != null) {
      final cacheAge = DateTime.now().difference(cacheTime);
      if (cacheAge < _presenceCacheTimeout) {
        return cachedData;
      }
    }

    return null;
  }

  /// Get user's last seen timestamp with fallback
  Future<DateTime?> getUserLastSeen(String userId) async {
    try {
      // Check cache first
      final cachedData = _getCachedPresence(userId);
      if (cachedData != null) {
        final lastSeenTimestamp = cachedData['lastSeen'] as int?;
        if (lastSeenTimestamp != null) {
          return DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp);
        }
      }

      // Try Realtime Database
      try {
        final snapshot = await database
            .ref('presence/$userId/lastSeen')
            .get()
            .timeout(const Duration(seconds: 2));

        if (snapshot.exists) {
          final timestamp = snapshot.value as int?;
          if (timestamp != null) {
            return DateTime.fromMillisecondsSinceEpoch(timestamp);
          }
        }
      } catch (e) {
        print('⚠️ Realtime DB lastSeen timeout: $e');
      }

      // Fallback to Firestore
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get()
            .timeout(const Duration(seconds: 2));

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          final lastSeen = data['lastSeen'] as Timestamp?;
          return lastSeen?.toDate();
        }
      } catch (e) {
        print('⚠️ Firestore lastSeen timeout: $e');
      }

      return null;
    } catch (e) {
      print('❌ Error getting user last seen: $e');
      return null;
    }
  }

  Future<void> updateUserInfo({
    String? displayName,
    String? photoURL,
    Map<String, dynamic>? additionalInfo,
  }) async {
    try {
      if (_userPresenceRef == null || _currentUserId == null) {
        print('⚠️ Cannot update user info - presence not initialized');
        return;
      }

      print('🔄 Updating user info in presence...');

      final updates = <String, dynamic>{};

      if (displayName != null && displayName.isNotEmpty) {
        updates['displayName'] = displayName;
      }

      if (photoURL != null) {
        updates['photoURL'] = photoURL;
      }

      // Add any additional info provided
      if (additionalInfo != null) {
        updates.addAll(additionalInfo);
      }

      // Always update the timestamp
      updates['updatedAt'] = ServerValue.timestamp;

      if (updates.isNotEmpty) {
        // Update in Realtime Database
        await _userPresenceRef!
            .update(updates)
            .timeout(const Duration(seconds: 5));

        print('✅ User presence info updated in Realtime Database');

        // Also update in Firestore for consistency
        final firestoreUpdates = <String, dynamic>{};

        if (displayName != null && displayName.isNotEmpty) {
          firestoreUpdates['displayName'] = displayName;
        }

        if (photoURL != null) {
          firestoreUpdates['photoURL'] = photoURL;
        }

        if (additionalInfo != null) {
          // Filter out Realtime Database specific fields
          additionalInfo.forEach((key, value) {
            if (key != 'updatedAt' && value != ServerValue.timestamp) {
              firestoreUpdates[key] = value;
            }
          });
        }

        firestoreUpdates['presenceUpdatedAt'] = FieldValue.serverTimestamp();

        if (firestoreUpdates.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_currentUserId)
              .update(firestoreUpdates)
              .timeout(const Duration(seconds: 3));

          print('✅ User info updated in Firestore');
        }
      } else {
        print('⚠️ No updates to apply');
      }
    } catch (e) {
      print('❌ Error updating user presence info: $e');

      // Try to at least update Firestore as fallback
      if (_currentUserId != null) {
        try {
          final firestoreUpdates = <String, dynamic>{};

          if (displayName != null && displayName.isNotEmpty) {
            firestoreUpdates['displayName'] = displayName;
          }

          if (photoURL != null) {
            firestoreUpdates['photoURL'] = photoURL;
          }

          if (firestoreUpdates.isNotEmpty) {
            firestoreUpdates['updatedAt'] = FieldValue.serverTimestamp();

            await FirebaseFirestore.instance
                .collection('users')
                .doc(_currentUserId)
                .update(firestoreUpdates);

            print('✅ Fallback: Updated user info in Firestore only');
          }
        } catch (fallbackError) {
          print('❌ Fallback update also failed: $fallbackError');
        }
      }
    }
  }

  // Optional: Add this helper method to get current user info from presence
  Future<Map<String, dynamic>?> getCurrentUserInfo() async {
    try {
      if (_currentUserId == null) return null;

      // Try cache first
      final cachedData = _getCachedPresence(_currentUserId!);
      if (cachedData != null) {
        return {
          'displayName': cachedData['displayName'],
          'photoURL': cachedData['photoURL'],
          'online': cachedData['online'],
          'lastSeen': cachedData['lastSeen'],
        };
      }

      // Try Realtime Database
      if (_userPresenceRef != null) {
        final snapshot = await _userPresenceRef!.get().timeout(
          const Duration(seconds: 3),
        );
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>?;
          if (data != null) {
            return {
              'displayName': data['displayName'],
              'photoURL': data['photoURL'],
              'online': data['online'],
              'lastSeen': data['lastSeen'],
            };
          }
        }
      }

      // Fallback to Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId!)
          .get()
          .timeout(const Duration(seconds: 2));

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        return {
          'displayName': data['displayName'],
          'photoURL': data['photoURL'],
          'online': data['isOnline'],
          'lastSeen': (data['lastSeen'] as Timestamp?)?.toDate(),
        };
      }

      return null;
    } catch (e) {
      print('❌ Error getting current user info: $e');
      return null;
    }
  }

  /// Force refresh presence for a user
  Future<void> refreshUserPresence(String userId) async {
    try {
      // Clear cache
      _presenceCache.remove(userId);
      _presenceCacheTime.remove(userId);

      // Fetch fresh data
      await isUserOnline(userId);
    } catch (e) {
      print('❌ Error refreshing user presence: $e');
    }
  }

  /// Get connection status
  bool get isConnectedToRealtimeDB => _isConnectedToRealtimeDB;
  bool get isInitialized => _isInitialized;
  String? get currentUserId => _currentUserId;

  /// Get debug information
  Map<String, dynamic> getDebugInfo() {
    return {
      'isInitialized': _isInitialized,
      'isConnectedToRealtimeDB': _isConnectedToRealtimeDB,
      'currentUserId': _currentUserId,
      'cachedUsers': _presenceCache.length,
      'connectionRetryCount': _connectionRetryCount,
      'hasPresenceRef': _userPresenceRef != null,
      'hasConnectionsRef': _userConnectionsRef != null,
      'heartbeatActive': _heartbeatTimer?.isActive ?? false,
    };
  }

  /// Clear all cached data
  void clearCache() {
    _presenceCache.clear();
    _presenceCacheTime.clear();
    print('✅ Presence cache cleared');
  }

  /// Sign out and cleanup
  Future<void> signOut() async {
    try {
      print('🔴 Signing out from presence service...');

      // Set user offline first
      await setUserOffline();

      // Cancel all subscriptions and timers
      await _connectionStateSubscription?.cancel();
      await _presenceSubscription?.cancel();
      _connectionRetryTimer?.cancel();
      _heartbeatTimer?.cancel();
      _operationTimeoutTimer?.cancel();

      // Clear references
      _userPresenceRef = null;
      _userConnectionsRef = null;
      _currentUserId = null;
      _isInitialized = false;
      _isConnectedToRealtimeDB = false;
      _connectionRetryCount = 0;
      _isUpdatingPresence = false;

      // Clear cache
      clearCache();

      print('✅ Presence service sign out completed');
    } catch (e) {
      print('❌ Error in presence service sign out: $e');
    }
  }

  /// Monitor presence changes
  void _setupPresenceMonitoring() {
    if (_userPresenceRef == null) return;

    _presenceSubscription?.cancel();

    _presenceSubscription = _userPresenceRef!.onValue.listen(
      (event) {
        if (event.snapshot.exists) {
          final data = event.snapshot.value as Map<dynamic, dynamic>?;
          if (data != null && _currentUserId != null) {
            _presenceCache[_currentUserId!] = Map<String, dynamic>.from(data);
            _presenceCacheTime[_currentUserId!] = DateTime.now();
          }
        }
      },
      onError: (error) {
        print('❌ Error monitoring presence: $error');
      },
    );
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    await signOut();
  }
}

class PresenceDebouncer {
  static Timer? _debounceTimer;
  static bool _pendingOnlineStatus = true;
  static const Duration _debounceDuration = Duration(seconds: 3); // Increased

  static void setOnlineStatus(bool isOnline, Function() updateFunction) {
    _debounceTimer?.cancel();
    _pendingOnlineStatus = isOnline;

    _debounceTimer = Timer(_debounceDuration, () {
      print(
        '🕐 Debounced status update: ${_pendingOnlineStatus ? "Online" : "Offline"}',
      );
      try {
        updateFunction();
      } catch (e) {
        print('❌ Error in debounced update: $e');
      }
    });
  }

  static void cancelPendingUpdates() {
    _debounceTimer?.cancel();
  }
}
