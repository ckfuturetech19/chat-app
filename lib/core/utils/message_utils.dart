import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:onlyus/models/message_model.dart';

import '../constants/app_strings.dart';

class MessageUtils {
  // Private constructor to prevent instantiation
  MessageUtils._();

  // Check if message contains only emojis
  static bool isOnlyEmojis(String text) {
    if (text.trim().isEmpty) return false;
    
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1F018}-\u{1F270}]',
      unicode: true,
    );
    
    final cleanText = text.replaceAll(RegExp(r'\s'), '');
    final emojiMatches = emojiRegex.allMatches(cleanText);
    
    if (emojiMatches.isEmpty) return false;
    
    final emojiText = emojiMatches.map((m) => m.group(0)!).join();
    return emojiText == cleanText;
  }

  // Check if message is a URL
  static bool isUrl(String text) {
    final urlRegex = RegExp(
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$',
      caseSensitive: false,
    );
    return urlRegex.hasMatch(text.trim());
  }

  // Extract URLs from message text
  static List<String> extractUrls(String text) {
    final urlRegex = RegExp(
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    
    return urlRegex.allMatches(text).map((match) => match.group(0)!).toList();
  }

  // Check if message contains hearts
  static bool containsHearts(String text) {
    final heartRegex = RegExp(r'[❤️💕💖💗💙💚💛🧡💜🖤💝💘💌💟💍]');
    return heartRegex.hasMatch(text);
  }

  // Count hearts in message
  static int countHearts(String text) {
    final heartRegex = RegExp(r'[❤️💕💖💗💙💚💛🧡💜🖤💝💘💌💟💍]');
    return heartRegex.allMatches(text).length;
  }

  // Get message preview for notifications
  static String getMessagePreview(MessageModel message, {int maxLength = 50}) {
    switch (message.type) {
      case MessageType.image:
        return message.message.isNotEmpty 
            ? message.message.length > maxLength
                ? '📷 ${message.message.substring(0, maxLength)}...'
                : '📷 ${message.message}'
            : AppStrings.photoMessage;
      case MessageType.text:
        if (message.message.length > maxLength) {
          return '${message.message.substring(0, maxLength)}...';
        }
        return message.message;
    }
  }

  // Get appropriate font size for emoji messages
  static double getEmojiFontSize(String text) {
    if (!isOnlyEmojis(text)) return 16.0;
    
    final emojiCount = text.replaceAll(RegExp(r'\s'), '').length;
    
    if (emojiCount == 1) return 48.0;
    if (emojiCount == 2) return 36.0;
    if (emojiCount <= 4) return 28.0;
    return 24.0;
  }

  // Check if message needs special rendering
  static bool needsSpecialRendering(MessageModel message) {
    return isOnlyEmojis(message.message) || 
           containsHearts(message.message) ||
           isUrl(message.message);
  }

  // Generate message ID
  static String generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random().nextInt(9999);
    return '${timestamp}_$random';
  }

  // Check if messages should be grouped
  static bool shouldGroupMessages(
    MessageModel? previousMessage,
    MessageModel currentMessage, {
    Duration maxTimeDifference = const Duration(minutes: 5),
  }) {
    if (previousMessage == null) return false;
    
    // Same sender
    if (previousMessage.senderId != currentMessage.senderId) return false;
    
    // Within time limit
    final timeDifference = currentMessage.timestamp.difference(previousMessage.timestamp);
    if (timeDifference > maxTimeDifference) return false;
    
    // Both are text messages (don't group images)
    if (previousMessage.type != MessageType.text || 
        currentMessage.type != MessageType.text) return false;
    
    return true;
  }

  // Get message bubble color based on content
  static Color getMessageBubbleColor(MessageModel message, bool isMyMessage) {
    if (containsHearts(message.message)) {
      return isMyMessage 
          ? const Color(0xFFFF69B4) // Hot pink for heart messages
          : const Color(0xFFDDA0DD); // Plum for partner's heart messages
    }
    
    return isMyMessage 
        ? const Color(0xFFF8BBD9) // Default my message color
        : const Color(0xFFE0E7FF); // Default partner message color
  }

  // Format message size for display
  static String formatMessageSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Validate message content
  static String? validateMessage(String message) {
    final trimmed = message.trim();
    
    if (trimmed.isEmpty) {
      return 'Message cannot be empty';
    }
    
    if (trimmed.length > 4000) {
      return 'Message is too long (max 4000 characters)';
    }
    
    return null; // Message is valid
  }

  // Clean message text for display
  static String cleanMessageText(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ') // Replace multiple spaces with single space
        .replaceAll(RegExp(r'\n+'), '\n'); // Replace multiple newlines with single newline
  }

  // Check if message is a romantic message
  static bool isRomanticMessage(String text) {
    final romanticKeywords = [
      'love', 'heart', 'kiss', 'hug', 'miss', 'beautiful', 'gorgeous',
      'handsome', 'sweet', 'honey', 'baby', 'darling', 'sweetheart',
      'babe', 'cutie', 'angel', 'princess', 'prince', 'forever',
      'always', 'together', 'soul', 'mate', 'dream', 'wonderful',
    ];
    
    final lowerText = text.toLowerCase();
    return romanticKeywords.any((keyword) => lowerText.contains(keyword)) ||
           containsHearts(text);
  }

  // Get text direction for message
  static TextDirection getTextDirection(String text) {
    // Check for RTL characters (Arabic, Hebrew, etc.)
    final rtlRegex = RegExp(r'[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F]');
    return rtlRegex.hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;
  }

  // Extract mentions from message (@username)
  static List<String> extractMentions(String text) {
    final mentionRegex = RegExp(r'@([a-zA-Z0-9_]+)');
    return mentionRegex
        .allMatches(text)
        .map((match) => match.group(1)!)
        .toList();
  }

  // Extract hashtags from message (#hashtag)
  static List<String> extractHashtags(String text) {
    final hashtagRegex = RegExp(r'#([a-zA-Z0-9_]+)');
    return hashtagRegex
        .allMatches(text)
        .map((match) => match.group(1)!)
        .toList();
  }

  // Check if message contains sensitive content
  static bool containsSensitiveContent(String text) {
    // This is a basic implementation - in production, you might want
    // to use a more sophisticated content filtering service
    final sensitiveWords = [
      // Add words you want to filter
    ];
    
    final lowerText = text.toLowerCase();
    return sensitiveWords.any((word) => lowerText.contains(word));
  }

  // Get message priority based on content
  static MessagePriority getMessagePriority(MessageModel message) {
    final text = message.message.toLowerCase();
    
    if (text.contains('urgent') || text.contains('emergency') || text.contains('help')) {
      return MessagePriority.high;
    }
    
    if (isRomanticMessage(message.message) || containsHearts(message.message)) {
      return MessagePriority.high;
    }
    
    if (message.type == MessageType.image) {
      return MessagePriority.medium;
    }
    
    return MessagePriority.normal;
  }

  // Generate message search keywords
  static List<String> generateSearchKeywords(MessageModel message) {
    final keywords = <String>[];
    
    // Add message text words
    final words = message.message
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .toList();
    
    keywords.addAll(words);
    
    // Add sender name
    keywords.add(message.senderName.toLowerCase());
    
    // Add message type
    keywords.add(message.type.name);
    
    // Add date components
    final date = message.timestamp;
    keywords.addAll([
      date.year.toString(),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
    ]);
    
    return keywords.toSet().toList(); // Remove duplicates
  }

  // Calculate message similarity (for duplicate detection)
  static double calculateSimilarity(String text1, String text2) {
    if (text1 == text2) return 1.0;
    
    final words1 = text1.toLowerCase().split(RegExp(r'\s+'));
    final words2 = text2.toLowerCase().split(RegExp(r'\s+'));
    
    final commonWords = words1.where((word) => words2.contains(word)).length;
    final totalWords = math.max(words1.length, words2.length);
    
    return totalWords > 0 ? commonWords / totalWords : 0.0;
  }

  // Check if message is a duplicate
  static bool isDuplicateMessage(
    MessageModel message,
    List<MessageModel> recentMessages, {
    double similarityThreshold = 0.8,
    Duration timeWindow = const Duration(minutes: 1),
  }) {
    final cutoffTime = message.timestamp.subtract(timeWindow);
    
    final recentSimilarMessages = recentMessages.where((msg) =>
        msg.senderId == message.senderId &&
        msg.timestamp.isAfter(cutoffTime) &&
        msg.id != message.id);
    
    for (final recentMessage in recentSimilarMessages) {
      final similarity = calculateSimilarity(
        message.message,
        recentMessage.message,
      );
      
      if (similarity >= similarityThreshold) {
        return true;
      }
    }
    
    return false;
  }

  // Get message reactions (for future enhancement)
  static List<String> getSuggestedReactions(MessageModel message) {
    if (isRomanticMessage(message.message) || containsHearts(message.message)) {
      return ['❤️', '😍', '🥰', '😘', '💕'];
    }
    
    if (isOnlyEmojis(message.message)) {
      return ['😊', '😂', '👍', '❤️', '🔥'];
    }
    
    return ['👍', '❤️', '😊', '😂', '🎉'];
  }

  // Format message for sharing
  static String formatForSharing(MessageModel message) {
    final timestamp = message.formattedTime;
    final sender = message.senderName;
    
    switch (message.type) {
      case MessageType.text:
        return '$sender ($timestamp): ${message.message}';
      case MessageType.image:
        final caption = message.message.isNotEmpty ? ': ${message.message}' : '';
        return '$sender ($timestamp): [Image$caption]';
    }
  }
}

// Message priority enum
enum MessagePriority {
  low,
  normal,
  medium,
  high,
  urgent,
}

// Message search result
class MessageSearchResult {
  final MessageModel message;
  final List<String> matchedKeywords;
  final double relevanceScore;

  const MessageSearchResult({
    required this.message,
    required this.matchedKeywords,
    required this.relevanceScore,
  });
}

// Message statistics
class MessageStatistics {
  final int totalMessages;
  final int textMessages;
  final int imageMessages;
  final int heartsCount;
  final int emojiOnlyMessages;
  final DateTime? firstMessageDate;
  final DateTime? lastMessageDate;
  final Map<String, int> topWords;
  final Map<String, int> dailyMessageCounts;

  const MessageStatistics({
    required this.totalMessages,
    required this.textMessages,
    required this.imageMessages,
    required this.heartsCount,
    required this.emojiOnlyMessages,
    this.firstMessageDate,
    this.lastMessageDate,
    required this.topWords,
    required this.dailyMessageCounts,
  });

  factory MessageStatistics.fromMessages(List<MessageModel> messages) {
    if (messages.isEmpty) {
      return const MessageStatistics(
        totalMessages: 0,
        textMessages: 0,
        imageMessages: 0,
        heartsCount: 0,
        emojiOnlyMessages: 0,
        topWords: {},
        dailyMessageCounts: {},
      );
    }

    final sortedMessages = [...messages]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    int textCount = 0;
    int imageCount = 0;
    int heartsCount = 0;
    int emojiOnlyCount = 0;
    final wordCounts = <String, int>{};
    final dailyCounts = <String, int>{};

    for (final message in messages) {
      // Count message types
      if (message.type == MessageType.text) {
        textCount++;
      } else if (message.type == MessageType.image) {
        imageCount++;
      }

      // Count hearts
      heartsCount += MessageUtils.countHearts(message.message);

      // Count emoji-only messages
      if (MessageUtils.isOnlyEmojis(message.message)) {
        emojiOnlyCount++;
      }

      // Count words
      final words = message.message
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((word) => word.length > 2);

      for (final word in words) {
        wordCounts[word] = (wordCounts[word] ?? 0) + 1;
      }

      // Count daily messages
      final dateKey = '${message.timestamp.year}-${message.timestamp.month.toString().padLeft(2, '0')}-${message.timestamp.day.toString().padLeft(2, '0')}';
      dailyCounts[dateKey] = (dailyCounts[dateKey] ?? 0) + 1;
    }

    // Get top 10 words
    final sortedWords = wordCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topWords = Map.fromEntries(sortedWords.take(10));

    return MessageStatistics(
      totalMessages: messages.length,
      textMessages: textCount,
      imageMessages: imageCount,
      heartsCount: heartsCount,
      emojiOnlyMessages: emojiOnlyCount,
      firstMessageDate: sortedMessages.first.timestamp,
      lastMessageDate: sortedMessages.last.timestamp,
      topWords: topWords,
      dailyMessageCounts: dailyCounts,
    );
  }
}