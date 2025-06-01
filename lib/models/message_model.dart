import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image }

class MessageModel {
  final String id;
  final String chatId;
  final String message;
  final String? imageUrl;
  final String senderId;
  final String senderName;
  final DateTime timestamp;
  final bool isRead;
  final bool isDelivered;
  final DateTime? readAt;
  final MessageType type;
  final bool? isDeleted;
  final DateTime? deletedAt;
  final bool isFavorited;
  final List<String> favoritedBy;

  const MessageModel({
    required this.id,
    required this.chatId,
    required this.message,
    this.imageUrl,
    required this.senderId,
    required this.senderName,
    required this.timestamp,
    required this.isRead,
    required this.isDelivered,
    this.readAt,
    required this.type,
    this.isDeleted,
    this.deletedAt,
    this.isFavorited = false,
    this.favoritedBy = const [],
  });

  // Create MessageModel from Firestore document
  factory MessageModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return MessageModel(
      id: doc.id,
      chatId: data['chatId'] ?? '',
      message: data['message'] ?? '',
      imageUrl: data['imageUrl'],
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      isRead: data['isRead'] ?? false,
      isDelivered: data['isDelivered'] ?? false,
      readAt: data['readAt'] != null
          ? (data['readAt'] as Timestamp).toDate()
          : null,
      type: _parseMessageType(data['type']),
      isDeleted: data['isDeleted'] ?? false,
      deletedAt: data['deletedAt'] != null
          ? (data['deletedAt'] as Timestamp).toDate()
          : null,
      isFavorited: data['isFavorited'] ?? false,
      favoritedBy: List<String>.from(data['favoritedBy'] ?? []),
    );
  }

  // Create MessageModel from Map (used when loading from cache)
  factory MessageModel.fromMap(Map<String, dynamic> data, String id) {
  return MessageModel(
    id: id,
    chatId: data['chatId'] ?? '',
    message: data['message'] ?? '',
    imageUrl: data['imageUrl'],
    senderId: data['senderId'] ?? '',
    senderName: data['senderName'] ?? 'Unknown',
    timestamp: _parseTimestamp(data['timestamp']) ?? DateTime.now(),
    isRead: data['isRead'] ?? false,
    isDelivered: data['isDelivered'] ?? false,
    readAt: _parseTimestamp(data['readAt']),
    type: _parseMessageType(data['type']),
    isDeleted: data['isDeleted'] ?? false,
    deletedAt: _parseTimestamp(data['deletedAt']),
    isFavorited: data['isFavorited'] ?? false,
    favoritedBy: List<String>.from(data['favoritedBy'] ?? []),
  );
}

// Add this helper method to MessageModel
static DateTime? _parseTimestamp(dynamic timestamp) {
  if (timestamp == null) return null;
  
  if (timestamp is Timestamp) {
    return timestamp.toDate();
  }
  
  if (timestamp is DateTime) {
    return timestamp;
  }
  
  if (timestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
  
  return null;
}
  // Alternative constructor for creating from cache with string ID
  factory MessageModel.fromCacheMap(Map<String, dynamic> data) {
    return MessageModel.fromMap(data, data['id'] ?? '');
  }

  // Parse message type from string
  static MessageType _parseMessageType(dynamic typeData) {
    if (typeData == null) return MessageType.text;
    
    switch (typeData.toString().toLowerCase()) {
      case 'image':
        return MessageType.image;
      case 'text':
      default:
        return MessageType.text;
    }
  }

  // Convert to Map for Firestore (with Timestamp objects)
  Map<String, dynamic> toFirestore() {
    return {
      'chatId': chatId,
      'message': message,
      'imageUrl': imageUrl,
      'senderId': senderId,
      'senderName': senderName,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
      'isDelivered': isDelivered,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'type': type.name,
      'isDeleted': isDeleted ?? false,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'isFavorited': isFavorited,
      'favoritedBy': favoritedBy,
    };
  }

  // Convert to Map for caching (with milliseconds instead of Timestamp)
 Map<String, dynamic> toMap() {
  return {
    'id': id,
    'chatId': chatId,
    'message': message,
    'imageUrl': imageUrl,
    'senderId': senderId,
    'senderName': senderName,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'isRead': isRead,
    'isDelivered': isDelivered,
    'readAt': readAt?.millisecondsSinceEpoch,
    'type': type.name,
    'isDeleted': isDeleted ?? false,
    'deletedAt': deletedAt?.millisecondsSinceEpoch,
    'isFavorited': isFavorited,
    'favoritedBy': favoritedBy,
  };
}

  // Create a copy with updated fields
  MessageModel copyWith({
    String? id,
    String? chatId,
    String? message,
    String? imageUrl,
    String? senderId,
    String? senderName,
    DateTime? timestamp,
    bool? isRead,
    bool? isDelivered,
    DateTime? readAt,
    MessageType? type,
    bool? isDeleted,
    DateTime? deletedAt,
    bool? isFavorited,
    List<String>? favoritedBy,
  }) {
    return MessageModel(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      message: message ?? this.message,
      imageUrl: imageUrl ?? this.imageUrl,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      isDelivered: isDelivered ?? this.isDelivered,
      readAt: readAt ?? this.readAt,
      type: type ?? this.type,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      isFavorited: isFavorited ?? this.isFavorited,
      favoritedBy: favoritedBy ?? this.favoritedBy,
    );
  }

  // Check if message is from current user
  bool isFromCurrentUser(String currentUserId) {
    return senderId == currentUserId;
  }

  // Check if message is deleted
  bool get isMessageDeleted {
    return isDeleted == true;
  }

  // Get display text for notifications (handle deleted messages)
  String get displayText {
    if (isMessageDeleted) {
      return 'This message was deleted';
    }
    
    switch (type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.text:
        if (message.length > 50) {
          return '${message.substring(0, 50)}...';
        }
        return message;
    }
  }

  // Get message content (handle deleted messages)
  String get messageContent {
    if (isMessageDeleted) {
      return 'This message was deleted';
    }
    return message;
  }

  // Get formatted timestamp
  String get formattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    if (messageDate == today) {
      // Today: show time only
      final hour = timestamp.hour;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(messageDate).inDays < 7) {
      // This week: show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[timestamp.weekday - 1];
    } else {
      // Older: show date
      final month = timestamp.month.toString().padLeft(2, '0');
      final day = timestamp.day.toString().padLeft(2, '0');
      return '$month/$day';
    }
  }

  // Get detailed formatted timestamp
  String get detailedFormattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    final hour = timestamp.hour;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final timeString = '$displayHour:$minute $period';
    
    if (messageDate == today) {
      return 'Today at $timeString';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday at $timeString';
    } else {
      final month = timestamp.month.toString().padLeft(2, '0');
      final day = timestamp.day.toString().padLeft(2, '0');
      final year = timestamp.year;
      return '$month/$day/$year at $timeString';
    }
  }

  // Get message status icon
  String get statusIcon {
    if (!isDelivered) return '⏳'; // Pending
    if (!isRead) return '✓'; // Delivered
    return '✓✓'; // Read
  }

  // Get message status text
  String get statusText {
    if (!isDelivered) return 'Sending...';
    if (!isRead) return 'Delivered';
    return 'Read';
  }

  // Check if message contains only emojis
  bool get isOnlyEmojis {
    if (type != MessageType.text || message.trim().isEmpty || isMessageDeleted) return false;
    
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
      unicode: true,
    );
    
    final cleanMessage = message.replaceAll(RegExp(r'\s'), '');
    final emojiMatches = emojiRegex.allMatches(cleanMessage);
    
    return emojiMatches.length > 0 && 
           emojiMatches.map((m) => m.group(0)!).join() == cleanMessage;
  }

  @override
  String toString() {
    return 'MessageModel{id: $id, chatId: $chatId, senderId: $senderId, type: $type, isRead: $isRead, isDeleted: $isDeleted}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageModel &&
        other.id == id &&
        other.chatId == chatId &&
        other.message == message &&
        other.imageUrl == imageUrl &&
        other.senderId == senderId &&
        other.timestamp == timestamp &&
        other.isRead == isRead &&
        other.isDelivered == isDelivered &&
        other.type == type &&
        other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        chatId.hashCode ^
        message.hashCode ^
        imageUrl.hashCode ^
        senderId.hashCode ^
        timestamp.hashCode ^
        isRead.hashCode ^
        isDelivered.hashCode ^
        type.hashCode ^
        (isDeleted?.hashCode ?? 0);
  }
}