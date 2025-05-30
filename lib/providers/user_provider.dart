import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onlyus/core/services/pressence_service.dart';
import '../core/services/firebase_service.dart';
import '../core/services/chat_service.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

// FIXED: Basic user provider (single fetch from Firestore)
final userProvider = FutureProvider.family<UserModel?, String>((ref, userId) async {
  try {
    final doc = await FirebaseService.usersCollection.doc(userId).get();
    
    if (doc.exists && doc.data() != null) {
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

// FIXED: Quick current user provider for immediate loading
final quickCurrentUserProvider = FutureProvider<UserModel?>((ref) async {
  final currentUserId = ref.watch(authControllerProvider.notifier).currentUserId;
  
  if (currentUserId == null) return null;
  
  try {
    final userDoc = await FirebaseService.usersCollection
        .doc(currentUserId)
        .get()
        .timeout(const Duration(seconds: 2));
    
    if (userDoc.exists && userDoc.data() != null) {
      return UserModel.fromFirestore(
        userDoc as DocumentSnapshot<Map<String, dynamic>>,
      );
    }
    return null;
  } catch (e) {
    print('❌ Error in quick current user provider: $e');
    return null;
  }
});

// FIXED: Quick partner provider for immediate loading
final quickPartnerProvider = FutureProvider<UserModel?>((ref) async {
  final currentUserId = ref.watch(authControllerProvider.notifier).currentUserId;
  
  if (currentUserId == null) return null;
  
  print('🚀 Quick partner provider loading...');
  
  try {
    // First try to get partner ID from current user
    final currentUserDoc = await FirebaseService.usersCollection
        .doc(currentUserId)
        .get()
        .timeout(const Duration(seconds: 2));
    
    if (currentUserDoc.exists) {
      final userData = currentUserDoc.data() as Map<String, dynamic>;
      final partnerId = userData['partnerId'] as String?;
      
      if (partnerId != null && partnerId.isNotEmpty) {
        return await _getPartnerWithPresence(partnerId);
      }
    }
    
    // Fallback to any other user
    return await _findAnyOtherUserWithPresence(currentUserId);
  } catch (e) {
    print('❌ Error in quick partner provider: $e');
    return null;
  }
});

// FIXED: Real-time current user provider with frequent presence updates
final realTimeCurrentUserProvider = StreamProvider<UserModel?>((ref) {
  final currentUserId = ref.watch(authControllerProvider.notifier).currentUserId;

  if (currentUserId == null) {
    return Stream.value(null);
  }

  print('🔍 Setting up real-time current user stream for: $currentUserId');

  // Combine Firestore user data with real-time presence updates
  return FirebaseService.usersCollection
      .doc(currentUserId)
      .snapshots()
      .asyncMap((firestoreDoc) async {
        if (!firestoreDoc.exists || firestoreDoc.data() == null) return null;
        
        final firestoreData = firestoreDoc.data() as Map<String, dynamic>;
        
        try {
          // FIXED: Use static getter correctly
          final presenceSnapshot = await PresenceService.database
              .ref('presence/$currentUserId')
              .get()
              .timeout(const Duration(seconds: 2));
          
          bool isOnline = false;
          int? lastSeenTimestamp;
          
          if (presenceSnapshot.exists && presenceSnapshot.value != null) {
            final presenceData = presenceSnapshot.value as Map<dynamic, dynamic>;
            isOnline = presenceData['online'] as bool? ?? false;
            lastSeenTimestamp = presenceData['lastSeen'] as int?;
            
            print('📋 Current user presence - Online: $isOnline, LastSeen: $lastSeenTimestamp');
          }
          
          // Create user model with real-time presence data
          return UserModel.fromCombinedData({
            ...firestoreData,
            'uid': currentUserId,
            'isOnline': isOnline,
            'realtimeLastSeen': lastSeenTimestamp,
          });
        } catch (e) {
          print('⚠️ Error getting real-time presence for current user: $e');
          // Return user with Firestore data only
          return UserModel.fromFirestore(firestoreDoc as DocumentSnapshot<Map<String, dynamic>>);
        }
      })
      .handleError((error) {
        print('❌ Error in real-time current user stream: $error');
        return null;
      });
});

// FIXED: Real-time partner user provider with frequent presence updates
final realTimePartnerUserProvider = StreamProvider<UserModel?>((ref) {
  final currentUserId = ref.watch(authControllerProvider.notifier).currentUserId;
  
  if (currentUserId == null) {
    return Stream.value(null);
  }

  print('🔍 Setting up real-time partner user stream');

  // Get partner information and stream their data with presence
  return FirebaseService.usersCollection
      .doc(currentUserId)
      .snapshots()
      .asyncMap((currentUserDoc) async {
        if (!currentUserDoc.exists) {
          return await _findAnyOtherUserWithPresence(currentUserId);
        }
        
        final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
        String? partnerId = currentUserData['partnerId'] as String?;
        
        print('📋 Partner ID from user doc: $partnerId');
        
        // Strategy 1: Use partnerId if available
        if (partnerId != null && partnerId.isNotEmpty) {
          final partner = await _getPartnerWithPresence(partnerId);
          if (partner != null) {
            print('✅ Found partner by ID: ${partner.displayName}');
            return partner;
          }
        }
        
        // Strategy 2: Find any other user as fallback
        final fallbackPartner = await _findAnyOtherUserWithPresence(currentUserId);
        if (fallbackPartner != null) {
          print('✅ Found fallback partner: ${fallbackPartner.displayName}');
        } else {
          print('❌ No partner found with any strategy');
        }
        
        return fallbackPartner;
      })
      .handleError((error) {
        print('❌ Error in real-time partner user stream: $error');
        return null;
      });
});

// FIXED: Helper function to get partner with real-time presence
Future<UserModel?> _getPartnerWithPresence(String partnerId) async {
  try {
    print('🔍 Getting partner with presence: $partnerId');
    
    // Get Firestore data
    final partnerDoc = await FirebaseService.usersCollection
        .doc(partnerId)
        .get()
        .timeout(const Duration(seconds: 3));
        
    if (!partnerDoc.exists || partnerDoc.data() == null) {
      print('❌ Partner document not found: $partnerId');
      return null;
    }
    
    final firestoreData = partnerDoc.data() as Map<String, dynamic>;
    
    try {
      // FIXED: Use static getter correctly
      final presenceSnapshot = await PresenceService.database
          .ref('presence/$partnerId')
          .get()
          .timeout(const Duration(seconds: 2));
      
      bool isOnline = false;
      int? lastSeenTimestamp;
      
      if (presenceSnapshot.exists && presenceSnapshot.value != null) {
        final presenceData = presenceSnapshot.value as Map<dynamic, dynamic>;
        isOnline = presenceData['online'] as bool? ?? false;
        lastSeenTimestamp = presenceData['lastSeen'] as int?;
        
        print('📋 Partner presence - Online: $isOnline, LastSeen: $lastSeenTimestamp');
      } else {
        print('⚠️ No presence data found for partner: $partnerId');
      }

      return UserModel.fromCombinedData({
        ...firestoreData,
        'uid': partnerId,
        'isOnline': isOnline,
        'realtimeLastSeen': lastSeenTimestamp,
      });
    } catch (e) {
      print('⚠️ Error getting presence data for partner $partnerId: $e');
      // Return partner data without real-time presence
      return UserModel.fromFirestore(
        partnerDoc as DocumentSnapshot<Map<String, dynamic>>,
      );
    }
  } catch (e) {
    print('❌ Error getting partner by ID $partnerId: $e');
    return null;
  }
}

// FIXED: Helper function to find any other user with presence
Future<UserModel?> _findAnyOtherUserWithPresence(String currentUserId) async {
  try {
    print('🔍 Finding any other user with presence as fallback...');
    
    final usersQuery = await FirebaseService.usersCollection
        .where(FieldPath.documentId, isNotEqualTo: currentUserId)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 3));
    
    if (usersQuery.docs.isNotEmpty) {
      final otherUserDoc = usersQuery.docs.first;
      final userData = otherUserDoc.data();
      final userId = otherUserDoc.id;
      
      print('✅ Found fallback user: $userId');
      
      try {
        // FIXED: Use static getter correctly
        final presenceSnapshot = await PresenceService.database
            .ref('presence/$userId')
            .get()
            .timeout(const Duration(seconds: 2));
        
        bool isOnline = false;
        int? lastSeenTimestamp;
        
        if (presenceSnapshot.exists && presenceSnapshot.value != null) {
          final presenceData = presenceSnapshot.value as Map<dynamic, dynamic>;
          isOnline = presenceData['online'] as bool? ?? false;
          lastSeenTimestamp = presenceData['lastSeen'] as int?;
        }
        
        return UserModel.fromCombinedData({
          ...userData,
          'uid': userId,
          'isOnline': isOnline,
          'realtimeLastSeen': lastSeenTimestamp,
        });
      } catch (e) {
        print('⚠️ Error getting presence for fallback user: $e');
        return UserModel.fromFirestore(
          otherUserDoc as DocumentSnapshot<Map<String, dynamic>>,
        );
      }
    }
    
    print('❌ No other users found');
    return null;
  } catch (e) {
    print('❌ Error finding fallback user: $e');
    return null;
  }
}

// FIXED: Live presence status provider that updates every few seconds
final livePresenceStatusProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, userId) {
  return PresenceService.instance
      .getUserPresenceStream(userId)
      .map((data) {
        if (data == null) return null;
        
        final isOnline = data['online'] as bool? ?? false;
        final lastSeenTimestamp = data['lastSeen'] as int?;
        final lastSeen = lastSeenTimestamp != null 
            ? DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp)
            : null;
        
        return {
          'isOnline': isOnline,
          'lastSeen': lastSeen,
          'lastSeenTimestamp': lastSeenTimestamp,
          'status': isOnline ? 'Online' : _getLastSeenText(lastSeen),
        };
      })
      .handleError((error) {
        print('❌ Error in live presence status stream for $userId: $error');
        return null;
      });
});

// Helper function to get last seen text
String _getLastSeenText(DateTime? lastSeen) {
  if (lastSeen == null) return 'Offline';
  
  final now = DateTime.now();
  final difference = now.difference(lastSeen);
  
  if (difference.inSeconds < 30) {
    return 'Just now';
  } else if (difference.inMinutes < 1) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  } else if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  } else {
    return 'Long ago';
  }
}

// FIXED: Enhanced typing status provider
final enhancedTypingStatusProvider = StreamProvider.family<bool, String>((ref, userId) {
  try {
    final chatService = ChatService.instance;
    final chatId = chatService.activeChatId;

    if (chatId == null || chatId.isEmpty) {
      return Stream.value(false);
    }

    return FirebaseService.chatsCollection
        .doc(chatId)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) return false;
          
          final chatData = doc.data() as Map<String, dynamic>;
          final typingUsers = chatData['typingUsers'] as Map<String, dynamic>? ?? {};
          
          return typingUsers[userId] as bool? ?? false;
        })
        .distinct()
        .handleError((error) {
          print('❌ Enhanced typing status stream error: $error');
          return false;
        });
  } catch (e) {
    print('❌ Error setting up typing status provider: $e');
    return Stream.value(false);
  }
});

// Provider for quick user status (used in UI)
final userQuickStatusProvider = Provider.family<String, UserModel?>((ref, user) {
  if (user == null) return 'Unknown';
  
  // Get live presence data
  final presenceData = ref.watch(livePresenceStatusProvider(user.uid)).value;
  
  if (presenceData != null) {
    final isOnline = presenceData['isOnline'] as bool? ?? false;
    
    if (isOnline) {
      return 'Online';
    } else {
      final lastSeen = presenceData['lastSeen'] as DateTime?;
      return _getLastSeenText(lastSeen);
    }
  }
  
  // Fallback to user model status
  return user.chatStatusText;
});

// Provider for profile status (more detailed)
final userProfileStatusProvider = Provider.family<String, UserModel?>((ref, user) {
  if (user == null) return 'Unknown';
  
  // Get live presence data
  final presenceData = ref.watch(livePresenceStatusProvider(user.uid)).value;
  
  if (presenceData != null) {
    final isOnline = presenceData['isOnline'] as bool? ?? false;
    
    if (isOnline) {
      return 'Online now';
    } else {
      final lastSeen = presenceData['lastSeen'] as DateTime?;
      return _getDetailedLastSeenText(lastSeen);
    }
  }
  
  // Fallback to user model status
  return user.profileStatusText;
});

// Helper function for detailed last seen text
String _getDetailedLastSeenText(DateTime? lastSeen) {
  if (lastSeen == null) return 'Last seen unknown';
  
  final now = DateTime.now();
  final difference = now.difference(lastSeen);
  
  if (difference.inSeconds < 30) {
    return 'Active just now';
  } else if (difference.inMinutes < 1) {
    return 'Active ${difference.inSeconds} seconds ago';
  } else if (difference.inMinutes < 60) {
    return 'Last seen ${difference.inMinutes} minutes ago';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    return 'Last seen $hours ${hours == 1 ? 'hour' : 'hours'} ago';
  } else if (difference.inDays < 30) {
    final days = difference.inDays;
    return 'Last seen $days ${days == 1 ? 'day' : 'days'} ago';
  } else {
    final months = (difference.inDays / 30).floor();
    return 'Last seen $months ${months == 1 ? 'month' : 'months'} ago';
  }
}

// FIXED: Enhanced current user provider that combines quick loading with real-time updates
final enhancedCurrentUserProvider = Provider<AsyncValue<UserModel?>>((ref) {
  final streamValue = ref.watch(realTimeCurrentUserProvider);
  final quickValue = ref.watch(quickCurrentUserProvider);
  
  // If stream is loading but we have quick data, use that
  return streamValue.when(
    data: (user) => AsyncValue.data(user),
    loading: () {
      // While stream is loading, check if we have quick data
      return quickValue.when(
        data: (user) => AsyncValue.data(user),
        loading: () => const AsyncValue.loading(),
        error: (error, stack) => AsyncValue.error(error, stack),
      );
    },
    error: (error, stack) {
      // On stream error, fallback to quick data if available
      return quickValue.when(
        data: (user) => AsyncValue.data(user),
        loading: () => AsyncValue.error(error, stack),
        error: (_, __) => AsyncValue.error(error, stack),
      );
    },
  );
});

// FIXED: Enhanced partner provider that combines quick loading with real-time updates
final enhancedPartnerProvider = Provider<AsyncValue<UserModel?>>((ref) {
  final streamValue = ref.watch(realTimePartnerUserProvider);
  final quickValue = ref.watch(quickPartnerProvider);
  
  return streamValue.when(
    data: (partner) => AsyncValue.data(partner),
    loading: () {
      // While stream is loading, check if we have quick data
      return quickValue.when(
        data: (partner) => AsyncValue.data(partner),
        loading: () => const AsyncValue.loading(),
        error: (error, stack) => AsyncValue.error(error, stack),
      );
    },
    error: (error, stack) {
      // On stream error, fallback to quick data if available
      return quickValue.when(
        data: (partner) => AsyncValue.data(partner),
        loading: () => AsyncValue.error(error, stack),
        error: (_, __) => AsyncValue.error(error, stack),
      );
    },
  );
});

// Backward compatibility providers
final currentUserStreamProvider = realTimeCurrentUserProvider;
final partnerUserStreamProvider = realTimePartnerUserProvider;
final typingStatusProvider = enhancedTypingStatusProvider;

// FIXED: Provider for current user presence (real-time only)
final userPresenceProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, userId) {
  return PresenceService.instance.getUserPresenceStream(userId).handleError(
    (error) {
      print('❌ Error in user presence stream for $userId: $error');
      return null;
    },
  );
});

// FIXED: Provider for multiple users presence
final multipleUsersPresenceProvider = StreamProvider.family<Map<String, Map<String, dynamic>>, List<String>>((ref, userIds) {
  return PresenceService.instance
      .getMultipleUsersPresenceStream(userIds)
      .handleError((error) {
        print('❌ Error in multiple users presence stream: $error');
        return <String, Map<String, dynamic>>{};
      });
});

// FIXED: Provider to check if a specific user is online
final isUserOnlineProvider = FutureProvider.family<bool, String>((ref, userId) async {
  try {
    return await PresenceService.instance.isUserOnline(userId);
  } catch (e) {
    print('❌ Error checking if user $userId is online: $e');
    return false;
  }
});

// FIXED: Provider to get user's last seen time
final userLastSeenProvider = FutureProvider.family<DateTime?, String>((ref, userId) async {
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

  Future<UserModel?> getUserById(String userId) async {
    try {
      return await _ref.read(userProvider(userId).future);
    } catch (e) {
      print('❌ Error getting user by ID: $e');
      return null;
    }
  }

  Future<void> setOnline() async {
    try {
      await PresenceService.instance.setUserOnline();
    } catch (e) {
      print('❌ Error setting user online: $e');
    }
  }

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