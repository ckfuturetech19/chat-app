import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/firebase_service.dart';
import '../core/services/chat_service.dart';

final enhancedTypingStatusProvider = StreamProvider.family<bool, String>((ref, userId) {
  // Get the current chat ID from ChatService
  final chatService = ChatService.instance;
  final chatId = chatService.activeChatId;

  if (chatId == null || chatId.isEmpty) {
    return Stream.value(false);
  }

  return FirebaseService.chatsCollection
      .doc(chatId)
      .snapshots()
      .map((doc) {
        if (!doc.exists || doc.data() == null) return false;
        
        final chatData = doc.data() as Map<String, dynamic>;
        final typingUsers = chatData['typingUsers'] as Map<String, dynamic>? ?? {};
        
        return typingUsers[userId] as bool? ?? false;
      })
      .distinct() // Only emit when typing status actually changes
      .handleError((error) {
        print('❌ Enhanced typing status stream error: $error');
        return false;
      });
});

// Alternative typing provider that works without ChatService dependency
final simpleTypingStatusProvider = StreamProvider.family<bool, String>((ref, userId) {
  // Find any chat where the user is a participant and check typing status
  return FirebaseService.chatsCollection
      .where('participants', arrayContains: userId)
      .limit(1)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isEmpty) return false;
        
        final chatDoc = snapshot.docs.first;
        final chatData = chatDoc.data();
        final typingUsers = chatData['typingUsers'] as Map<String, dynamic>? ?? {};
        
        return typingUsers[userId] as bool? ?? false;
      })
      .handleError((error) {
        print('❌ Simple typing status stream error: $error');
        return false;
      });
});

// Use this as the main typing provider
final typingStatusProvider = enhancedTypingStatusProvider;