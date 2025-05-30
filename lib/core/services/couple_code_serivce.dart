import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onlyus/core/services/firebase_service.dart';

class CoupleCodeService {
  // Singleton instance
  static CoupleCodeService? _instance;
  static CoupleCodeService get instance => _instance ??= CoupleCodeService._();
  CoupleCodeService._();

  // Code configuration
  static const int _codeLength = 6;
  static const String _codeChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static const Duration _codeExpiration = Duration(days: 7);

  // Generate a random couple code
  static String _generateRandomCode() {
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        _codeLength,
        (_) => _codeChars.codeUnitAt(random.nextInt(_codeChars.length)),
      ),
    );
  }

  // Check if code already exists
  Future<bool> _codeExists(String code) async {
    try {
      final doc = await FirebaseService.firestore
          .collection('coupleCodes')
          .doc(code)
          .get();
      return doc.exists;
    } catch (e) {
      print('❌ Error checking code existence: $e');
      return true; // Assume exists to be safe
    }
  }

  // Generate unique couple code
  Future<String> generateUniqueCoupleCode() async {
    String code;
    bool exists;
    int attempts = 0;
    const maxAttempts = 10;

    do {
      code = _generateRandomCode();
      exists = await _codeExists(code);
      attempts++;
      
      if (attempts >= maxAttempts) {
        throw Exception('Failed to generate unique code after $maxAttempts attempts');
      }
    } while (exists);

    return code;
  }

  // Create and save couple code for user
  Future<String> createCoupleCodeForUser(String userId) async {
    try {
      final code = await generateUniqueCoupleCode();
      
      // Save code document
      await FirebaseService.firestore
          .collection('coupleCodes')
          .doc(code)
          .set({
        'code': code,
        'creatorId': userId,
        'isUsed': false,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': FieldValue.serverTimestamp(), // Will be updated with expiration
        'usedAt': null,
        'usedBy': null,
      });

      // Update user document with couple code
      await FirebaseService.usersCollection.doc(userId).update({
        'coupleCode': code,
        'codeCreatedAt': FieldValue.serverTimestamp(),
        'isConnected': false,
        'partnerId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Couple code created: $code for user: $userId');
      return code;
    } catch (e) {
      print('❌ Error creating couple code: $e');
      rethrow;
    }
  }

  // Validate and use couple code
  Future<CoupleCodeResult> useCoupleCode(String code, String userId) async {
    try {
      final codeDoc = await FirebaseService.firestore
          .collection('coupleCodes')
          .doc(code.toUpperCase())
          .get();

      if (!codeDoc.exists) {
        return CoupleCodeResult.invalid('Code does not exist');
      }

      final codeData = codeDoc.data()!;
      
      // Check if code is already used
      if (codeData['isUsed'] == true) {
        return CoupleCodeResult.invalid('Code has already been used');
      }

      // Check if code is expired
      final createdAt = (codeData['createdAt'] as Timestamp).toDate();
      if (DateTime.now().difference(createdAt) > _codeExpiration) {
        return CoupleCodeResult.invalid('Code has expired');
      }

      final creatorId = codeData['creatorId'] as String;
      
      // Check if user is trying to use their own code
      if (creatorId == userId) {
        return CoupleCodeResult.invalid('You cannot use your own code');
      }

      // Check if creator is already connected
      final creatorDoc = await FirebaseService.usersCollection.doc(creatorId).get();
      final creatorData = creatorDoc.data()!;
      
      if (creatorData['isConnected'] == true) {
        return CoupleCodeResult.invalid('Code creator is already connected');
      }

      // Check if current user is already connected
      final currentUserDoc = await FirebaseService.usersCollection.doc(userId).get();
      final currentUserData = currentUserDoc.data()!;
      
      if (currentUserData['isConnected'] == true) {
        return CoupleCodeResult.invalid('You are already connected to someone');
      }

      // All validations passed - create connection
      await _createConnection(code, creatorId, userId);
      
      return CoupleCodeResult.success(creatorId, 'Successfully connected!');
    } catch (e) {
      print('❌ Error using couple code: $e');
      return CoupleCodeResult.error('An error occurred while connecting');
    }
  }

  // Create connection between two users
  // In couple_code_service.dart, update the _createConnection method:
Future<void> _createConnection(String code, String creatorId, String userId) async {
  try {
    final batch = FirebaseService.firestore.batch();

    // Get both user documents first to get their names
    final creatorDoc = await FirebaseService.usersCollection.doc(creatorId).get();
    final userDoc = await FirebaseService.usersCollection.doc(userId).get();
    
    final creatorData = creatorDoc.data() as Map<String, dynamic>;
    final userData = userDoc.data() as Map<String, dynamic>;

    // Mark code as used
    final codeRef = FirebaseService.firestore.collection('coupleCodes').doc(code);
    batch.update(codeRef, {
      'isUsed': true,
      'usedAt': FieldValue.serverTimestamp(),
      'usedBy': userId,
    });

    // Update creator user with partner info
    final creatorRef = FirebaseService.usersCollection.doc(creatorId);
    batch.update(creatorRef, {
      'isConnected': true,
      'partnerId': userId,
      'partnerName': userData['displayName'] ?? 'Unknown',
      'connectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update current user with partner info
    final userRef = FirebaseService.usersCollection.doc(userId);
    batch.update(userRef, {
      'isConnected': true,
      'partnerId': creatorId,
      'partnerName': creatorData['displayName'] ?? 'Unknown',
      'connectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Commit the batch first to ensure users are connected
    await batch.commit();
    print('✅ User documents updated with connection info');

    // Then create or update chat room
    final chatId = await FirebaseService.getOrCreateChatRoom(creatorId);
    
    // Update chat with couple code reference
    await FirebaseService.chatsCollection.doc(chatId).update({
      'coupleCode': code,
      'connectedViaCode': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    print('✅ Connection created successfully between $creatorId and $userId');
  } catch (e) {
    print('❌ Error creating connection: $e');
    rethrow;
  }
}
  // Get user's couple code
  Future<String?> getUserCoupleCode(String userId) async {
    try {
      final doc = await FirebaseService.usersCollection.doc(userId).get();
      if (doc.exists) {
        final data = doc.data();
        return data?['coupleCode'] as String?;
      }
      return null;
    } catch (e) {
      print('❌ Error getting user couple code: $e');
      return null;
    }
  }

  // Check if user is connected
  Future<bool> isUserConnected(String userId) async {
    try {
      final doc = await FirebaseService.usersCollection.doc(userId).get();
      if (doc.exists) {
        final data = doc.data();
        return data?['isConnected'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      print('❌ Error checking user connection status: $e');
      return false;
    }
  }

  // Get partner ID
  Future<String?> getPartnerId(String userId) async {
    try {
      final doc = await FirebaseService.usersCollection.doc(userId).get();
      if (doc.exists) {
        final data = doc.data();
        return data?['partnerId'] as String?;
      }
      return null;
    } catch (e) {
      print('❌ Error getting partner ID: $e');
      return null;
    }
  }

  // Regenerate couple code (if current one is compromised)
  Future<String> regenerateCoupleCode(String userId) async {
    try {
      // Get current code
      final currentCode = await getUserCoupleCode(userId);
      
      // Mark current code as expired if it exists
      if (currentCode != null) {
        await FirebaseService.firestore
            .collection('coupleCodes')
            .doc(currentCode)
            .update({
          'isExpired': true,
          'expiredAt': FieldValue.serverTimestamp(),
        });
      }

      // Generate new code
      final newCode = await createCoupleCodeForUser(userId);
      return newCode;
    } catch (e) {
      print('❌ Error regenerating couple code: $e');
      rethrow;
    }
  }

  // Format code for display (add dashes)
  static String formatCodeForDisplay(String code) {
    if (code.length != _codeLength) return code;
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  // Remove formatting from code
  static String cleanCode(String code) {
    return code.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
  }

  // Validate code format
  static bool isValidCodeFormat(String code) {
    final cleanedCode = cleanCode(code);
    return cleanedCode.length == _codeLength &&
           RegExp(r'^[A-Z0-9]+$').hasMatch(cleanedCode);
  }

  // Get code expiration date
  Future<DateTime?> getCodeExpirationDate(String code) async {
    try {
      final doc = await FirebaseService.firestore
          .collection('coupleCodes')
          .doc(code)
          .get();
      
      if (doc.exists) {
        final createdAt = (doc.data()!['createdAt'] as Timestamp).toDate();
        return createdAt.add(_codeExpiration);
      }
      return null;
    } catch (e) {
      print('❌ Error getting code expiration: $e');
      return null;
    }
  }

  // Clean up expired codes (maintenance function)
  Future<void> cleanupExpiredCodes() async {
    try {
      final cutoffDate = DateTime.now().subtract(_codeExpiration);
      
      final expiredCodes = await FirebaseService.firestore
          .collection('coupleCodes')
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .where('isUsed', isEqualTo: false)
          .get();

      final batch = FirebaseService.firestore.batch();
      
      for (final doc in expiredCodes.docs) {
        batch.update(doc.reference, {
          'isExpired': true,
          'expiredAt': FieldValue.serverTimestamp(),
        });
      }
      
      if (expiredCodes.docs.isNotEmpty) {
        await batch.commit();
        print('✅ Cleaned up ${expiredCodes.docs.length} expired codes');
      }
    } catch (e) {
      print('❌ Error cleaning up expired codes: $e');
    }
  }
}

// Result class for couple code operations
class CoupleCodeResult {
  final bool isSuccess;
  final String message;
  final String? partnerId;

  CoupleCodeResult._(this.isSuccess, this.message, this.partnerId);

  factory CoupleCodeResult.success(String partnerId, String message) {
    return CoupleCodeResult._(true, message, partnerId);
  }

  factory CoupleCodeResult.invalid(String message) {
    return CoupleCodeResult._(false, message, null);
  }

  factory CoupleCodeResult.error(String message) {
    return CoupleCodeResult._(false, message, null);
  }
}