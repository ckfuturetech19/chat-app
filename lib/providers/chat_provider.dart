import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/chat_service.dart';
import '../models/message_model.dart';
import 'auth_provider.dart';

// Chat State classes
abstract class ChatState {}

class ChatInitial extends ChatState {}

class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
  final List<MessageModel> messages;
  final String chatId;
  final bool isConnected;

  ChatLoaded({
    required this.messages,
    required this.chatId,
    this.isConnected = true,
  });

  ChatLoaded copyWith({
    List<MessageModel>? messages,
    String? chatId,
    bool? isConnected,
  }) {
    return ChatLoaded(
      messages: messages ?? this.messages,
      chatId: chatId ?? this.chatId,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class ChatSendingMessage extends ChatState {
  final List<MessageModel> messages;
  final String chatId;
  final String pendingMessage;

  ChatSendingMessage({
    required this.messages,
    required this.chatId,
    required this.pendingMessage,
  });
}

class ChatError extends ChatState {
  final String message;
  final List<MessageModel> cachedMessages;
  final String? chatId;

  ChatError(this.message, {this.cachedMessages = const [], this.chatId});
}

// Enhanced Chat Controller with Real-time fixes
class ChatController extends StateNotifier<ChatState> {
  final ChatService _chatService;
  final Ref _ref;
  StreamSubscription<List<MessageModel>>? _messagesSubscription;
  String? _currentChatId;
  Timer? _retryTimer;
  Timer? _typingTimer;
  int _retryCount = 0;
  static const int maxRetries = 3;

  ChatController(this._chatService, this._ref) : super(ChatInitial()) {
    _initializeChat();
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _retryTimer?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    try {
      state = ChatLoading();

      // Check authentication
      final currentUserId =
          _ref.read(authControllerProvider.notifier).currentUserId;
      if (currentUserId == null) {
        state = ChatError('Please log in to continue');
        return;
      }

      // Initialize chat with retry logic
      final chatId = await _initializeChatWithRetry();

      if (chatId == null) {
        // Show empty state for better UX
        state = ChatLoaded(messages: [], chatId: '', isConnected: false);
        return;
      }

      _currentChatId = chatId;
      await _setupMessageStream(chatId);
    } catch (e) {
      print('❌ Error initializing chat: $e');
      state = ChatError(
        'Failed to load chat. Please check your connection.',
        cachedMessages: _getCachedMessages(),
      );
      _scheduleRetry();
    }
  }

  Future<String?> _initializeChatWithRetry() async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final chatId = await _chatService.initializeChatWithFallback();
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
        }
      } catch (e) {
        print('❌ Chat initialization attempt ${attempt + 1} failed: $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
        }
      }
    }
    return null;
  }

  Future<void> _setupMessageStream(String chatId) async {
    try {
      // Cancel any existing subscription
      await _messagesSubscription?.cancel();

      // Setup new stream with enhanced error handling
      _messagesSubscription = _chatService
          .getMessagesStream(chatId: chatId)
          .listen(
            (messages) {
              print(
                '✅ Received ${messages.length} messages for real-time update',
              );

              // Always update state with new messages for real-time updates
              final currentState = state;

              if (currentState is ChatSendingMessage) {
                // Check if our pending message was confirmed
                final messageTexts =
                    messages
                        .map((m) => m.message.toLowerCase().trim())
                        .toList();
                final pendingText =
                    currentState.pendingMessage.toLowerCase().trim();

                // If we find our pending message, switch to loaded state
                if (messageTexts.contains(pendingText)) {
                  state = ChatLoaded(
                    messages: messages,
                    chatId: chatId,
                    isConnected: true,
                  );
                } else {
                  // Update messages but keep sending state
                  state = ChatSendingMessage(
                    messages: messages,
                    chatId: chatId,
                    pendingMessage: currentState.pendingMessage,
                  );
                }
              } else {
                // Normal message update
                state = ChatLoaded(
                  messages: messages,
                  chatId: chatId,
                  isConnected: true,
                );
              }

              // Cache messages for offline support
              _cacheMessages(chatId, messages);
            },
            onError: (error) {
              print('❌ Messages stream error: $error');

              // Handle different types of errors
              final errorString = error.toString().toLowerCase();

              if (errorString.contains('failed-precondition') ||
                  errorString.contains('requires an index') ||
                  errorString.contains('index')) {
                print(
                  '⚠️ Firestore index error - please create required indexes',
                );

                // Show cached messages with warning
                final cachedMessages = _getCachedMessages();
                state = ChatLoaded(
                  messages: cachedMessages,
                  chatId: chatId,
                  isConnected: false,
                );
                return; // Don't retry for index errors
              }

              // For other errors, show cached messages and retry
              final cachedMessages = _getCachedMessages();
              state = ChatLoaded(
                messages: cachedMessages,
                chatId: chatId,
                isConnected: false,
              );

              // Schedule retry for connection issues
              _scheduleRetry();
            },
          );
    } catch (e) {
      print('❌ Error setting up message stream: $e');
      throw e;
    }
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    try {
      final currentState = state;
      String chatId = _currentChatId ?? '';
      List<MessageModel> currentMessages = [];

      // Get current messages from state
      if (currentState is ChatLoaded) {
        currentMessages = currentState.messages;
        chatId = currentState.chatId;
      } else if (currentState is ChatSendingMessage) {
        currentMessages = currentState.messages;
        chatId = currentState.chatId;
      }

      // Show optimistic UI immediately
      state = ChatSendingMessage(
        messages: currentMessages,
        chatId: chatId,
        pendingMessage: message.trim(),
      );

      // Clear typing status immediately
      await updateTypingStatus(false);

      // Send message to Firebase
      final success = await _chatService.sendTextMessage(
        message: message.trim(),
        chatId: chatId.isNotEmpty ? chatId : null,
      );

      if (!success) {
        // Revert to previous state on failure
        state = ChatLoaded(
          messages: currentMessages,
          chatId: chatId,
          isConnected: false,
        );

        throw Exception('Failed to send message');
      }

      // Don't manually update state here - let the real-time stream handle it
      // The stream will automatically update when the message is confirmed from Firebase
    } catch (e) {
      print('❌ Error sending message: $e');

      // Revert to loaded state with error indication
      final currentState = state;
      if (currentState is ChatSendingMessage) {
        state = ChatLoaded(
          messages: currentState.messages,
          chatId: currentState.chatId,
          isConnected: false,
        );
      }

      rethrow; // Let UI handle the error
    }
  }

  Future<void> sendImageMessage(String imageUrl, {String? caption}) async {
    try {
      final currentState = state;
      String chatId = _currentChatId ?? '';
      List<MessageModel> currentMessages = [];

      if (currentState is ChatLoaded) {
        currentMessages = currentState.messages;
        chatId = currentState.chatId;
      }

      // Show sending state
      state = ChatSendingMessage(
        messages: currentMessages,
        chatId: chatId,
        pendingMessage: '📷 Photo',
      );

      final success = await _chatService.sendImageMessage(
        imageUrl: imageUrl,
        caption: caption,
        chatId: chatId.isNotEmpty ? chatId : null,
      );

      if (!success) {
        state = ChatLoaded(
          messages: currentMessages,
          chatId: chatId,
          isConnected: false,
        );
        throw Exception('Failed to send image');
      }

      // Real-time stream will handle the update
    } catch (e) {
      print('❌ Error sending image: $e');
      rethrow;
    }
  }

  Future<void> updateTypingStatus(bool isTyping) async {
    try {
      // Cancel previous typing timer
      _typingTimer?.cancel();

      await _chatService.updateTypingStatus(isTyping);

      // Auto-clear typing status after 3 seconds
      if (isTyping) {
        _typingTimer = Timer(const Duration(seconds: 3), () {
          updateTypingStatus(false);
        });
      }
    } catch (e) {
      print('❌ Error updating typing status: $e');
      // Don't throw here as it's not critical
    }
  }

  Future<void> markMessagesAsRead() async {
    try {
      await _chatService.markMessagesAsRead(chatId: _currentChatId);
    } catch (e) {
      print('❌ Error marking messages as read: $e');
      // Don't throw here as it's not critical
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _chatService.deleteMessage(messageId);
      // Real-time stream will handle the update
    } catch (e) {
      print('❌ Error deleting message: $e');
      rethrow;
    }
  }

  void retry() {
    _retryCount = 0;
    _retryTimer?.cancel();
    _initializeChat();
  }

  void _scheduleRetry() {
    if (_retryCount < maxRetries) {
      _retryCount++;
      _retryTimer?.cancel();

      final delay = Duration(seconds: _retryCount * 2);
      print(
        '🔄 Scheduling retry in ${delay.inSeconds} seconds (attempt $_retryCount)',
      );

      _retryTimer = Timer(delay, () {
        if (_currentChatId != null) {
          _setupMessageStream(_currentChatId!);
        } else {
          _initializeChat();
        }
      });
    }
  }

  void _cacheMessages(String chatId, List<MessageModel> messages) {
    // Cache messages for offline support
    _chatService.cacheMessages(chatId, messages);
    print('💾 Cached ${messages.length} messages for chat $chatId');
  }

  List<MessageModel> _getCachedMessages() {
    // Return cached messages from service
    return _chatService.getCachedMessages(chatId: _currentChatId);
  }

  String? get currentChatId => _currentChatId;

  bool get isConnected {
    final currentState = state;
    if (currentState is ChatLoaded) return currentState.isConnected;
    return false;
  }
}

// Enhanced Provider for Chat Controller
final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
  (ref) {
    return ChatController(ChatService.instance, ref);
  },
);

// Enhanced typing status provider with better real-time updates
final typingStatusProvider = StreamProvider.family<bool, String>((ref, userId) {
  final chatController = ref.watch(chatControllerProvider.notifier);
  final chatId = chatController.currentChatId;

  if (chatId == null || chatId.isEmpty) {
    return Stream.value(false);
  }

  return ChatService.instance
      .getChatStream(chatId: chatId)
      .map((chat) {
        if (chat == null) return false;
        return chat.typingUsers[userId] ?? false;
      })
      .distinct() // Only emit when typing status actually changes
      .handleError((error) {
        print('❌ Typing status stream error: $error');
        return false;
      });
});

// Provider for current chat ID
final currentChatIdProvider = Provider<String?>((ref) {
  final chatState = ref.watch(chatControllerProvider);

  if (chatState is ChatLoaded) return chatState.chatId;
  if (chatState is ChatSendingMessage) return chatState.chatId;
  return null;
});

// Provider for connection status
final chatConnectionStatusProvider = Provider<bool>((ref) {
  final chatState = ref.watch(chatControllerProvider);

  if (chatState is ChatLoaded) return chatState.isConnected;
  return false;
});

// Enhanced provider for unread message count
final unreadMessageCountProvider = FutureProvider<int>((ref) async {
  final chatController = ref.watch(chatControllerProvider.notifier);
  final chatId = chatController.currentChatId;

  if (chatId == null) return 0;

  try {
    return await ChatService.instance.getUnreadMessageCount(chatId: chatId);
  } catch (e) {
    print('❌ Error getting unread count: $e');
    return 0;
  }
});

// Provider for real-time message updates
final realTimeMessagesProvider =
    StreamProvider.family<List<MessageModel>, String>((ref, chatId) {
      if (chatId.isEmpty) return Stream.value([]);

      return ChatService.instance.getMessagesStream(chatId: chatId).handleError(
        (error) {
          print('❌ Real-time messages error: $error');
          return <MessageModel>[];
        },
      );
    });
