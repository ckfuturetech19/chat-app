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
  });

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
      realtimeLastSeen: data['realtimeLastSeen'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(data['realtimeLastSeen'])
          : null,
      partnerId: data['partnerId'],
      oneSignalPlayerId: data['oneSignalPlayerId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
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
      lastSeen: data['lastSeen'] is Timestamp 
          ? (data['lastSeen'] as Timestamp).toDate()
          : data['lastSeen'] is DateTime 
              ? data['lastSeen'] as DateTime
              : null,
      realtimeLastSeen: data['realtimeLastSeen'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(data['realtimeLastSeen'])
          : null,
      partnerId: data['partnerId'],
      oneSignalPlayerId: data['oneSignalPlayerId'],
      createdAt: data['createdAt'] is Timestamp 
          ? (data['createdAt'] as Timestamp).toDate()
          : data['createdAt'] is DateTime 
              ? data['createdAt'] as DateTime
              : null,
      updatedAt: data['updatedAt'] is Timestamp 
          ? (data['updatedAt'] as Timestamp).toDate()
          : data['updatedAt'] is DateTime 
              ? data['updatedAt'] as DateTime
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

  // Get formatted last seen text with real-time data priority
  String get lastSeenText {
    if (isOnline) {
      return 'Online';
    }
    
    // Use real-time last seen if available, otherwise fallback to Firestore
    final lastSeenTime = realtimeLastSeen ?? lastSeen;
    
    if (lastSeenTime == null) {
      return 'Last seen unknown';
    }

    final now = DateTime.now();
    final difference = now.difference(lastSeenTime);

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
  }

  // Get more detailed last seen text
  String get detailedLastSeenText {
    if (isOnline) {
      return 'Online now';
    }
    
    final lastSeenTime = realtimeLastSeen ?? lastSeen;
    
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

  // Check if user was recently active (within 5 minutes)
  bool get isRecentlyActive {
    if (isOnline) return true;
    
    final lastSeenTime = realtimeLastSeen ?? lastSeen;
    if (lastSeenTime == null) return false;
    
    final difference = DateTime.now().difference(lastSeenTime);
    return difference.inMinutes <= 5;
  }

  // Check if user was active today
  bool get isActiveToday {
    if (isOnline) return true;
    
    final lastSeenTime = realtimeLastSeen ?? lastSeen;
    if (lastSeenTime == null) return false;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastSeenDate = DateTime(lastSeenTime.year, lastSeenTime.month, lastSeenTime.day);
    
    return lastSeenDate.isAtSameMomentAs(today) || lastSeenDate.isAfter(today);
  }

  // Get online status color
  Color get onlineStatusColor {
    if (isOnline) {
      return const Color(0xFF4CAF50); // Green
    } else if (isRecentlyActive) {
      return const Color(0xFFFF9800); // Orange
    } else {
      return const Color(0xFF9E9E9E); // Gray
    }
  }

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
    );
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, displayName: $displayName, isOnline: $isOnline, lastSeen: $lastSeenText)';
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
        other.oneSignalPlayerId == oneSignalPlayerId;
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
    );
  }
}