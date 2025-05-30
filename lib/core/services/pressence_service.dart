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

  // Current user's presence reference
  DatabaseReference? _userPresenceRef;
  DatabaseReference? _userLastSeenRef;

  // Connection state listener
  late StreamSubscription<DatabaseEvent> _connectionStateSubscription;

  // Initialize presence system
  Future<void> initialize() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('⚠️ No authenticated user for presence');
        return;
      }

      // Enable offline persistence for Realtime Database
      database.setPersistenceEnabled(true);

      // Set up presence references
      _userPresenceRef = database.ref('presence/${currentUser.uid}');
      _userLastSeenRef = database.ref('lastSeen/${currentUser.uid}');

      // Set up connection state monitoring
      await _setupConnectionStateMonitoring();

      print('✅ Presence service initialized for ${currentUser.uid}');
    } catch (e) {
      print('❌ Error initializing presence service: $e');
    }
  }

  // Set up connection state monitoring
  Future<void> _setupConnectionStateMonitoring() async {
    try {
      final connectedRef = database.ref('.info/connected');

      _connectionStateSubscription = connectedRef.onValue.listen((event) {
        final isConnected = event.snapshot.value as bool? ?? false;

        if (isConnected) {
          _handleConnectionEstablished();
        } else {
          _handleConnectionLost();
        }
      });
    } catch (e) {
      print('❌ Error setting up connection monitoring: $e');
    }
  }

  // Handle when connection is established
  void _handleConnectionEstablished() async {
    try {
      if (_userPresenceRef == null) return;

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Set user as online
      await _userPresenceRef!.set({
        'online': true,
        'lastSeen': ServerValue.timestamp,
        'uid': currentUser.uid,
        'displayName': currentUser.displayName ?? 'Unknown',
        'photoURL': currentUser.photoURL,
      });

      // Set up automatic offline detection when user disconnects
      await _userPresenceRef!.onDisconnect().set({
        'online': false,
        'lastSeen': ServerValue.timestamp,
        'uid': currentUser.uid,
        'displayName': currentUser.displayName ?? 'Unknown',
        'photoURL': currentUser.photoURL,
      });

      // Also update lastSeen on disconnect
      await _userLastSeenRef?.onDisconnect().set(ServerValue.timestamp);

      // Update Firestore user document
      await _updateFirestoreOnlineStatus(true);

      print('✅ User marked as online');
    } catch (e) {
      print('❌ Error handling connection established: $e');
    }
  }

  // Handle when connection is lost
  void _handleConnectionLost() async {
    try {
      print('⚠️ Connection lost - user will be marked offline automatically');

      // Update Firestore to reflect offline status
      await _updateFirestoreOnlineStatus(false);
    } catch (e) {
      print('❌ Error handling connection lost: $e');
    }
  }

  // Update Firestore user document with online status
  Future<void> _updateFirestoreOnlineStatus(bool isOnline) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
            'isOnline': isOnline,
            'lastSeen': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('❌ Error updating Firestore online status: $e');
    }
  }

  // Manually set user as online (call when app becomes active)
  Future<void> setUserOnline() async {
    try {
      if (_userPresenceRef == null) await initialize();
      if (_userPresenceRef == null) return;

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await _userPresenceRef!.set({
        'online': true,
        'lastSeen': ServerValue.timestamp,
        'uid': currentUser.uid,
        'displayName': currentUser.displayName ?? 'Unknown',
        'photoURL': currentUser.photoURL,
      });

      await _updateFirestoreOnlineStatus(true);
      print('✅ User manually set as online');
    } catch (e) {
      print('❌ Error setting user online: $e');
    }
  }

  // Manually set user as offline (call when app goes to background)
  Future<void> setUserOffline() async {
    try {
      if (_userPresenceRef == null) return;

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await _userPresenceRef!.set({
        'online': false,
        'lastSeen': ServerValue.timestamp,
        'uid': currentUser.uid,
        'displayName': currentUser.displayName ?? 'Unknown',
        'photoURL': currentUser.photoURL,
      });

      await _userLastSeenRef?.set(ServerValue.timestamp);
      await _updateFirestoreOnlineStatus(false);

      print('✅ User manually set as offline');
    } catch (e) {
      print('❌ Error setting user offline: $e');
    }
  }

  // Get user presence stream
  Stream<Map<String, dynamic>?> getUserPresenceStream(String userId) {
    return database
        .ref('presence/$userId')
        .onValue
        .map((event) {
          if (event.snapshot.exists) {
            final data = event.snapshot.value as Map<dynamic, dynamic>?;
            if (data != null) {
              return Map<String, dynamic>.from(data);
            }
          }
          return null;
        })
        .handleError((error) {
          print('❌ Error in presence stream for $userId: $error');
          return null;
        });
  }

  // Get multiple users' presence status
  Stream<Map<String, Map<String, dynamic>>> getMultipleUsersPresenceStream(
    List<String> userIds,
  ) {
    if (userIds.isEmpty) {
      return Stream.value({});
    }

    return database
        .ref('presence')
        .onValue
        .map((event) {
          final Map<String, Map<String, dynamic>> presenceData = {};

          if (event.snapshot.exists) {
            final allPresence = event.snapshot.value as Map<dynamic, dynamic>?;
            if (allPresence != null) {
              for (final userId in userIds) {
                if (allPresence.containsKey(userId)) {
                  final userData =
                      allPresence[userId] as Map<dynamic, dynamic>?;
                  if (userData != null) {
                    presenceData[userId] = Map<String, dynamic>.from(userData);
                  }
                }
              }
            }
          }

          return presenceData;
        })
        .handleError((error) {
          print('❌ Error in multiple users presence stream: $error');
          return <String, Map<String, dynamic>>{};
        });
  }

  // Check if user is currently online
  Future<bool> isUserOnline(String userId) async {
    try {
      final snapshot = await database.ref('presence/$userId/online').get();
      return snapshot.value as bool? ?? false;
    } catch (e) {
      print('❌ Error checking if user is online: $e');
      return false;
    }
  }

  // Get user's last seen timestamp
  Future<DateTime?> getUserLastSeen(String userId) async {
    try {
      final snapshot = await database.ref('presence/$userId/lastSeen').get();
      final timestamp = snapshot.value as int?;

      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      print('❌ Error getting user last seen: $e');
      return null;
    }
  }

  // Update user's display name and photo in presence
  Future<void> updateUserInfo({String? displayName, String? photoURL}) async {
    try {
      if (_userPresenceRef == null) return;

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final updates = <String, dynamic>{};

      if (displayName != null) {
        updates['displayName'] = displayName;
      }

      if (photoURL != null) {
        updates['photoURL'] = photoURL;
      }

      if (updates.isNotEmpty) {
        await _userPresenceRef!.update(updates);
        print('✅ User presence info updated');
      }
    } catch (e) {
      print('❌ Error updating user presence info: $e');
    }
  }

  // Clean up old presence data (call periodically)
  Future<void> cleanupOldPresenceData({Duration? olderThan}) async {
    try {
      final cutoffTime = DateTime.now().subtract(
        olderThan ?? const Duration(days: 30),
      );

      final snapshot = await database.ref('presence').get();
      if (!snapshot.exists) return;

      final allPresence = snapshot.value as Map<dynamic, dynamic>;
      final batch = <String, dynamic>{};

      for (final entry in allPresence.entries) {
        final userId = entry.key as String;
        final userData = entry.value as Map<dynamic, dynamic>;
        final lastSeen = userData['lastSeen'] as int?;

        if (lastSeen != null) {
          final lastSeenDate = DateTime.fromMillisecondsSinceEpoch(lastSeen);

          if (lastSeenDate.isBefore(cutoffTime)) {
            batch['presence/$userId'] = null; // This will delete the entry
          }
        }
      }

      if (batch.isNotEmpty) {
        await database.ref().update(batch);
        print('✅ Cleaned up ${batch.length} old presence records');
      }
    } catch (e) {
      print('❌ Error cleaning up old presence data: $e');
    }
  }

  // Dispose and cleanup
  Future<void> dispose() async {
    try {
      // Cancel connection state subscription
      await _connectionStateSubscription.cancel();

      // Set user offline before disposing
      await setUserOffline();

      // Clear references
      _userPresenceRef = null;
      _userLastSeenRef = null;

      print('✅ Presence service disposed');
    } catch (e) {
      print('❌ Error disposing presence service: $e');
    }
  }

  // Sign out cleanup
  Future<void> signOut() async {
    try {
      await setUserOffline();
      await dispose();
      print('✅ Presence service sign out cleanup completed');
    } catch (e) {
      print('❌ Error in presence service sign out: $e');
    }
  }
}
