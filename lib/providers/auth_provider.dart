import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onlyus/core/services/firebase_service.dart';

import '../core/services/auth_service.dart';
import '../core/services/notification_service.dart';
import '../models/user_model.dart';
import 'user_provider.dart';

// Auth state provider - listens to Firebase Auth state changes
final authStateProvider = StreamProvider<User?>((ref) {
  return AuthService.instance.authStateChanges;
});

// Current user provider - provides the current UserModel
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (user) async {
      if (user == null) return null;

      // Get user data from Firestore
      final userModel = await ref.read(userProvider(user.uid).future);
      return userModel;
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// Auth controller provider
final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref),
);

// Auth state classes
abstract class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthSuccess extends AuthState {
  final UserModel user;
  const AuthSuccess(this.user);
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

// Auth controller
class AuthController extends StateNotifier<AuthState> {
  final Ref _ref;
  final AuthService _authService = AuthService.instance;

  AuthController(this._ref) : super(const AuthInitial()) {
    _initialize();
  }

  // Initialize auth state
  void _initialize() {
    _ref.listen(authStateProvider, (previous, next) {
      next.when(
        data: (user) async {
          if (user != null) {
            try {
              // Get user model from Firestore
              final userModel = await _ref.read(userProvider(user.uid).future);
              if (userModel != null) {
                state = AuthSuccess(userModel);

                // Set up OneSignal external user ID
                await NotificationService.setExternalUserId(user.uid);
                await NotificationService.updateUserPlayerId();
              }
            } catch (e) {
              state = AuthError('Failed to load user data: $e');
            }
          } else {
            state = const AuthInitial();

            // Remove OneSignal external user ID on logout
            // Remove OneSignal external user ID on logout
            await NotificationService.removeExternalUserId();
          }
        },
        loading: () => state = const AuthLoading(),
        error: (error, stackTrace) => state = AuthError('Auth error: $error'),
      );
    });
  }

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      state = const AuthLoading();

      final userCredential = await _authService.signInWithGoogle();

      if (userCredential == null) {
        // User cancelled sign-in
        state = const AuthInitial();
        return;
      }

      // The auth state listener will handle updating the state
      // when Firebase Auth state changes
    } catch (e) {
      state = AuthError('Sign in failed: ${e.toString()}');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      state = const AuthLoading();
      await _authService.signOut();
      // Auth state listener will handle the state update
    } catch (e) {
      state = AuthError('Sign out failed: ${e.toString()}');
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      state = const AuthLoading();
      await _authService.deleteAccount();
      // Auth state listener will handle the state update
    } catch (e) {
      state = AuthError('Account deletion failed: ${e.toString()}');
    }
  }

  // Update profile
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    try {
      await _authService.updateProfile(
        displayName: displayName,
        photoURL: photoURL,
      );

      // Refresh current user data
      final currentUser = _authService.currentUser;
      if (currentUser != null) {
        final userModel = await _ref.read(userProvider(currentUser.uid).future);
        if (userModel != null) {
          state = AuthSuccess(userModel);
        }
      }
    } catch (e) {
      state = AuthError('Profile update failed: ${e.toString()}');
    }
  }

  Future<void> updateUserPrivacySettings({
    bool? showOnlineStatus,
    bool? showLastSeen,
  }) async {
    try {
      final currentUser = FirebaseService.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final updates = <String, dynamic>{};

      if (showOnlineStatus != null) {
        updates['privacySettings.showOnlineStatus'] = showOnlineStatus;
      }

      if (showLastSeen != null) {
        updates['privacySettings.showLastSeen'] = showLastSeen;
      }

      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();

        await FirebaseService.usersCollection
            .doc(currentUser.uid)
            .update(updates);

        print('✅ Privacy settings updated successfully');
      }
    } catch (e) {
      print('❌ Error updating privacy settings: $e');
      rethrow;
    }
  }

  // Add method to check if user's online status should be visible
  Future<bool> shouldShowOnlineStatus(String userId) async {
    try {
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final privacySettings =
            userData['privacySettings'] as Map<String, dynamic>?;

        return privacySettings?['showOnlineStatus'] ?? true; // Default to true
      }

      return true;
    } catch (e) {
      print('❌ Error checking online status visibility: $e');
      return true;
    }
  }

  // Add method to check if user's last seen should be visible
  Future<bool> shouldShowLastSeen(String userId) async {
    try {
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final privacySettings =
            userData['privacySettings'] as Map<String, dynamic>?;

        return privacySettings?['showLastSeen'] ?? true; // Default to true
      }

      return true;
    } catch (e) {
      print('❌ Error checking last seen visibility: $e');
      return true;
    }
  }

  // Check if user is authenticated
  bool get isAuthenticated => _authService.isSignedIn;

  // Get current user ID
  String? get currentUserId => _authService.currentUserId;

  // Get current user
  User? get currentFirebaseUser => _authService.currentUser;
}
