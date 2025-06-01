// import 'dart:async';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import '../core/services/firebase_service.dart';
// import '../core/services/cache_service.dart';
// import '../core/services/pressence_service.dart';
// import '../models/user_model.dart';
// import 'auth_provider.dart';

// // ============================================================================
// // CACHED USER PROVIDERS
// // ============================================================================

// /// Enhanced current user provider with intelligent caching
// final cachedCurrentUserProvider = StateNotifierProvider<CachedUserController, AsyncValue<UserModel?>>((ref) {
//   return CachedUserController(ref, CacheService.instance, true);
// });

// /// Enhanced partner user provider with intelligent caching
// final cachedPartnerUserProvider = StateNotifierProvider<CachedUserController, AsyncValue<UserModel?>>((ref) {
//   return CachedUserController(ref, CacheService.instance, false);
// });

// /// User controller with smart caching strategy
// class CachedUserController extends StateNotifier<AsyncValue<UserModel?>> {
//   final Ref _ref;
//   final CacheService _cacheService;
//   final bool _isCurrentUser;
  
//   StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;
//   StreamSubscription<Map<String, dynamic>?>? _presenceSubscription;
//   Timer? _backgroundSyncTimer;
//   Timer? _cacheValidationTimer;
  
//   UserModel? _cachedUser;
//   bool _isListening = false;
//   bool _hasInitialLoad = false;

//   CachedUserController(this._ref, this._cacheService, this._isCurrentUser) 
//       : super(const AsyncValue.loading()) {
//     _initialize();
//   }

//   Future<void> _initialize() async {
//     try {
//       print('🔍 ${_isCurrentUser ? 'Current' : 'Partner'} user controller initializing...');
      
//       // Step 1: Load from cache immediately for instant UI
//       await _loadFromCache();
      
//       // Step 2: Setup real-time listeners
//       await _setupRealtimeListeners();
      
//       // Step 3: Start background sync
//       _startBackgroundSync();
      
//       // Step 4: Setup cache validation
//       _startCacheValidation();
      
//     } catch (e) {
//       print('❌ Error initializing cached user controller: $e');
//       state = AsyncValue.error(e, StackTrace.current);
//     }
//   }

//   /// Step 1: Load from cache for instant UI
//   Future<void> _loadFromCache() async {
//     try {
//       final cachedUser = _isCurrentUser 
//           ? _cacheService.getCachedCurrentUser()
//           : _cacheService.getCachedPartnerUser();
      
//       if (cachedUser != null) {
//         _cachedUser = cachedUser;
//         state = AsyncValue.data(cachedUser);
//         _hasInitialLoad = true;
        
//         print('✅ ${_isCurrentUser ? 'Current' : 'Partner'} user loaded from cache: ${cachedUser.displayName}');
//       } else {
//         print('⚠️ No cached ${_isCurrentUser ? 'current' : 'partner'} user found');
//       }
//     } catch (e) {
//       print('❌ Error loading user from cache: $e');
//     }
//   }

//   /// Step 2: Setup real-time listeners for data freshness
//   Future<void> _setupRealtimeListeners() async {
//     if (_isListening) return;
    
//     try {
//       final userId = await _getUserId();
//       if (userId == null) {
//         if (!_hasInitialLoad) {
//           state = const AsyncValue.data(null);
//         }
//         return;
//       }

//       print('📡 Setting up real-time listeners for user: $userId');
      
//       // Listen to Firestore changes
//       _userSubscription = FirebaseService.usersCollection
//           .doc(userId)
//           .snapshots()
//           .listen(
//             (snapshot) => _handleFirestoreUpdate(snapshot),
//             onError: (error) {
//               print('❌ Firestore user stream error: $error');
//               // Don't change state on error if we have cached data
//               if (_cachedUser == null) {
//                 state = AsyncValue.error(error, StackTrace.current);
//               }
//             },
//           );

//       // Listen to presence changes
//       _presenceSubscription = PresenceService.instance
//           .getUserPresenceStream(userId)
//           .listen(
//             (presence) => _handlePresenceUpdate(presence),
//             onError: (error) {
//               print('❌ Presence stream error: $error');
//               // Presence errors are non-critical
//             },
//           );

//       _isListening = true;
//       print('✅ Real-time listeners setup for ${_isCurrentUser ? 'current' : 'partner'} user');
      
//     } catch (e) {
//       print('❌ Error setting up real-time listeners: $e');
//     }
//   }

//   /// Handle Firestore document updates
//   void _handleFirestoreUpdate(DocumentSnapshot<Map<String, dynamic>> snapshot) {
//     try {
//       if (!snapshot.exists || snapshot.data() == null) {
//         if (!_hasInitialLoad) {
//           state = const AsyncValue.data(null);
//         }
//         return;
//       }

//       final firestoreData = snapshot.data()!;
//       final userId = snapshot.id;
      
//       // Create updated user model
//       UserModel updatedUser;
      
//       if (_cachedUser != null) {
//         // Merge with cached presence data if available
//         updatedUser = UserModel.fromCombinedData({
//           ...firestoreData,
//           'uid': userId,
//           'isOnline': _cachedUser!.isOnline, // Keep cached presence
//           'realtimeLastSeen': _cachedUser!.realtimeLastSeen?.millisecondsSinceEpoch,
//         });
//       } else {
//         updatedUser = UserModel.fromFirestore(snapshot);
//       }

//       // Check if data actually changed to avoid unnecessary updates
//       if (_cachedUser == null || _hasUserDataChanged(_cachedUser!, updatedUser)) {
//         _cachedUser = updatedUser;
//         state = AsyncValue.data(updatedUser);
        
//         // Cache the updated user
//         _cacheUpdatedUser(updatedUser);
        
//         print('✅ ${_isCurrentUser ? 'Current' : 'Partner'} user updated from Firestore');
//       }
      
//       _hasInitialLoad = true;
      
//     } catch (e) {
//       print('❌ Error handling Firestore update: $e');
//     }
//   }

//   /// Handle presence updates
//   void _handlePresenceUpdate(Map<String, dynamic>? presence) {
//     try {
//       if (_cachedUser == null || presence == null) return;

//       final isOnline = presence['online'] as bool? ?? false;
//       final lastSeenTimestamp = presence['lastSeen'] as int?;
//       final realtimeLastSeen = lastSeenTimestamp != null 
//           ? DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp)
//           : null;

//       // Check if presence actually changed
//       if (_cachedUser!.isOnline != isOnline || 
//           _cachedUser!.realtimeLastSeen != realtimeLastSeen) {
        
//         final updatedUser = _cachedUser!.copyWith(
//           isOnline: isOnline,
//           realtimeLastSeen: realtimeLastSeen,
//         );

//         _cachedUser = updatedUser;
//         state = AsyncValue.data(updatedUser);
        
//         // Cache presence data separately for quick access
//         _cacheService.cacheUserPresence(_cachedUser!.uid, presence);
        
//         // Cache updated user
//         _cacheUpdatedUser(updatedUser);
        
//         print('✅ ${_isCurrentUser ? 'Current' : 'Partner'} user presence updated');
//       }
      
//     } catch (e) {
//       print('❌ Error handling presence update: $e');
//     }
//   }

//   /// Check if user data has meaningfully changed
//   bool _hasUserDataChanged(UserModel oldUser, UserModel newUser) {
//     return oldUser.displayName != newUser.displayName ||
//            oldUser.photoURL != newUser.photoURL ||
//            oldUser.email != newUser.email ||
//            oldUser.partnerId != newUser.partnerId ||
//            oldUser.isConnected != newUser.isConnected ||
//            oldUser.showOnlineStatus != newUser.showOnlineStatus ||
//            oldUser.showLastSeen != newUser.showLastSeen ||
//            oldUser.notificationEnabled != newUser.notificationEnabled;
//   }

//   /// Cache updated user data
//   Future<void> _cacheUpdatedUser(UserModel user) async {
//     try {
//       if (_isCurrentUser) {
//         await _cacheService.cacheCurrentUser(user);
//       } else {
//         await _cacheService.cachePartnerUser(user);
//       }
//     } catch (e) {
//       print('❌ Error caching updated user: $e');
//     }
//   }

//   /// Get user ID based on controller type
//   Future<String?> _getUserId() async {
//     if (_isCurrentUser) {
//       return _ref.read(authControllerProvider.notifier).currentUserId;
//     } else {
//       // For partner user, get partner ID from current user
//       final currentUserId = _ref.read(authControllerProvider.notifier).currentUserId;
//       if (currentUserId == null) return null;
      
//       try {
//         // First check cached current user for partner ID
//         final cachedCurrentUser = _cacheService.getCachedCurrentUser();
//         if (cachedCurrentUser?.partnerId != null) {
//           return cachedCurrentUser!.partnerId;
//         }
        
//         // Fallback to Firestore
//         final currentUserDoc = await FirebaseService.usersCollection
//             .doc(currentUserId)
//             .get()
//             .timeout(const Duration(seconds: 3));
            
//         if (currentUserDoc.exists) {
//           final userData = currentUserDoc.data() as Map<String, dynamic>;
//           return userData['partnerId'] as String?;
//         }
        
//         return null;
//       } catch (e) {
//         print('❌ Error getting partner ID: $e');
//         return null;
//       }
//     }
//   }

//   /// Step 3: Background sync to keep data fresh
//   void _startBackgroundSync() {
//     _backgroundSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
//       await _performBackgroundSync();
//     });
//   }

//   /// Perform background sync
//   Future<void> _performBackgroundSync() async {
//     try {
//       if (!_isListening) return;
      
//       final userId = await _getUserId();
//       if (userId == null) return;
      
//       print('🔄 Performing background sync for ${_isCurrentUser ? 'current' : 'partner'} user');
      
//       // Get fresh data from Firestore
//       final userDoc = await FirebaseService.usersCollection
//           .doc(userId)
//           .get(const GetOptions(source: Source.server))
//           .timeout(const Duration(seconds: 5));
          
//       if (userDoc.exists && userDoc.data() != null) {
//         _handleFirestoreUpdate(userDoc);
//       }
      
//       // Get fresh presence data
//       try {
//         final isOnline = await PresenceService.instance.isUserOnline(userId);
//         final lastSeen = await PresenceService.instance.getUserLastSeen(userId);
        
//         final presence = {
//           'online': isOnline,
//           'lastSeen': lastSeen?.millisecondsSinceEpoch,
//         };
        
//         _handlePresenceUpdate(presence);
//       } catch (e) {
//         print('⚠️ Error syncing presence in background: $e');
//       }
      
//     } catch (e) {
//       print('❌ Error in background sync: $e');
//     }
//   }

//   /// Step 4: Cache validation to ensure data integrity
//   void _startCacheValidation() {
//     _cacheValidationTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
//       await _validateCache();
//     });
//   }

//   /// Validate cache integrity
//   Future<void> _validateCache() async {
//     try {
//       final cachedUser = _isCurrentUser 
//           ? _cacheService.getCachedCurrentUser()
//           : _cacheService.getCachedPartnerUser();
          
//       if (cachedUser != null && _cachedUser != null) {
//         // Check if cached data is consistent
//         if (cachedUser.uid != _cachedUser!.uid ||
//             cachedUser.displayName != _cachedUser!.displayName) {
//           print('⚠️ Cache inconsistency detected, refreshing...');
//           await _loadFromCache();
//         }
//       }
      
//       // Clear expired caches
//       await _cacheService.clearExpiredCaches();
      
//     } catch (e) {
//       print('❌ Error validating cache: $e');
//     }
//   }

//   /// Force refresh from server
//   Future<void> forceRefresh() async {
//     try {
//       print('🔄 Force refreshing ${_isCurrentUser ? 'current' : 'partner'} user...');
      
//       final userId = await _getUserId();
//       if (userId == null) {
//         state = const AsyncValue.data(null);
//         return;
//       }

//       state = const AsyncValue.loading();
      
//       // Get fresh data from server
//       final userDoc = await FirebaseService.usersCollection
//           .doc(userId)
//           .get(const GetOptions(source: Source.server))
//           .timeout(const Duration(seconds: 8));
          
//       if (userDoc.exists && userDoc.data() != null) {
//         final userData = userDoc.data()!;
        
//         // Get fresh presence
//         try {
//           final isOnline = await PresenceService.instance.isUserOnline(userId);
//           final lastSeen = await PresenceService.instance.getUserLastSeen(userId);
          
//           final user = UserModel.fromCombinedData({
//             ...userData,
//             'uid': userId,
//             'isOnline': isOnline,
//             'realtimeLastSeen': lastSeen?.millisecondsSinceEpoch,
//           });
          
//           _cachedUser = user;
//           state = AsyncValue.data(user);
          
//           // Update cache
//           await _cacheUpdatedUser(user);
          
//           print('✅ ${_isCurrentUser ? 'Current' : 'Partner'} user force refreshed');
          
//         } catch (e) {
//           // Fallback without presence
//           final user = UserModel.fromFirestore(userDoc);
//           _cachedUser = user;
//           state = AsyncValue.data(user);
//           await _cacheUpdatedUser(user);
//         }
//       } else {
//         state = const AsyncValue.data(null);
//       }
      
//     } catch (e) {
//       print('❌ Error force refreshing user: $e');
//       state = AsyncValue.error(e, StackTrace.current);
//     }
//   }

//   /// Get current cached user data (synchronous)
//   UserModel? getCachedUser() => _cachedUser;

//   /// Check if user data is stale
//   bool isDataStale() {
//     final lastSync = _cacheService.getLastSync(_isCurrentUser ? 'current_user' : 'partner_user');
//     if (lastSync == null) return true;
    
//     return DateTime.now().difference(lastSync).inMinutes > 30;
//   }

//   @override
//   void dispose() {
//     _userSubscription?.cancel();
//     _presenceSubscription?.cancel();
//     _backgroundSyncTimer?.cancel();
//     _cacheValidationTimer?.cancel();
//     super.dispose();
//   }
// }

// // ============================================================================
// // UTILITY PROVIDERS
// // ============================================================================

// /// Provider for current user with fallback strategy
// final optimizedCurrentUserProvider = Provider<AsyncValue<UserModel?>>((ref) {
//   final cachedUser = ref.watch(cachedCurrentUserProvider);
  
//   // If cached user is loading and we have no data, try quick fallback
//   return cachedUser.when(
//     data: (user) => AsyncValue.data(user),
//     loading: () {
//       // Try to get cached data while loading
//       final cachedData = CacheService.instance.getCachedCurrentUser();
//       if (cachedData != null) {
//         return AsyncValue.data(cachedData);
//       }
//       return const AsyncValue.loading();
//     },
//     error: (error, stack) {
//       // On error, fallback to cached data if available
//       final cachedData = CacheService.instance.getCachedCurrentUser();
//       if (cachedData != null) {
//         return AsyncValue.data(cachedData);
//       }
//       return AsyncValue.error(error, stack);
//     },
//   );
// });

// /// Provider for partner user with fallback strategy
// final optimizedPartnerUserProvider = Provider<AsyncValue<UserModel?>>((ref) {
//   final cachedUser = ref.watch(cachedPartnerUserProvider);
  
//   return cachedUser.when(
//     data: (user) => AsyncValue.data(user),
//     loading: () {
//       final cachedData = CacheService.instance.getCachedPartnerUser();
//       if (cachedData != null) {
//         return AsyncValue.data(cachedData);
//       }
//       return const AsyncValue.loading();
//     },
//     error: (error, stack) {
//       final cachedData = CacheService.instance.getCachedPartnerUser();
//       if (cachedData != null) {
//         return AsyncValue.data(cachedData);
//       }
//       return AsyncValue.error(error, stack);
//     },
//   );
// });

// /// Provider for user presence with caching
// final cachedUserPresenceProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, userId) {
//   // First check cache
//   final cachedPresence = CacheService.instance.getCachedUserPresence(userId);
  
//   if (cachedPresence != null) {
//     // Return cached data immediately, then stream fresh data
//     return Stream.value(cachedPresence).followedBy(
//       PresenceService.instance.getUserPresenceStream(userId).asyncMap((presence) async {
//         // Cache fresh presence data
//         if (presence != null) {
//           await CacheService.instance.cacheUserPresence(userId, presence);
//         }
//         return presence;
//       }),
//     );
//   } else {
//     // No cache, just stream fresh data
//     return PresenceService.instance.getUserPresenceStream(userId).asyncMap((presence) async {
//       if (presence != null) {
//         await CacheService.instance.cacheUserPresence(userId, presence);
//       }
//       return presence;
//     });
//   }
// });

// /// Provider for user status with caching
// final cachedUserStatusProvider = Provider.family<String, UserModel?>((ref, user) {
//   if (user == null) return 'Unknown';
  
//   // Use cached presence data for status calculation
//   final cachedPresence = CacheService.instance.getCachedUserPresence(user.uid);
  
//   if (cachedPresence != null) {
//     final isOnline = cachedPresence['online'] as bool? ?? false;
//     final lastSeenTimestamp = cachedPresence['lastSeen'] as int?;
    
//     // Create temporary user with cached presence for status calculation
//     final userWithPresence = user.copyWith(
//       isOnline: isOnline,
//       realtimeLastSeen: lastSeenTimestamp != null 
//           ? DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp)
//           : null,
//     );
    
//     return userWithPresence.chatStatusText;
//   }
  
//   // Fallback to user's built-in status
//   return user.chatStatusText;
// });

// /// Force refresh all user data
// final refreshAllUsersProvider = Provider<Future<void>>((ref) async {
//   final currentUserController = ref.read(cachedCurrentUserProvider.notifier);
//   final partnerUserController = ref.read(cachedPartnerUserProvider.notifier);
  
//   await Future.wait([
//     currentUserController.forceRefresh(),
//     partnerUserController.forceRefresh(),
//   ]);
// });

// // Backward compatibility - these providers now use caching internally
// final realTimeCurrentUserProvider = optimizedCurrentUserProvider;
// final realTimePartnerUserProvider = optimizedPartnerUserProvider;