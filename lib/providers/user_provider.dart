import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onlyus/core/services/pressence_service.dart';
import '../core/services/firebase_service.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

// Provider for current user stream with real-time presence
final currentUserStreamProvider = StreamProvider<UserModel?>((ref) {
  final currentUserId =
      ref.watch(authControllerProvider.notifier).currentUserId;

  if (currentUserId == null) {
    return Stream.value(null);
  }

  return FirebaseService.getCombinedUserStream(currentUserId)
      .map((data) {
        if (data == null) return null;
        return UserModel.fromCombinedData(data);
      })
      .handleError((error) {
        print('❌ Error in current user stream: $error');
        return null;
      });
});

// Provider for partner user stream with real-time presence
final partnerUserStreamProvider = StreamProvider<UserModel?>((ref) {
  final currentUser = ref.watch(currentUserStreamProvider).value;

  if (currentUser?.partnerId == null) {
    return Stream.value(null);
  }

  return FirebaseService.getCombinedUserStream(currentUser!.partnerId!)
      .map((data) {
        if (data == null) return null;
        return UserModel.fromCombinedData(data);
      })
      .handleError((error) {
        print('❌ Error in partner user stream: $error');
        return null;
      });
});

// Provider for specific user presence (real-time only)
final userPresenceProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, userId) {
      return PresenceService.instance.getUserPresenceStream(userId).handleError(
        (error) {
          print('❌ Error in user presence stream for $userId: $error');
          return null;
        },
      );
    });

// Provider for multiple users presence
final multipleUsersPresenceProvider =
    StreamProvider.family<Map<String, Map<String, dynamic>>, List<String>>((
      ref,
      userIds,
    ) {
      return PresenceService.instance
          .getMultipleUsersPresenceStream(userIds)
          .handleError((error) {
            print('❌ Error in multiple users presence stream: $error');
            return <String, Map<String, dynamic>>{};
          });
    });

// Provider to check if a specific user is online
final isUserOnlineProvider = FutureProvider.family<bool, String>((
  ref,
  userId,
) async {
  try {
    return await PresenceService.instance.isUserOnline(userId);
  } catch (e) {
    print('❌ Error checking if user $userId is online: $e');
    return false;
  }
});

// Provider to get user's last seen time
final userLastSeenProvider = FutureProvider.family<DateTime?, String>((
  ref,
  userId,
) async {
  try {
    return await PresenceService.instance.getUserLastSeen(userId);
  } catch (e) {
    print('❌ Error getting last seen for user $userId: $e');
    return null;
  }
});

// User controller for managing user-related operations
class UserController extends StateNotifier<UserState> {
  final Ref _ref;

  UserController(this._ref) : super(const UserInitial());

  // Update user online status using presence service
  Future<void> updateOnlineStatus(bool isOnline) async {
    try {
      if (isOnline) {
        await PresenceService.instance.setUserOnline();
      } else {
        await PresenceService.instance.setUserOffline();
      }
    } catch (e) {
      print('❌ Error updating online status: $e');
    }
  }

  // Update user profile in Firestore and presence
  Future<void> updateUserProfile({
    String? displayName,
    String? photoURL,
  }) async {
    try {
      state = const UserLoading();

      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        state = const UserError('User not authenticated');
        return;
      }

      final userDoc = FirebaseService.usersCollection.doc(currentUserId);

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (displayName != null) {
        updateData['displayName'] = displayName;
      }

      if (photoURL != null) {
        updateData['photoURL'] = photoURL;
      }

      // Update Firestore
      await userDoc.update(updateData);

      // Update presence service
      await PresenceService.instance.updateUserInfo(
        displayName: displayName,
        photoURL: photoURL,
      );

      // Get updated user data
      final updatedUser = await _ref.read(userProvider(currentUserId).future);
      if (updatedUser != null) {
        state = UserLoaded(updatedUser);
      }
    } catch (e) {
      state = UserError('Failed to update profile: $e');
    }
  }

  // Update partner ID
  Future<void> updatePartnerId(String partnerId) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) throw Exception('User not authenticated');

      await FirebaseService.usersCollection.doc(currentUserId).update({
        'partnerId': partnerId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Partner ID updated successfully');
    } catch (e) {
      print('❌ Error updating partner ID: $e');
      rethrow;
    }
  }

  // Update OneSignal player ID
  Future<void> updateOneSignalPlayerId(String playerId) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return;

      await FirebaseService.usersCollection.doc(currentUserId).update({
        'oneSignalPlayerId': playerId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error updating OneSignal player ID: $e');
    }
  }

  // Get user by ID
  Future<UserModel?> getUserById(String userId) async {
    try {
      return await _ref.read(userProvider(userId).future);
    } catch (e) {
      print('❌ Error getting user by ID: $e');
      return null;
    }
  }

  // Search users (useful if you want to add more users later)
  Future<List<UserModel>> searchUsers(String query) async {
    try {
      if (query.trim().isEmpty) return [];

      final snapshot =
          await FirebaseService.usersCollection
              .where('displayName', isGreaterThanOrEqualTo: query)
              .where('displayName', isLessThanOrEqualTo: '$query\uf8ff')
              .limit(10)
              .get();

      return snapshot.docs
          .map(
            (doc) => UserModel.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>,
            ),
          )
          .toList();
    } catch (e) {
      print('❌ Error searching users: $e');
      return [];
    }
  }

  // Check if partner is available (for the two-user system)
  Future<bool> isPartnerAvailable() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return false;

      final usersSnapshot = await FirebaseService.usersCollection.get();

      // Count users (should be exactly 2 for this app)
      int userCount = 0;
      for (final doc in usersSnapshot.docs) {
        if (doc.exists) userCount++;
      }

      return userCount >= 2;
    } catch (e) {
      print('❌ Error checking partner availability: $e');
      return false;
    }
  }

  // Get all users (mainly for debugging)
  Future<List<UserModel>> getAllUsers() async {
    try {
      final snapshot = await FirebaseService.usersCollection.get();

      return snapshot.docs
          .where((doc) => doc.exists)
          .map(
            (doc) => UserModel.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>,
            ),
          )
          .toList();
    } catch (e) {
      print('❌ Error getting all users: $e');
      return [];
    }
  }

  // Manually set user online
  Future<void> setOnline() async {
    try {
      await PresenceService.instance.setUserOnline();
    } catch (e) {
      print('❌ Error setting user online: $e');
    }
  }

  // Manually set user offline
  Future<void> setOffline() async {
    try {
      await PresenceService.instance.setUserOffline();
    } catch (e) {
      print('❌ Error setting user offline: $e');
    }
  }
}

// User controller provider
final userControllerProvider = StateNotifierProvider<UserController, UserState>(
  (ref) => UserController(ref),
);

// Helper provider to get formatted last seen text for any user
final userLastSeenTextProvider = Provider.family<String, String>((ref, userId) {
  final presenceData = ref.watch(userPresenceProvider(userId)).value;

  if (presenceData == null) {
    return 'Last seen unknown';
  }

  final isOnline = presenceData['online'] as bool? ?? false;
  if (isOnline) {
    return 'Online';
  }

  final lastSeenTimestamp = presenceData['lastSeen'] as int?;
  if (lastSeenTimestamp == null) {
    return 'Last seen unknown';
  }

  final lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp);
  final now = DateTime.now();
  final difference = now.difference(lastSeen);

  if (difference.inMinutes < 1) {
    return 'Last seen just now';
  } else if (difference.inMinutes < 60) {
    return 'Last seen ${difference.inMinutes}m ago';
  } else if (difference.inHours < 24) {
    return 'Last seen ${difference.inHours}h ago';
  } else if (difference.inDays < 7) {
    return 'Last seen ${difference.inDays}d ago';
  } else {
    return 'Last seen long ago';
  }
});

// Helper provider to get online status color for any user
final userOnlineStatusColorProvider = Provider.family<Color, String>((
  ref,
  userId,
) {
  if (userId == FirebaseService.currentUserId) {
    return const Color(0xFF4CAF50); // Green
  }
  final presenceData = ref.watch(userPresenceProvider(userId)).value;

  if (presenceData == null) {
    return const Color(0xFF9E9E9E); // Gray
  }
  // You can add more logic here for other statuses if needed
  return const Color(
    0xFF4CAF50,
  ); // Default to green if presenceData is not null
});

// Current user provider (single user fetch)
final userProvider = FutureProvider.family<UserModel?, String>((
  ref,
  userId,
) async {
  try {
    final doc = await FirebaseService.usersCollection.doc(userId).get();

    if (doc.exists) {
      return UserModel.fromFirestore(
        doc as DocumentSnapshot<Map<String, dynamic>>,
      );
    }
    return null;
  } catch (e) {
    print('❌ Error fetching user $userId: $e');
    return null;
  }
});

// Simple user stream provider (Firestore only - for backward compatibility)
final userStreamProvider = StreamProvider.family<UserModel?, String>((
  ref,
  userId,
) {
  return FirebaseService.getUserStream(userId)
      .map((doc) {
        if (doc.exists && doc.data() != null) {
          return UserModel.fromFirestore(
            doc as DocumentSnapshot<Map<String, dynamic>>,
          );
        }
        return null;
      })
      .handleError((error) {
        print('❌ Error in user stream for $userId: $error');
        return null;
      });
});

// Partner user provider (single fetch) - for backward compatibility
final partnerUserProvider = FutureProvider<UserModel?>((ref) async {
  try {
    // Get current user ID
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return null;

    // Get current user document to find partner
    final currentUserDoc =
        await FirebaseService.usersCollection.doc(currentUserId).get();

    if (!currentUserDoc.exists) {
      // Fallback: Get all users and find the partner (not current user)
      final usersSnapshot = await FirebaseService.usersCollection.get();

      for (final doc in usersSnapshot.docs) {
        if (doc.id != currentUserId) {
          return UserModel.fromFirestore(
            doc as DocumentSnapshot<Map<String, dynamic>>,
          );
        }
      }
      return null;
    }

    final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
    final partnerId = currentUserData['partnerId'] as String?;

    if (partnerId == null || partnerId.isEmpty) {
      // Fallback: find any other user
      final usersSnapshot = await FirebaseService.usersCollection.get();

      for (final doc in usersSnapshot.docs) {
        if (doc.id != currentUserId) {
          return UserModel.fromFirestore(
            doc as DocumentSnapshot<Map<String, dynamic>>,
          );
        }
      }
      return null;
    }

    // Get partner by ID
    final partnerDoc =
        await FirebaseService.usersCollection.doc(partnerId).get();
    if (partnerDoc.exists) {
      return UserModel.fromFirestore(
        partnerDoc as DocumentSnapshot<Map<String, dynamic>>,
      );
    }

    return null;
  } catch (e) {
    print('❌ Error fetching partner user: $e');
    return null;
  }
});

// User state classes
abstract class UserState {
  const UserState();
}

class UserInitial extends UserState {
  const UserInitial();
}

class UserLoading extends UserState {
  const UserLoading();
}

class UserLoaded extends UserState {
  final UserModel user;
  const UserLoaded(this.user);
}

class UserError extends UserState {
  final String message;
  const UserError(this.message);
}
