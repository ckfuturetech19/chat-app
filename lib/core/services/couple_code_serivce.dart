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

  // Enhanced code existence check with debugging
  Future<bool> _codeExists(String code) async {
    try {
      print('🔍 Checking if code exists: $code');

      final doc =
          await FirebaseService.firestore
              .collection('coupleCodes')
              .doc(code)
              .get();

      final exists = doc.exists;
      print('📋 Code exists result: $exists');

      if (exists) {
        final data = doc.data();
        print('📋 Code data: $data');
      }

      return exists;
    } catch (e) {
      print('❌ Error checking code existence: $e');
      return true; // Assume exists to be safe
    }
  }

  // Debug method to search for codes with pattern matching
  Future<List<Map<String, dynamic>>> searchCodesWithPattern(
    String pattern,
  ) async {
    try {
      print('🔍 Searching for codes with pattern: $pattern');

      // Search for codes that might match
      final querySnapshot =
          await FirebaseService.firestore
              .collection('coupleCodes')
              .where('isUsed', isEqualTo: false)
              .limit(50)
              .get();

      final matchingCodes = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final codeId = doc.id;
        final codeValue = data['code'] as String?;

        // Check if the code ID or code value matches the pattern
        if (codeId.toLowerCase().contains(pattern.toLowerCase()) ||
            (codeValue != null &&
                codeValue.toLowerCase().contains(pattern.toLowerCase()))) {
          matchingCodes.add({'docId': codeId, 'data': data});
        }
      }

      print('📋 Found ${matchingCodes.length} matching codes');
      for (final match in matchingCodes) {
        print('📋 Match: ${match['docId']} -> ${match['data']}');
      }

      return matchingCodes;
    } catch (e) {
      print('❌ Error searching codes: $e');
      return [];
    }
  }

  // Debug method to list all available codes
  Future<List<Map<String, dynamic>>> listAllAvailableCodes() async {
    try {
      print('🔍 Listing all available codes...');

      final querySnapshot =
          await FirebaseService.firestore
              .collection('coupleCodes')
              .where('isUsed', isEqualTo: false)
              .limit(20)
              .get();

      final codes = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        codes.add({
          'docId': doc.id,
          'code': data['code'],
          'creatorId': data['creatorId'],
          'createdAt': data['createdAt'],
          'isUsed': data['isUsed'],
        });
      }

      print('📋 Found ${codes.length} available codes:');
      for (final code in codes) {
        print(
          '📋 Code: ${code['docId']} (${code['code']}) - Creator: ${code['creatorId']}',
        );
      }

      return codes;
    } catch (e) {
      print('❌ Error listing codes: $e');
      return [];
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
        throw Exception(
          'Failed to generate unique code after $maxAttempts attempts',
        );
      }
    } while (exists);

    return code;
  }

  // Enhanced create couple code with better logging
  Future<String> createCoupleCodeForUser(String userId) async {
    try {
      print('🔍 Creating couple code for user: $userId');

      final code = await generateUniqueCoupleCode();
      print('📋 Generated code: $code');

      // Save code document
      await FirebaseService.firestore.collection('coupleCodes').doc(code).set({
        'code': code,
        'creatorId': userId,
        'isUsed': false,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': FieldValue.serverTimestamp(),
        'usedAt': null,
        'usedBy': null,
      });

      print('✅ Code document created in Firestore');

      // Update user document with couple code
      await FirebaseService.usersCollection.doc(userId).update({
        'coupleCode': code,
        'codeCreatedAt': FieldValue.serverTimestamp(),
        'isConnected': false,
        'partnerId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ User document updated with code');

      // Verify the code was created successfully
      final verificationDoc =
          await FirebaseService.firestore
              .collection('coupleCodes')
              .doc(code)
              .get();

      if (verificationDoc.exists) {
        print('✅ Code creation verified: $code');
      } else {
        print('❌ Code creation verification failed');
      }

      print('✅ Couple code created: $code for user: $userId');
      return code;
    } catch (e) {
      print('❌ Error creating couple code: $e');
      rethrow;
    }
  }

  // Enhanced validate and use couple code with extensive debugging
  Future<CoupleCodeResult> useCoupleCode(String code, String userId) async {
    try {
      print('🔍 Starting code validation for code: $code, user: $userId');

      // Clean and format the code
      final cleanedCode = cleanCode(code);
      print('📋 Cleaned code: $cleanedCode');

      // First, try to find the code with the cleaned version
      var codeDoc =
          await FirebaseService.firestore
              .collection('coupleCodes')
              .doc(cleanedCode)
              .get();

      // If not found, try with original code
      if (!codeDoc.exists) {
        print('⚠️ Code not found with cleaned version, trying original...');
        codeDoc =
            await FirebaseService.firestore
                .collection('coupleCodes')
                .doc(code.toUpperCase())
                .get();
      }

      // If still not found, try lowercase
      if (!codeDoc.exists) {
        print('⚠️ Code not found with uppercase, trying lowercase...');
        codeDoc =
            await FirebaseService.firestore
                .collection('coupleCodes')
                .doc(code.toLowerCase())
                .get();
      }

      // If still not found, search for similar codes
      if (!codeDoc.exists) {
        print(
          '⚠️ Code not found with any variation, searching for similar codes...',
        );

        // Search for codes with pattern matching
        final similarCodes = await searchCodesWithPattern(cleanedCode);

        if (similarCodes.isNotEmpty) {
          print('📋 Found similar codes, but none match exactly');
          for (final similar in similarCodes) {
            print('📋 Similar: ${similar['docId']}');
          }
        }

        // List all available codes for debugging
        await listAllAvailableCodes();

        print(
          '❌ Code does not exist: $cleanedCode (tried multiple variations)',
        );
        return CoupleCodeResult.invalid(
          'Code does not exist. Please check the code and try again.',
        );
      }

      print('✅ Code document found!');
      final codeData = codeDoc.data()!;
      print('📋 Code data: $codeData');

      // Check if code is already used
      if (codeData['isUsed'] == true) {
        print('❌ Code already used: $cleanedCode');
        return CoupleCodeResult.invalid('Code has already been used');
      }

      // Check if code is expired
      final createdAt = (codeData['createdAt'] as Timestamp).toDate();
      final now = DateTime.now();
      final age = now.difference(createdAt);

      print('📋 Code age: ${age.inDays} days, ${age.inHours % 24} hours');

      if (age > _codeExpiration) {
        print('❌ Code expired: $cleanedCode');
        return CoupleCodeResult.invalid('Code has expired');
      }

      final creatorId = codeData['creatorId'] as String;
      print('📋 Code creator: $creatorId');

      // Check if user is trying to use their own code
      if (creatorId == userId) {
        print('❌ User trying to use own code');
        return CoupleCodeResult.invalid('You cannot use your own code');
      }

      // Check if creator is already connected
      final creatorDoc =
          await FirebaseService.usersCollection.doc(creatorId).get();
      if (!creatorDoc.exists) {
        print('❌ Creator user document not found');
        return CoupleCodeResult.invalid('Code creator not found');
      }

      final creatorData = creatorDoc.data()!;
      print('📋 Creator data: ${creatorData.keys}');

      if (creatorData['isConnected'] == true) {
        print('❌ Creator already connected');
        return CoupleCodeResult.invalid('Code creator is already connected');
      }

      // Check if current user is already connected
      final currentUserDoc =
          await FirebaseService.usersCollection.doc(userId).get();
      if (!currentUserDoc.exists) {
        print('❌ Current user document not found');
        return CoupleCodeResult.invalid('User not found');
      }

      final currentUserData = currentUserDoc.data()!;
      print('📋 Current user data: ${currentUserData.keys}');

      if (currentUserData['isConnected'] == true) {
        print('❌ Current user already connected');
        return CoupleCodeResult.invalid('You are already connected to someone');
      }

      print('✅ All validations passed - creating connection');

      // All validations passed - create connection
      await _createConnection(cleanedCode, creatorId, userId);

      print('✅ Connection created successfully');
      return CoupleCodeResult.success(creatorId, 'Successfully connected!');
    } catch (e) {
      print('❌ Error using couple code: $e');
      return CoupleCodeResult.error('An error occurred while connecting: $e');
    }
  }

  // Enhanced connection creation (keeping existing logic but with better logging)
  Future<void> _createConnection(
    String code,
    String creatorId,
    String userId,
  ) async {
    try {
      print('🔍 Creating connection between $creatorId and $userId');

      // Get both user documents first to get their names
      final creatorDoc =
          await FirebaseService.usersCollection.doc(creatorId).get();
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();

      if (!creatorDoc.exists || !userDoc.exists) {
        throw Exception('One or both user documents not found');
      }

      final creatorData = creatorDoc.data() as Map<String, dynamic>;
      final userData = userDoc.data() as Map<String, dynamic>;

      print(
        '📋 Creator: ${creatorData['displayName']}, User: ${userData['displayName']}',
      );

      // Use batch write for atomic operation
      final batch = FirebaseService.firestore.batch();

      // Mark code as used
      final codeRef = FirebaseService.firestore
          .collection('coupleCodes')
          .doc(code);
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

      // Add a small delay to ensure Firestore propagation
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify the connection was created successfully
      await _verifyConnection(creatorId, userId);

      // In your existing _createConnection method, add this before the final print:

      // Store connection history for future recovery
      await _storeConnectionHistory(
        code,
        creatorId,
        userId,
        creatorData,
        userData,
      );

      // Create or update chat room after verification
      await _initializeChatRoom(code, creatorId, userId);

      print('✅ Connection created successfully between $creatorId and $userId');
    } catch (e) {
      print('❌ Error creating connection: $e');

      // Attempt cleanup on failure
      try {
        await _cleanupFailedConnection(code, creatorId, userId);
      } catch (cleanupError) {
        print('❌ Error during cleanup: $cleanupError');
      }

      rethrow;
    }
  }

  // Verify that the connection was created successfully
  Future<void> _verifyConnection(String creatorId, String userId) async {
    try {
      print('🔍 Verifying connection between $creatorId and $userId');

      final creatorDoc =
          await FirebaseService.usersCollection.doc(creatorId).get();
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();

      if (!creatorDoc.exists || !userDoc.exists) {
        throw Exception('User documents not found during verification');
      }

      final creatorData = creatorDoc.data() as Map<String, dynamic>;
      final userData = userDoc.data() as Map<String, dynamic>;

      final creatorConnected = creatorData['isConnected'] as bool? ?? false;
      final userConnected = userData['isConnected'] as bool? ?? false;
      final creatorPartnerId = creatorData['partnerId'] as String?;
      final userPartnerId = userData['partnerId'] as String?;

      if (!creatorConnected ||
          !userConnected ||
          creatorPartnerId != userId ||
          userPartnerId != creatorId) {
        throw Exception('Connection verification failed - data mismatch');
      }

      print('✅ Connection verified successfully');
    } catch (e) {
      print('❌ Connection verification failed: $e');
      throw Exception('Connection verification failed: $e');
    }
  }

  // Initialize chat room after successful connection
  Future<void> _initializeChatRoom(
    String code,
    String creatorId,
    String userId,
  ) async {
    try {
      print('🔍 Initializing chat room for $creatorId and $userId');

      // Create chat room using Firebase service
      final chatId = await FirebaseService.getOrCreateChatRoom(userId);

      // Update chat with couple code reference
      await FirebaseService.chatsCollection.doc(chatId).update({
        'coupleCode': code,
        'connectedViaCode': true,
        'connectionTimestamp': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Chat room initialized: $chatId');
    } catch (e) {
      print('❌ Error initializing chat room: $e');
      // Don't rethrow - connection is still valid even if chat setup fails
    }
  }

  // Cleanup failed connection attempt
  Future<void> _cleanupFailedConnection(
    String code,
    String creatorId,
    String userId,
  ) async {
    try {
      print('🧹 Cleaning up failed connection attempt');

      final batch = FirebaseService.firestore.batch();

      // Revert code status
      final codeRef = FirebaseService.firestore
          .collection('coupleCodes')
          .doc(code);
      batch.update(codeRef, {'isUsed': false, 'usedAt': null, 'usedBy': null});

      // Revert creator user
      final creatorRef = FirebaseService.usersCollection.doc(creatorId);
      batch.update(creatorRef, {
        'isConnected': false,
        'partnerId': null,
        'partnerName': null,
        'connectedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Revert current user
      final userRef = FirebaseService.usersCollection.doc(userId);
      batch.update(userRef, {
        'isConnected': false,
        'partnerId': null,
        'partnerName': null,
        'connectedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      print('✅ Cleanup completed');
    } catch (e) {
      print('❌ Error during cleanup: $e');
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

  // Enhanced remove formatting from code
  static String cleanCode(String code) {
    return code.replaceAll('-', '').replaceAll(' ', '').toUpperCase().trim();
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
      final doc =
          await FirebaseService.firestore
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

      final expiredCodes =
          await FirebaseService.firestore
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

  // Get connection status for debugging
  Future<Map<String, dynamic>> getConnectionStatus(String userId) async {
    try {
      final userDoc = await FirebaseService.usersCollection.doc(userId).get();
      if (!userDoc.exists) {
        return {'exists': false};
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      return {
        'exists': true,
        'isConnected': userData['isConnected'] ?? false,
        'partnerId': userData['partnerId'],
        'partnerName': userData['partnerName'],
        'connectedAt': userData['connectedAt'],
        'coupleCode': userData['coupleCode'],
      };
    } catch (e) {
      print('❌ Error getting connection status: $e');
      return {'error': e.toString()};
    }
  }

  // Add these methods to your existing CoupleCodeService class

  // Store connection history when users connect
  Future<void> _storeConnectionHistory(
    String code,
    String userId1,
    String userId2,
    Map<String, dynamic> user1Data,
    Map<String, dynamic> user2Data,
  ) async {
    try {
      print('🔍 Storing connection history for code: $code');

      final connectionId = '${code}_${DateTime.now().millisecondsSinceEpoch}';

      // Store connection history for both users
      final batch = FirebaseService.firestore.batch();

      // User 1's connection history
      final user1HistoryRef = FirebaseService.firestore
          .collection('connectionHistory')
          .doc('${user1Data['email']}_$connectionId');

      batch.set(user1HistoryRef, {
        'id': connectionId,
        'coupleCode': code,
        'userEmail': user1Data['email'],
        'userId': userId1,
        'userName': user1Data['displayName'],
        'userPhoto': user1Data['photoURL'],
        'partnerEmail': user2Data['email'],
        'partnerId': userId2,
        'partnerName': user2Data['displayName'],
        'partnerPhoto': user2Data['photoURL'],
        'connectedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'chatId': _generateChatId(userId1, userId2),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // User 2's connection history
      final user2HistoryRef = FirebaseService.firestore
          .collection('connectionHistory')
          .doc('${user2Data['email']}_$connectionId');

      batch.set(user2HistoryRef, {
        'id': connectionId,
        'coupleCode': code,
        'userEmail': user2Data['email'],
        'userId': userId2,
        'userName': user2Data['displayName'],
        'userPhoto': user2Data['photoURL'],
        'partnerEmail': user1Data['email'],
        'partnerId': userId1,
        'partnerName': user1Data['displayName'],
        'partnerPhoto': user1Data['photoURL'],
        'connectedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'chatId': _generateChatId(userId1, userId2),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      print('✅ Connection history stored successfully');
    } catch (e) {
      print('❌ Error storing connection history: $e');
      // Don't throw - this is not critical for the connection
    }
  }

  // Get connection history for user by email
  Future<List<Map<String, dynamic>>> getConnectionHistoryByEmail(
    String email,
  ) async {
    try {
      print('🔍 Getting connection history for email: $email');

      final historyDocs =
          await FirebaseService.firestore
              .collection('connectionHistory')
              .where('userEmail', isEqualTo: email)
              .orderBy('connectedAt', descending: true)
              .get();

      final connectionHistory = <Map<String, dynamic>>[];

      for (final doc in historyDocs.docs) {
        final data = doc.data();

        // Check if this connection still exists (partner not deleted)
        final partnerId = data['partnerId'] as String?;
        bool partnerExists = false;

        if (partnerId != null) {
          try {
            final partnerDoc =
                await FirebaseService.usersCollection.doc(partnerId).get();
            partnerExists = partnerDoc.exists;
          } catch (e) {
            partnerExists = false;
          }
        }

        connectionHistory.add({
          ...data,
          'docId': doc.id,
          'partnerStillExists': partnerExists,
          'canReconnect': partnerExists && data['isActive'] == true,
        });
      }

      print('📋 Found ${connectionHistory.length} connection records');
      return connectionHistory;
    } catch (e) {
      print('❌ Error getting connection history: $e');
      return [];
    }
  }

  // Delete connection history record
  Future<void> deleteConnectionHistory(
    String email,
    String connectionId,
  ) async {
    try {
      final docId = '${email}_$connectionId';
      await FirebaseService.firestore
          .collection('connectionHistory')
          .doc(docId)
          .update({
            'isActive': false,
            'deletedAt': FieldValue.serverTimestamp(),
          });

      print('✅ Connection history deleted: $docId');
    } catch (e) {
      print('❌ Error deleting connection history: $e');
      rethrow;
    }
  }

  // Request reconnection using old couple code
  Future<CoupleCodeResult> requestReconnection(
    String email,
    String connectionId,
    String currentUserId,
  ) async {
    try {
      print(
        '🔍 Requesting reconnection for: $email, connection: $connectionId',
      );

      // Get the connection history record
      final docId = '${email}_$connectionId';
      final historyDoc =
          await FirebaseService.firestore
              .collection('connectionHistory')
              .doc(docId)
              .get();

      if (!historyDoc.exists) {
        return CoupleCodeResult.invalid('Connection history not found');
      }

      final historyData = historyDoc.data() as Map<String, dynamic>;
      final partnerId = historyData['partnerId'] as String;
      final coupleCode = historyData['coupleCode'] as String;

      // Check if partner still exists
      final partnerDoc =
          await FirebaseService.usersCollection.doc(partnerId).get();
      if (!partnerDoc.exists) {
        return CoupleCodeResult.invalid(
          'Your partner\'s account no longer exists',
        );
      }

      final partnerData = partnerDoc.data() as Map<String, dynamic>;

      // Check if partner is already connected to someone else
      if (partnerData['isConnected'] == true) {
        final currentPartnerId = partnerData['partnerId'] as String?;
        if (currentPartnerId != null && currentPartnerId != currentUserId) {
          return CoupleCodeResult.invalid(
            'Your partner is already connected to someone else',
          );
        }
      }

      // Create reconnection request
      await _createReconnectionRequest(
        currentUserId,
        partnerId,
        coupleCode,
        connectionId,
        historyData,
      );

      return CoupleCodeResult.success(
        partnerId,
        'Reconnection request sent to ${historyData['partnerName']}',
      );
    } catch (e) {
      print('❌ Error requesting reconnection: $e');
      return CoupleCodeResult.error('Failed to request reconnection: $e');
    }
  }

  // Create reconnection request
  Future<void> _createReconnectionRequest(
    String requesterId,
    String partnerId,
    String coupleCode,
    String connectionId,
    Map<String, dynamic> historyData,
  ) async {
    try {
      final requestId =
          '${requesterId}_${partnerId}_${DateTime.now().millisecondsSinceEpoch}';

      await FirebaseService.firestore
          .collection('reconnectionRequests')
          .doc(requestId)
          .set({
            'id': requestId,
            'requesterId': requesterId,
            'partnerId': partnerId,
            'coupleCode': coupleCode,
            'connectionId': connectionId,
            'historyData': historyData,
            'status': 'pending', // pending, accepted, rejected
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 7)),
            ),
          });

      print('✅ Reconnection request created: $requestId');
    } catch (e) {
      print('❌ Error creating reconnection request: $e');
      rethrow;
    }
  }

  // Accept reconnection request
  Future<CoupleCodeResult> acceptReconnectionRequest(String requestId) async {
    try {
      final requestDoc =
          await FirebaseService.firestore
              .collection('reconnectionRequests')
              .doc(requestId)
              .get();

      if (!requestDoc.exists) {
        return CoupleCodeResult.invalid('Reconnection request not found');
      }

      final requestData = requestDoc.data() as Map<String, dynamic>;

      // Check if request is still valid
      if (requestData['status'] != 'pending') {
        return CoupleCodeResult.invalid(
          'This request has already been processed',
        );
      }

      final requesterId = requestData['requesterId'] as String;
      final partnerId = requestData['partnerId'] as String;
      final coupleCode = requestData['coupleCode'] as String;

      // Reconnect the users with their original chat history
      await _reconnectUsersWithHistory(
        requesterId,
        partnerId,
        coupleCode,
        requestData,
      );

      // Update request status
      await FirebaseService.firestore
          .collection('reconnectionRequests')
          .doc(requestId)
          .update({
            'status': 'accepted',
            'acceptedAt': FieldValue.serverTimestamp(),
          });

      return CoupleCodeResult.success(requesterId, 'Reconnected successfully!');
    } catch (e) {
      print('❌ Error accepting reconnection: $e');
      return CoupleCodeResult.error('Failed to accept reconnection: $e');
    }
  }

  // Reconnect users with their chat history
  Future<void> _reconnectUsersWithHistory(
    String userId1,
    String userId2,
    String coupleCode,
    Map<String, dynamic> requestData,
  ) async {
    try {
      print('🔄 Reconnecting users with history');

      // Get user data
      final user1Doc = await FirebaseService.usersCollection.doc(userId1).get();
      final user2Doc = await FirebaseService.usersCollection.doc(userId2).get();

      if (!user1Doc.exists || !user2Doc.exists) {
        throw Exception('One or both users not found');
      }

      final user1Data = user1Doc.data() as Map<String, dynamic>;
      final user2Data = user2Doc.data() as Map<String, dynamic>;

      final batch = FirebaseService.firestore.batch();

      // Update both users with connection info
      batch.update(FirebaseService.usersCollection.doc(userId1), {
        'isConnected': true,
        'partnerId': userId2,
        'partnerName': user2Data['displayName'],
        'coupleCode': coupleCode,
        'reconnectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(FirebaseService.usersCollection.doc(userId2), {
        'isConnected': true,
        'partnerId': userId1,
        'partnerName': user1Data['displayName'],
        'coupleCode': coupleCode,
        'reconnectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Restore or create chat room
      final originalChatId = requestData['historyData']['chatId'] as String?;
      if (originalChatId != null) {
        // Try to restore original chat
        await _restoreOriginalChat(originalChatId, userId1, userId2, batch);
      } else {
        // Create new chat with same couple code
        final newChatId = await FirebaseService.getOrCreateChatRoom(userId2);
        batch.update(FirebaseService.chatsCollection.doc(newChatId), {
          'coupleCode': coupleCode,
          'reconnectedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print('✅ Users reconnected with history');
    } catch (e) {
      print('❌ Error reconnecting users: $e');
      rethrow;
    }
  }

  // Helper method to generate chat ID
  String _generateChatId(String userId1, String userId2) {
    final List<String> userIds = [userId1, userId2];
    userIds.sort();
    return '${userIds[0]}_${userIds[1]}';
  }

  // Restore original chat if it exists
  Future<void> _restoreOriginalChat(
    String chatId,
    String userId1,
    String userId2,
    WriteBatch batch,
  ) async {
    try {
      final chatDoc = await FirebaseService.chatsCollection.doc(chatId).get();

      if (chatDoc.exists) {
        // Chat still exists, just update it
        batch.update(FirebaseService.chatsCollection.doc(chatId), {
          'isActive': true,
          'reconnectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ Original chat restored: $chatId');
      } else {
        // Chat was deleted, create new one
        final newChatId = _generateChatId(userId1, userId2);
        batch.set(FirebaseService.chatsCollection.doc(newChatId), {
          'id': newChatId,
          'chatId': newChatId,
          'participants': [userId1, userId2],
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'restoredFrom': chatId,
        });
        print('✅ New chat created to replace deleted one: $newChatId');
      }
    } catch (e) {
      print('❌ Error restoring chat: $e');
      // Don't throw - connection is more important than chat restoration
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
