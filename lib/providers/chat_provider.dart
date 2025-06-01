import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onlyus/core/services/cache_service.dart';
import '../core/services/chat_service.dart';
import '../models/message_model.dart';
import 'auth_provider.dart';

// Chat State classes
abstract class ChatState {}

class ChatInitial extends ChatState {}

class ChatLoading extends ChatState {}

// ADD: New cached chat states
abstract class CachedChatState {}

class CachedChatInitial extends CachedChatState {}

class CachedChatLoading extends CachedChatState {
  final List<MessageModel> cachedMessages;
  CachedChatLoading({this.cachedMessages = const []});
}

class CachedChatLoaded extends CachedChatState {
  final List<MessageModel> messages;
  final String chatId;
  final bool isConnected;
  final bool isFromCache;

  CachedChatLoaded({
    required this.messages,
    required this.chatId,
    this.isConnected = true,
    this.isFromCache = false,
  });

  CachedChatLoaded copyWith({
    List<MessageModel>? messages,
    String? chatId,
    bool? isConnected,
    bool? isFromCache,
  }) {
    return CachedChatLoaded(
      messages: messages ?? this.messages,
      chatId: chatId ?? this.chatId,
      isConnected: isConnected ?? this.isConnected,
      isFromCache: isFromCache ?? this.isFromCache,
    );
  }
}



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
      print('🔍 ChatController: Starting chat initialization...');

      // Check authentication
      final currentUserId =
          _ref.read(authControllerProvider.notifier).currentUserId;
      if (currentUserId == null) {
        print('❌ ChatController: User not authenticated');
        state = ChatError('Please log in to continue');
        return;
      }

      print('✅ ChatController: User authenticated: $currentUserId');

      // Initialize chat with retry logic
      final chatId = await _initializeChatWithRetry();

      if (chatId == null) {
        print('⚠️ ChatController: No chat available, showing empty state');
        // Show empty state for better UX
        state = ChatLoaded(messages: [], chatId: '', isConnected: false);
        return;
      }

      _currentChatId = chatId;
      print('✅ ChatController: Chat initialized with ID: $chatId');
      
      await _setupMessageStream(chatId);
    } catch (e) {
      print('❌ ChatController: Error initializing chat: $e');
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
        print('🔍 ChatController: Chat initialization attempt ${attempt + 1}/$maxRetries');
        
        final chatId = await _chatService.initializeChatWithFallback();
        
        if (chatId != null) {
          print('✅ ChatController: Chat initialized successfully on attempt ${attempt + 1}');
          return chatId;
        }
        
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
        }
      } catch (e) {
        print('❌ ChatController: Chat initialization attempt ${attempt + 1} failed: $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
        }
      }
    }
    
    print('❌ ChatController: All chat initialization attempts failed');
    return null;
  }

  Future<void> _setupMessageStream(String chatId) async {
    try {
      print('📡 ChatController: Setting up message stream for chat: $chatId');
      
      // Cancel any existing subscription
      await _messagesSubscription?.cancel();

      // Setup new stream with enhanced error handling
      _messagesSubscription = _chatService
          .getMessagesStream(chatId: chatId)
          .listen(
            (messages) {
              print('✅ ChatController: Received ${messages.length} messages for real-time update');

              // Always update state with new messages for real-time updates
              final currentState = state;

              if (currentState is ChatSendingMessage) {
                // Check if our pending message was confirmed
                final messageTexts = messages
                    .map((m) => m.message.toLowerCase().trim())
                    .toList();
                final pendingText = currentState.pendingMessage.toLowerCase().trim();

                // If we find our pending message, switch to loaded state
                if (messageTexts.contains(pendingText)) {
                  print('✅ ChatController: Pending message confirmed, switching to loaded state');
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
              print('❌ ChatController: Messages stream error: $error');

              // Handle different types of errors
              final errorString = error.toString().toLowerCase();

              if (errorString.contains('failed-precondition') ||
                  errorString.contains('requires an index') ||
                  errorString.contains('index')) {
                print('⚠️ ChatController: Firestore index error - using cached messages');

                // Show cached messages with warning
                final cachedMessages = _getCachedMessages();
                state = ChatLoaded(
                  messages: cachedMessages,
                  chatId: chatId,
                  isConnected: false,
                );
                
                // Try to refresh the stream with a simpler query
                Timer(const Duration(seconds: 2), () {
                  _chatService.refreshMessagesStream(chatId: chatId);
                });
                
                return; // Don't retry for index errors immediately
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
          
      print('✅ ChatController: Message stream setup completed');
    } catch (e) {
      print('❌ ChatController: Error setting up message stream: $e');
      throw e;
    }
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    try {
      print('📤 ChatController: Sending message: ${message.trim()}');
      
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
        print('❌ ChatController: Failed to send message');
        // Revert to previous state on failure
        state = ChatLoaded(
          messages: currentMessages,
          chatId: chatId,
          isConnected: false,
        );

        throw Exception('Failed to send message');
      }

      print('✅ ChatController: Message sent successfully');
      // Don't manually update state here - let the real-time stream handle it
      // The stream will automatically update when the message is confirmed from Firebase
    } catch (e) {
      print('❌ ChatController: Error sending message: $e');

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
      print('📤 ChatController: Sending image message');
      
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

      print('✅ ChatController: Image message sent successfully');
      // Real-time stream will handle the update
    } catch (e) {
      print('❌ ChatController: Error sending image: $e');
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
      print('❌ ChatController: Error updating typing status: $e');
      // Don't throw here as it's not critical
    }
  }

  Future<void> markMessagesAsRead() async {
    try {
      await _chatService.markMessagesAsReadEnhanced(chatId: _currentChatId);
    } catch (e) {
      print('❌ ChatController: Error marking messages as read: $e');
      // Don't throw here as it's not critical
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _chatService.deleteMessage(messageId);
      // Real-time stream will handle the update
    } catch (e) {
      print('❌ ChatController: Error deleting message: $e');
      rethrow;
    }
  }

  void retry() {
    print('🔄 ChatController: Manual retry triggered');
    _retryCount = 0;
    _retryTimer?.cancel();
    _initializeChat();
  }

  // NEW: Force refresh chat and messages
  Future<void> refresh() async {
    print('🔄 ChatController: Force refresh triggered');
    try {
      if (_currentChatId != null) {
        await _chatService.refreshMessagesStream(chatId: _currentChatId);
      } else {
        await _initializeChat();
      }
    } catch (e) {
      print('❌ ChatController: Error during refresh: $e');
    }
  }

  void _scheduleRetry() {
    if (_retryCount < maxRetries) {
      _retryCount++;
      _retryTimer?.cancel();

      final delay = Duration(seconds: _retryCount * 2);
      print('🔄 ChatController: Scheduling retry in ${delay.inSeconds} seconds (attempt $_retryCount)');

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
    print('💾 ChatController: Cached ${messages.length} messages for chat $chatId');
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

final cachedChatControllerProvider = StateNotifierProvider<CachedChatController, CachedChatState>(
  (ref) {
    return CachedChatController(
      ChatService.instance, 
      CacheService.instance,
      ref,
    );
  },
);
// ADD: Helper provider to check data source
final chatDataSourceProvider = Provider<String>((ref) {
  final chatState = ref.watch(cachedChatControllerProvider);
  
  if (chatState is CachedChatLoaded) {
    return chatState.isFromCache ? 'cache' : 'live';
  }
  
  return 'unknown';
});

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

// NEW: Provider for chat service status (useful for debugging)
final chatServiceStatusProvider = Provider<Map<String, dynamic>>((ref) {
  return ChatService.instance.getServiceStatus();
});




class CachedChatSendingMessage extends CachedChatState {
  final List<MessageModel> messages;
  final String chatId;
  final String pendingMessage;

  CachedChatSendingMessage({
    required this.messages,
    required this.chatId,
    required this.pendingMessage,
  });
}

class CachedChatError extends CachedChatState {
  final String message;
  final List<MessageModel> cachedMessages;

  CachedChatError(this.message, {this.cachedMessages = const []});
}

// ADD: Cached Chat Controller
class CachedChatController extends StateNotifier<CachedChatState> {
  final ChatService _chatService;
  final CacheService _cacheService;
  final Ref _ref;
  
  StreamSubscription<List<MessageModel>>? _messagesSubscription;
  String? _currentChatId;
  List<MessageModel> _lastKnownMessages = [];
  bool _hasInitialCache = false;

  CachedChatController(this._chatService, this._cacheService, this._ref) 
      : super(CachedChatInitial()) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Step 1: Load cached messages immediately
      await _loadCachedMessages();
      
      // Step 2: Initialize chat and setup real-time listeners
      await _initializeChat();
    } catch (e) {
      print('❌ CachedChatController: Error initializing: $e');
      state = CachedChatError(
        'Failed to load chat',
        cachedMessages: _lastKnownMessages,
      );
    }
  }

  Future<void> _loadCachedMessages() async {
    try {
      // Try to get chat ID from last session
      final lastChatId = _chatService.activeChatId;
      
      if (lastChatId != null) {
        final cachedMessages = _cacheService.getCachedMessages(lastChatId);
        
        if (cachedMessages.isNotEmpty) {
          _lastKnownMessages = cachedMessages;
          _currentChatId = lastChatId;
          _hasInitialCache = true;
          
          state = CachedChatLoaded(
            messages: cachedMessages,
            chatId: lastChatId,
            isConnected: false,
            isFromCache: true,
          );
          
          print('✅ Loaded ${cachedMessages.length} cached messages for instant UI');
          return;
        }
      }
      
      state = CachedChatLoading();
    } catch (e) {
      print('❌ Error loading cached messages: $e');
      state = CachedChatLoading();
    }
  }

  Future<void> _initializeChat() async {
    try {
      final currentUserId = _ref.read(authControllerProvider.notifier).currentUserId;
      if (currentUserId == null) {
        state = CachedChatError('Please log in to continue');
        return;
      }

      if (!_hasInitialCache) {
        state = CachedChatLoading();
      }

      final chatId = await _chatService.initializeChatWithFallback();

      if (chatId == null) {
        if (_hasInitialCache) {
          state = CachedChatLoaded(
            messages: _lastKnownMessages,
            chatId: _currentChatId ?? '',
            isConnected: false,
            isFromCache: true,
          );
        } else {
          state = CachedChatLoaded(
            messages: [],
            chatId: '',
            isConnected: false,
          );
        }
        return;
      }

      _currentChatId = chatId;
      await _setupMessageStream(chatId);
    } catch (e) {
      print('❌ CachedChatController: Error initializing chat: $e');
      state = CachedChatLoaded(
        messages: _lastKnownMessages,
        chatId: _currentChatId ?? '',
        isConnected: false,
        isFromCache: true,
      );
    }
  }

  Future<void> _setupMessageStream(String chatId) async {
    try {
      await _messagesSubscription?.cancel();

      _messagesSubscription = _chatService
          .getMessagesStream(chatId: chatId)
          .listen(
            (messages) => _handleMessagesUpdate(messages, chatId),
            onError: (error) => _handleStreamError(error, chatId),
          );
    } catch (e) {
      print('❌ CachedChatController: Error setting up message stream: $e');
    }
  }

  void _handleMessagesUpdate(List<MessageModel> messages, String chatId) {
    try {
      _lastKnownMessages = messages;
      
      final currentState = state;
      
      if (currentState is CachedChatSendingMessage) {
        final messageTexts = messages
            .map((m) => m.message.toLowerCase().trim())
            .toList();
        final pendingText = currentState.pendingMessage.toLowerCase().trim();

        if (messageTexts.contains(pendingText)) {
          state = CachedChatLoaded(
            messages: messages,
            chatId: chatId,
            isConnected: true,
            isFromCache: false,
          );
        } else {
          state = CachedChatSendingMessage(
            messages: messages,
            chatId: chatId,
            pendingMessage: currentState.pendingMessage,
          );
        }
      } else {
        state = CachedChatLoaded(
          messages: messages,
          chatId: chatId,
          isConnected: true,
          isFromCache: false,
        );
      }

      // Cache messages asynchronously
      _cacheMessagesAsync(chatId, messages);
    } catch (e) {
      print('❌ CachedChatController: Error handling messages update: $e');
    }
  }

  void _handleStreamError(dynamic error, String chatId) {
    print('❌ CachedChatController: Messages stream error: $error');

    final cachedMessages = _cacheService.getCachedMessages(chatId);
    
    state = CachedChatLoaded(
      messages: cachedMessages.isNotEmpty ? cachedMessages : _lastKnownMessages,
      chatId: chatId,
      isConnected: false,
      isFromCache: true,
    );
  }

  void _cacheMessagesAsync(String chatId, List<MessageModel> messages) {
    Future.microtask(() async {
      try {
        await _cacheService.cacheMessages(chatId, messages);
      } catch (e) {
        print('❌ Error caching messages async: $e');
      }
    });
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    try {
      final currentState = state;
      String chatId = _currentChatId ?? '';
      List<MessageModel> currentMessages = _lastKnownMessages;

      if (currentState is CachedChatLoaded) {
        currentMessages = currentState.messages;
        chatId = currentState.chatId;
      }

      // Show optimistic UI immediately
      state = CachedChatSendingMessage(
        messages: currentMessages,
        chatId: chatId,
        pendingMessage: message.trim(),
      );

      // Send message to server
      final success = await _chatService.sendTextMessage(
        message: message.trim(),
        chatId: chatId.isNotEmpty ? chatId : null,
      );

      if (!success) {
        state = CachedChatLoaded(
          messages: currentMessages,
          chatId: chatId,
          isConnected: false,
          isFromCache: false,
        );
        throw Exception('Failed to send message');
      }
    } catch (e) {
      print('❌ CachedChatController: Error sending message: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    super.dispose();
  }
}