import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoURL;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? realtimeLastSeen; // From Realtime Database
  final String? partnerId;
  final String? oneSignalPlayerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // FIXED: Add privacy settings with proper structure
  final Map<String, dynamic> privacySettings;

  // ADD THESE MISSING PROPERTIES:
  final bool isConnected;
  final String? partnerName;
  final String? coupleCode;
  final DateTime? connectedAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoURL,
    this.isOnline = false,
    this.lastSeen,
    this.realtimeLastSeen,
    this.partnerId,
    this.oneSignalPlayerId,
    this.createdAt,
    this.updatedAt,
    this.privacySettings = const {},
    // ADD THESE TO CONSTRUCTOR:
    this.isConnected = false,
    this.partnerName,
    this.coupleCode,
    this.connectedAt,
  });

  // FIXED: Privacy setting getters with proper defaults
  bool get showOnlineStatus => privacySettings['showOnlineStatus'] ?? true;
  bool get showLastSeen => privacySettings['showLastSeen'] ?? true;

  // Create UserModel from Firestore document
  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? 'Unknown',
      photoURL: data['photoURL'],
      isOnline: data['isOnline'] ?? false,
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
      realtimeLastSeen:
          data['realtimeLastSeen'] != null
              ? DateTime.fromMillisecondsSinceEpoch(data['realtimeLastSeen'])
              : null,
      partnerId: data['partnerId'],
      oneSignalPlayerId: data['oneSignalPlayerId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      privacySettings: data['privacySettings'] ?? {},
      // ADD THESE:
      isConnected: data['isConnected'] ?? false,
      partnerName: data['partnerName'],
      coupleCode: data['coupleCode'],
      connectedAt: (data['connectedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Create UserModel from combined data (Firestore + Realtime Database)
  factory UserModel.fromCombinedData(Map<String, dynamic> data) {
    return UserModel(
      uid: data['uid'] ?? '',
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? 'Unknown',
      photoURL: data['photoURL'],
      isOnline: data['isOnline'] ?? false,
      lastSeen:
          data['lastSeen'] is Timestamp
              ? (data['lastSeen'] as Timestamp).toDate()
              : data['lastSeen'] is DateTime
              ? data['lastSeen'] as DateTime
              : null,
      realtimeLastSeen:
          data['realtimeLastSeen'] != null
              ? DateTime.fromMillisecondsSinceEpoch(data['realtimeLastSeen'])
              : null,
      partnerId: data['partnerId'],
      oneSignalPlayerId: data['oneSignalPlayerId'],
      createdAt:
          data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : data['createdAt'] is DateTime
              ? data['createdAt'] as DateTime
              : null,
      updatedAt:
          data['updatedAt'] is Timestamp
              ? (data['updatedAt'] as Timestamp).toDate()
              : data['updatedAt'] is DateTime
              ? data['updatedAt'] as DateTime
              : null,
      privacySettings: data['privacySettings'] ?? {},
      // ADD THESE:
      isConnected: data['isConnected'] ?? false,
      partnerName: data['partnerName'],
      coupleCode: data['coupleCode'],
      connectedAt:
          data['connectedAt'] is Timestamp
              ? (data['connectedAt'] as Timestamp).toDate()
              : data['connectedAt'] is DateTime
              ? data['connectedAt'] as DateTime
              : null,
    );
  }

  // Convert to map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      'isOnline': isOnline,
      'lastSeen': lastSeen != null ? Timestamp.fromDate(lastSeen!) : null,
      'partnerId': partnerId,
      'oneSignalPlayerId': oneSignalPlayerId,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'privacySettings': privacySettings,
      // ADD THESE:
      'isConnected': isConnected,
      'partnerName': partnerName,
      'coupleCode': coupleCode,
      'connectedAt':
          connectedAt != null ? Timestamp.fromDate(connectedAt!) : null,
    };
  }

  // Get user initials for avatar
  String get initials {
    final names = displayName.trim().split(' ');
    if (names.length >= 2) {
      return '${names.first[0]}${names.last[0]}'.toUpperCase();
    } else if (names.isNotEmpty) {
      return names.first.substring(0, 1).toUpperCase();
    }
    return '?';
  }

  // FIXED: Get the most accurate online status respecting privacy
  bool get actualOnlineStatus {
    // If user has disabled showing online status, return false for others
    if (!showOnlineStatus) return false;

    // Use real-time data if available, otherwise fallback to Firestore
    return isOnline;
  }

  // FIXED: Get the most accurate last seen time respecting privacy
  DateTime? get actualLastSeen {
    // If user has disabled showing last seen, return null for others
    if (!showLastSeen) return null;

    // Prioritize real-time last seen over Firestore last seen
    return realtimeLastSeen ?? lastSeen;
  }

  // FIXED: Check if user was recently active (within 2 minutes)
  bool get isRecentlyActive {
    if (actualOnlineStatus) return true;

    final lastSeenTime = actualLastSeen;
    if (lastSeenTime == null) return false;

    final difference = DateTime.now().difference(lastSeenTime);
    return difference.inMinutes <= 2;
  }

  // Check if user was active today
  bool get isActiveToday {
    if (actualOnlineStatus) return true;

    final lastSeenTime = actualLastSeen;
    if (lastSeenTime == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastSeenDate = DateTime(
      lastSeenTime.year,
      lastSeenTime.month,
      lastSeenTime.day,
    );

    return lastSeenDate.isAtSameMomentAs(today) || lastSeenDate.isAfter(today);
  }

  // FIXED: Get online status color with proper logic
  Color get onlineStatusColor {
    if (!showOnlineStatus) {
      return const Color(0xFF9E9E9E); // Gray for hidden status
    }

    if (actualOnlineStatus) {
      return const Color(0xFF4CAF50); // Green for online
    } else if (isRecentlyActive) {
      return const Color(0xFFFF9800); // Orange for recently active
    } else {
      return const Color(0xFF9E9E9E); // Gray for offline
    }
  }

  // FIXED: Chat screen status text (concise)
  String get chatStatusText {
    if (!showOnlineStatus && !showLastSeen) {
      return 'Hidden';
    }

    if (actualOnlineStatus) {
      return 'Online';
    }

    if (!showLastSeen) {
      return 'Offline';
    }

    final lastSeenTime = actualLastSeen;
    if (lastSeenTime == null) {
      return 'Offline';
    }

    final now = DateTime.now();
    final difference = now.difference(lastSeenTime);

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

  // FIXED: Profile screen status text (detailed)
  String get profileStatusText {
    if (!showOnlineStatus && !showLastSeen) {
      return 'Status hidden';
    }

    if (actualOnlineStatus) {
      return 'Online now';
    }

    if (!showLastSeen) {
      return 'Status hidden';
    }

    final lastSeenTime = actualLastSeen;
    if (lastSeenTime == null) {
      return 'Last seen unknown';
    }

    final now = DateTime.now();
    final difference = now.difference(lastSeenTime);

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

  // FIXED: Profile screen status color
  Color get profileStatusColor {
    if (!showOnlineStatus) {
      return const Color(0xFF9E9E9E); // Gray for hidden
    }

    if (actualOnlineStatus) {
      return const Color(0xFF4CAF50); // Green
    } else if (isRecentlyActive) {
      return const Color(0xFFFF9800); // Orange
    } else {
      return const Color(0xFF9E9E9E); // Gray
    }
  }

  // Backward compatibility getters
  String get statusText => chatStatusText;
  String get lastSeenText => chatStatusText;
  String get detailedLastSeenText => profileStatusText;
  String get detailedStatusText => profileStatusText;

  // Copy with method for updating user data
  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
    bool? isOnline,
    DateTime? lastSeen,
    DateTime? realtimeLastSeen,
    String? partnerId,
    String? oneSignalPlayerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? privacySettings,
    // ADD THESE:
    bool? isConnected,
    String? partnerName,
    String? coupleCode,
    DateTime? connectedAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      realtimeLastSeen: realtimeLastSeen ?? this.realtimeLastSeen,
      partnerId: partnerId ?? this.partnerId,
      oneSignalPlayerId: oneSignalPlayerId ?? this.oneSignalPlayerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      privacySettings: privacySettings ?? this.privacySettings,
      // ADD THESE:
      isConnected: isConnected ?? this.isConnected,
      partnerName: partnerName ?? this.partnerName,
      coupleCode: coupleCode ?? this.coupleCode,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, displayName: $displayName, isOnline: $actualOnlineStatus, status: $chatStatusText)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is UserModel &&
        other.uid == uid &&
        other.email == email &&
        other.displayName == displayName &&
        other.photoURL == photoURL &&
        other.isOnline == isOnline &&
        other.lastSeen == lastSeen &&
        other.realtimeLastSeen == realtimeLastSeen &&
        other.partnerId == partnerId &&
        other.oneSignalPlayerId == oneSignalPlayerId &&
        // ADD THESE:
        other.isConnected == isConnected &&
        other.partnerName == partnerName &&
        other.coupleCode == coupleCode &&
        other.connectedAt == connectedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      uid,
      email,
      displayName,
      photoURL,
      isOnline,
      lastSeen,
      realtimeLastSeen,
      partnerId,
      oneSignalPlayerId,
      // ADD THESE:
      isConnected,
      partnerName,
      coupleCode,
      connectedAt,
    );
  }
}
