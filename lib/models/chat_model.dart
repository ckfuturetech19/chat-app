import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String chatId;
  final List<String> participants;
  final Map<String, String> participantNames;
  final Map<String, String> participantPhotos;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final String lastMessageSender;
  final Map<String, bool> typingUsers;
  final Map<String, int> unreadCounts;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatModel({
    required this.chatId,
    required this.participants,
    required this.participantNames,
    required this.participantPhotos,
    required this.lastMessage,
    this.lastMessageTime,
    required this.lastMessageSender,
    required this.typingUsers,
    required this.unreadCounts,
    required this.createdAt,
    required this.updatedAt,
  });

  // Create ChatModel from Firestore document
  factory ChatModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    
    return ChatModel(
      chatId: data['chatId'] ?? doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      participantNames: Map<String, String>.from(data['participantNames'] ?? {}),
      participantPhotos: Map<String, String>.from(data['participantPhotos'] ?? {}),
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: data['lastMessageTime'] != null
          ? (data['lastMessageTime'] as Timestamp).toDate()
          : null,
      lastMessageSender: data['lastMessageSender'] ?? '',
      typingUsers: Map<String, bool>.from(data['typingUsers'] ?? {}),
      unreadCounts: Map<String, int>.from(
        (data['unreadCounts'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(key, value as int? ?? 0)),
      ),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  // Create ChatModel from Map
  factory ChatModel.fromMap(Map<String, dynamic> data, String id) {
    return ChatModel(
      chatId: data['chatId'] ?? id,
      participants: List<String>.from(data['participants'] ?? []),
      participantNames: Map<String, String>.from(data['participantNames'] ?? {}),
      participantPhotos: Map<String, String>.from(data['participantPhotos'] ?? {}),
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: data['lastMessageTime'] != null
          ? (data['lastMessageTime'] as Timestamp).toDate()
          : null,
      lastMessageSender: data['lastMessageSender'] ?? '',
      typingUsers: Map<String, bool>.from(data['typingUsers'] ?? {}),
      unreadCounts: Map<String, int>.from(
        (data['unreadCounts'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(key, value as int? ?? 0)),
      ),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  // Convert ChatModel to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'participants': participants,
      'participantNames': participantNames,
      'participantPhotos': participantPhotos,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime != null 
          ? Timestamp.fromDate(lastMessageTime!) 
          : null,
      'lastMessageSender': lastMessageSender,
      'typingUsers': typingUsers,
      'unreadCounts': unreadCounts,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // Create a copy with updated fields
  ChatModel copyWith({
    String? chatId,
    List<String>? participants,
    Map<String, String>? participantNames,
    Map<String, String>? participantPhotos,
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageSender,
    Map<String, bool>? typingUsers,
    Map<String, int>? unreadCounts,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatModel(
      chatId: chatId ?? this.chatId,
      participants: participants ?? this.participants,
      participantNames: participantNames ?? this.participantNames,
      participantPhotos: participantPhotos ?? this.participantPhotos,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSender: lastMessageSender ?? this.lastMessageSender,
      typingUsers: typingUsers ?? this.typingUsers,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Get the other participant's ID (partner)
  String? getPartnerUserId(String currentUserId) {
    return participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
  }

  // Get partner's name
  String getPartnerName(String currentUserId) {
    final partnerId = getPartnerUserId(currentUserId);
    if (partnerId == null || partnerId.isEmpty) return 'Unknown';
    return participantNames[partnerId] ?? 'Unknown';
  }

  // Get partner's photo URL
  String? getPartnerPhotoUrl(String currentUserId) {
    final partnerId = getPartnerUserId(currentUserId);
    if (partnerId == null || partnerId.isEmpty) return null;
    return participantPhotos[partnerId];
  }

  // Check if partner is typing
  bool isPartnerTyping(String currentUserId) {
    final partnerId = getPartnerUserId(currentUserId);
    if (partnerId == null || partnerId.isEmpty) return false;
    return typingUsers[partnerId] ?? false;
  }

  // Get unread count for current user
  int getUnreadCount(String currentUserId) {
    return unreadCounts[currentUserId] ?? 0;
  }

  // Check if chat has any messages
  bool get hasMessages => lastMessage.isNotEmpty;

  // Get formatted last message time
  String get formattedLastMessageTime {
    if (lastMessageTime == null) return '';
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(
      lastMessageTime!.year,
      lastMessageTime!.month,
      lastMessageTime!.day,
    );
    
    if (messageDate == today) {
      // Today: show time only
      final hour = lastMessageTime!.hour;
      final minute = lastMessageTime!.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(messageDate).inDays < 7) {
      // This week: show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[lastMessageTime!.weekday - 1];
    } else {
      // Older: show date
      final month = lastMessageTime!.month.toString().padLeft(2, '0');
      final day = lastMessageTime!.day.toString().padLeft(2, '0');
      return '$month/$day';
    }
  }

  // Get display text for last message
  String get displayLastMessage {
    if (lastMessage.isEmpty) return 'No messages yet';
    
    // Truncate long messages
    if (lastMessage.length > 50) {
      return '${lastMessage.substring(0, 50)}...';
    }
    
    return lastMessage;
  }

  // Check if current user sent the last message
  bool didCurrentUserSendLastMessage(String currentUserId) {
    return lastMessageSender == currentUserId;
  }

  // Get all typing users except current user
  List<String> getOtherTypingUsers(String currentUserId) {
    return typingUsers.entries
        .where((entry) => entry.key != currentUserId && entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  // Get typing status text
  String getTypingStatusText(String currentUserId) {
    final otherTypingUsers = getOtherTypingUsers(currentUserId);
    
    if (otherTypingUsers.isEmpty) return '';
    
    if (otherTypingUsers.length == 1) {
      final userId = otherTypingUsers.first;
      final name = participantNames[userId] ?? 'Someone';
      return '$name is typing...';
    } else {
      return 'Multiple people are typing...';
    }
  }

  // Check if chat is active (has recent activity)
  bool get isActive {
    if (lastMessageTime == null) return false;
    
    final now = DateTime.now();
    final difference = now.difference(lastMessageTime!);
    
    // Consider active if last message was within 7 days
    return difference.inDays <= 7;
  }

  // Check if this is a new chat (no messages)
  bool get isNewChat => lastMessage.isEmpty && lastMessageTime == null;

  // Get chat age in days
  int get ageInDays {
    final now = DateTime.now();
    return now.difference(createdAt).inDays;
  }

  // Get total participants count
  int get participantCount => participants.length;

  // Check if user is participant
  bool isUserParticipant(String userId) {
    return participants.contains(userId);
  }

  // Get chat summary for display
  String getChatSummary(String currentUserId) {
    final partner = getPartnerName(currentUserId);
    final messageCount = unreadCounts.values.fold<int>(0, (sum, count) => sum + count);
    
    if (isNewChat) {
      return 'New chat with $partner';
    } else if (messageCount > 0) {
      return '$messageCount unread messages from $partner';
    } else {
      return 'Chat with $partner';
    }
  }

  @override
  String toString() {
    return 'ChatModel{chatId: $chatId, participants: $participants, lastMessage: $lastMessage}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatModel &&
        other.chatId == chatId &&
        other.participants.toString() == participants.toString() &&
        other.lastMessage == lastMessage &&
        other.lastMessageTime == lastMessageTime &&
        other.lastMessageSender == lastMessageSender;
  }

  @override
  int get hashCode {
    return chatId.hashCode ^
        participants.hashCode ^
        lastMessage.hashCode ^
        lastMessageTime.hashCode ^
        lastMessageSender.hashCode;
  }
}