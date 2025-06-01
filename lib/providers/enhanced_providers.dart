import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/services/firebase_service.dart';
import '../core/services/chat_service.dart';
import '../models/user_model.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';

// Enhanced typing status provider with better real-time updates
final enhancedTypingStatusProvider = StreamProvider.family<bool, String>((ref, userId) {
  final chatService = ChatService.instance;
  final chatId = chatService.activeChatId;

  if (chatId == null || chatId.isEmpty) {
    return Stream.value(false);
  }

  return FirebaseService.chatsCollection
      .doc(chatId)
      .snapshots()
      .map((snapshot) {
        if (!snapshot.exists) return false;
        
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data == null) return false;
        
        final typingUsers = data['typingUsers'] as Map<String, dynamic>? ?? {};
        final isTyping = typingUsers[userId] as bool? ?? false;
        
        // Also check timestamp to auto-clear stale typing status
        if (isTyping) {
          final typingTimestamp = data['typingTimestamp'] as Map<String, dynamic>? ?? {};
          final userTypingTime = typingTimestamp[userId];
          
          if (userTypingTime != null) {
            final timestamp = (userTypingTime as Timestamp).toDate();
            final now = DateTime.now();
            
            // Clear typing status if older than 5 seconds
            if (now.difference(timestamp).inSeconds > 5) {
              return false;
            }
          }
        }
        
        return isTyping;
      })
      .handleError((error) {
        print('❌ Enhanced typing status error: $error');
        return false;
      });
});

// User status color provider for visual indicators
final userStatusColorProvider = Provider.family<Color, UserModel>((ref, user) {
  // Check if user is online
  if (user.isOnline == true) {
    return Colors.green;
  }
  
  // Check last seen
  if (user.lastSeen != null) {
    final now = DateTime.now();
    final difference = now.difference(user.lastSeen!);
    
    if (difference.inMinutes < 5) {
      return Colors.orange; // Recently active
    } else if (difference.inHours < 1) {
      return Colors.yellow; // Active within hour
    }
  }
  
  return Colors.grey; // Offline or unknown
});

// Quick status text provider for privacy-aware status display
final userQuickStatusProvider = Provider.family<String, UserModel>((ref, user) {
  return user.chatStatusText;
});

// Real-time partner user provider with enhanced updates
final realTimePartnerUserProvider = StreamProvider<UserModel?>((ref) {
  final currentUserId = ref.watch(authControllerProvider.notifier).currentUserId;
  
  if (currentUserId == null) {
    return Stream.value(null);
  }

  return ChatService.instance.getPartnerUserStream(currentUserId)
      .handleError((error) {
        print('❌ Real-time partner user error: $error');
        return null;
      });
});

// Real-time current user provider
final realTimeCurrentUserProvider = StreamProvider<UserModel?>((ref) {
  final currentUserId = ref.watch(authControllerProvider.notifier).currentUserId;
  
  if (currentUserId == null) {
    return Stream.value(null);
  }

  return FirebaseService.usersCollection
      .doc(currentUserId)
      .snapshots()
      .map((snapshot) {
        if (!snapshot.exists) return null;
        
        final data = snapshot.data() as Map<String, dynamic>;
        return UserModel.fromMap(data, snapshot.id);
      })
      .handleError((error) {
        print('❌ Real-time current user error: $error');
        return null;
      });
});