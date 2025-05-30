import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_service.dart';

class AuthService {
  // Singleton instance
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  
  // Get current user
  User? get currentUser => _auth.currentUser;
  
  // Get auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }
      
      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;
      
      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      // Sign in to Firebase with the Google credentials
      final UserCredential userCredential = 
          await _auth.signInWithCredential(credential);
      
      // Create or update user document in Firestore
      if (userCredential.user != null) {
        await FirebaseService.createOrUpdateUser(
          uid: userCredential.user!.uid,
          email: userCredential.user!.email!,
          displayName: userCredential.user!.displayName ?? 'Unknown',
          photoURL: userCredential.user!.photoURL,
        );
        
        // Update online status
        await FirebaseService.updateUserOnlineStatus(true);
      }
      
      print('✅ Google Sign-In successful');
      return userCredential;
      
    } catch (e) {
      print('❌ Google Sign-In error: $e');
      rethrow;
    }
  }
  
  // Sign out
  Future<void> signOut() async {
    try {
      // Update online status before signing out
      await FirebaseService.updateUserOnlineStatus(false);
      
      // Sign out from Google
      await _googleSignIn.signOut();
      
      // Sign out from Firebase
      await _auth.signOut();
      
      print('✅ Sign out successful');
    } catch (e) {
      print('❌ Sign out error: $e');
      rethrow;
    }
  }
  
  // Check if user is signed in
  bool get isSignedIn => currentUser != null;
  
  // Get current user ID
  String? get currentUserId => currentUser?.uid;
  
  // Get current user email
  String? get currentUserEmail => currentUser?.email;
  
  // Get current user display name
  String? get currentUserDisplayName => currentUser?.displayName;
  
  // Get current user photo URL
  String? get currentUserPhotoURL => currentUser?.photoURL;
  
  // Reauthenticate user (useful for sensitive operations)
  Future<UserCredential?> reauthenticateWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) return null;
      
      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;
      
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      final UserCredential userCredential = 
          await currentUser!.reauthenticateWithCredential(credential);
      
      print('✅ Reauthentication successful');
      return userCredential;
      
    } catch (e) {
      print('❌ Reauthentication error: $e');
      rethrow;
    }
  }
  
  // Delete user account
  Future<void> deleteAccount() async {
    try {
      if (currentUser == null) {
        throw Exception('No user signed in');
      }
      
      // Reauthenticate before deletion
      final reauthResult = await reauthenticateWithGoogle();
      if (reauthResult == null) {
        throw Exception('Reauthentication required for account deletion');
      }
      
      // Delete user document from Firestore
      await FirebaseService.usersCollection.doc(currentUserId).delete();
      
      // Delete user account
      await currentUser!.delete();
      
      // Sign out from Google
      await _googleSignIn.signOut();
      
      print('✅ Account deleted successfully');
    } catch (e) {
      print('❌ Account deletion error: $e');
      rethrow;
    }
  }
  
  // Update user profile
  Future<void> updateProfile({
    String? displayName,
    String? photoURL,
  }) async {
    try {
      if (currentUser == null) {
        throw Exception('No user signed in');
      }
      
      // Update Firebase Auth profile
      await currentUser!.updateDisplayName(displayName);
      await currentUser!.updatePhotoURL(photoURL);
      
      // Update Firestore user document
      await FirebaseService.createOrUpdateUser(
        uid: currentUser!.uid,
        email: currentUser!.email!,
        displayName: displayName ?? currentUser!.displayName ?? 'Unknown',
        photoURL: photoURL ?? currentUser!.photoURL,
      );
      
      print('✅ Profile updated successfully');
    } catch (e) {
      print('❌ Profile update error: $e');
      rethrow;
    }
  }
}