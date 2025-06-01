import 'dart:async';
import 'dart:convert';
import 'package:onlyus/models/message_model.dart';
import 'package:onlyus/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static CacheService? _instance;
  static CacheService get instance => _instance ??= CacheService._();
  CacheService._();

  SharedPreferences? _prefs;

  // Cache keys
  static const String _currentUserKey = 'cached_current_user';
  static const String _partnerUserKey = 'cached_partner_user';
  static const String _messagesPrefix = 'cached_messages_';
  static const String _chatPrefix = 'cached_chat_';
  static const String _userPresencePrefix = 'cached_presence_';
  static const String _lastSyncPrefix = 'last_sync_';
  static const String _userPreferencesKey = 'cached_user_preferences';
  static const String _connectionHistoryKey = 'cached_connection_history';
  static const String _favoriteChatsKey = 'cached_favorite_chats';
  static const String _favoritedMessagesKey = 'cached_favorited_messages';

  // Cache expiry times (in minutes)
  static const int _userCacheExpiry = 30; // 30 minutes
  static const int _messagesCacheExpiry = 5; // 5 minutes for messages
  static const int _presenceCacheExpiry = 2; // 2 minutes for presence
  static const int _preferencesCacheExpiry = 60; // 1 hour

  // Memory cache for frequently accessed data
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _memoryCacheTimestamps = {};

  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      print('✅ Cache service initialized');
    } catch (e) {
      print('❌ Error initializing cache service: $e');
    }
  }

  SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('Cache service not initialized');
    }
    return _prefs!;
  }

  // ============================================================================
  // USER CACHING
  // ============================================================================

  /// Cache current user with expiry
  Future<void> cacheCurrentUser(UserModel user) async {
    try {
      final userData = {
        'user': user.toMap(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(_currentUserKey, jsonEncode(userData));

      // Also cache in memory for immediate access
      _memoryCache['current_user'] = user;
      _memoryCacheTimestamps['current_user'] = DateTime.now();

      print('✅ Current user cached');
    } catch (e) {
      print('❌ Error caching current user: $e');
    }
  }

  /// Get cached current user
  UserModel? getCachedCurrentUser() {
    try {
      // Check memory cache first
      if (_isMemoryCacheValid('current_user', _userCacheExpiry)) {
        return _memoryCache['current_user'] as UserModel?;
      }

      final cachedData = prefs.getString(_currentUserKey);
      if (cachedData == null) return null;

      final userData = jsonDecode(cachedData) as Map<String, dynamic>;
      final timestamp = userData['timestamp'] as int;

      if (_isCacheExpired(timestamp, _userCacheExpiry)) {
        _clearCache(_currentUserKey);
        return null;
      }

      final user = UserModel.fromMap(
        userData['user'] as Map<String, dynamic>,
        userData['user']['uid'] as String,
      );

      // Update memory cache
      _memoryCache['current_user'] = user;
      _memoryCacheTimestamps['current_user'] = DateTime.now();

      return user;
    } catch (e) {
      print('❌ Error getting cached current user: $e');
      return null;
    }
  }

  /// Cache partner user
  Future<void> cachePartnerUser(UserModel user) async {
    try {
      final userData = {
        'user': user.toMap(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(_partnerUserKey, jsonEncode(userData));

      // Memory cache
      _memoryCache['partner_user'] = user;
      _memoryCacheTimestamps['partner_user'] = DateTime.now();

      print('✅ Partner user cached');
    } catch (e) {
      print('❌ Error caching partner user: $e');
    }
  }

  /// Get cached partner user
  UserModel? getCachedPartnerUser() {
    try {
      // Check memory cache first
      if (_isMemoryCacheValid('partner_user', _userCacheExpiry)) {
        return _memoryCache['partner_user'] as UserModel?;
      }

      final cachedData = prefs.getString(_partnerUserKey);
      if (cachedData == null) return null;

      final userData = jsonDecode(cachedData) as Map<String, dynamic>;
      final timestamp = userData['timestamp'] as int;

      if (_isCacheExpired(timestamp, _userCacheExpiry)) {
        _clearCache(_partnerUserKey);
        return null;
      }

      final user = UserModel.fromMap(
        userData['user'] as Map<String, dynamic>,
        userData['user']['uid'] as String,
      );

      // Update memory cache
      _memoryCache['partner_user'] = user;
      _memoryCacheTimestamps['partner_user'] = DateTime.now();

      return user;
    } catch (e) {
      print('❌ Error getting cached partner user: $e');
      return null;
    }
  }

  // ============================================================================
  // MESSAGES CACHING
  // ============================================================================

  /// Cache messages for a chat
  Future<void> cacheMessages(String chatId, List<MessageModel> messages) async {
    try {
      final messagesData = {
        'messages': messages.map((m) => m.toMap()).toList(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'count': messages.length,
      };

      await prefs.setString(
        '$_messagesPrefix$chatId',
        jsonEncode(messagesData),
      );

      // Memory cache for current chat
      _memoryCache['messages_$chatId'] = messages;
      _memoryCacheTimestamps['messages_$chatId'] = DateTime.now();

      print('✅ Cached ${messages.length} messages for chat: $chatId');
    } catch (e) {
      print('❌ Error caching messages: $e');
    }
  }

  /// Get cached messages
  List<MessageModel> getCachedMessages(String chatId) {
    try {
      // Check memory cache first
      if (_isMemoryCacheValid('messages_$chatId', _messagesCacheExpiry)) {
        return List<MessageModel>.from(_memoryCache['messages_$chatId'] ?? []);
      }

      final cachedData = prefs.getString('$_messagesPrefix$chatId');
      if (cachedData == null) return [];

      final messagesData = jsonDecode(cachedData) as Map<String, dynamic>;
      final timestamp = messagesData['timestamp'] as int;

      if (_isCacheExpired(timestamp, _messagesCacheExpiry)) {
        _clearCache('$_messagesPrefix$chatId');
        return [];
      }

      final messagesList = messagesData['messages'] as List<dynamic>;
      final messages =
          messagesList
              .map(
                (m) => MessageModel.fromMap(
                  m as Map<String, dynamic>,
                  (m)['id'] as String,
                ),
              )
              .toList();

      // Update memory cache
      _memoryCache['messages_$chatId'] = messages;
      _memoryCacheTimestamps['messages_$chatId'] = DateTime.now();

      return messages;
    } catch (e) {
      print('❌ Error getting cached messages: $e');
      return [];
    }
  }

  /// Add new message to cache (for real-time updates)
  Future<void> addMessageToCache(String chatId, MessageModel message) async {
    try {
      final cachedMessages = getCachedMessages(chatId);

      // Check if message already exists (prevent duplicates)
      final existingIndex = cachedMessages.indexWhere(
        (m) => m.id == message.id,
      );

      if (existingIndex != -1) {
        // Update existing message
        cachedMessages[existingIndex] = message;
      } else {
        // Add new message at the beginning (since messages are ordered by timestamp desc)
        cachedMessages.insert(0, message);
      }

      // Limit cache size (keep only latest 100 messages)
      if (cachedMessages.length > 100) {
        cachedMessages.removeRange(100, cachedMessages.length);
      }

      await cacheMessages(chatId, cachedMessages);
    } catch (e) {
      print('❌ Error adding message to cache: $e');
    }
  }

  /// Update message in cache (for read receipts, etc.)
  Future<void> updateMessageInCache(
    String chatId,
    MessageModel updatedMessage,
  ) async {
    try {
      final cachedMessages = getCachedMessages(chatId);
      final index = cachedMessages.indexWhere((m) => m.id == updatedMessage.id);

      if (index != -1) {
        cachedMessages[index] = updatedMessage;
        await cacheMessages(chatId, cachedMessages);

        print('✅ Updated message in cache: ${updatedMessage.id}');
      }
    } catch (e) {
      print('❌ Error updating message in cache: $e');
    }
  }

  // ============================================================================
  // PRESENCE CACHING
  // ============================================================================

  /// Cache user presence
  Future<void> cacheUserPresence(
    String userId,
    Map<String, dynamic> presence,
  ) async {
    try {
      final presenceData = {
        'presence': presence,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(
        '$_userPresencePrefix$userId',
        jsonEncode(presenceData),
      );

      // Memory cache
      _memoryCache['presence_$userId'] = presence;
      _memoryCacheTimestamps['presence_$userId'] = DateTime.now();
    } catch (e) {
      print('❌ Error caching user presence: $e');
    }
  }

  /// Get cached user presence
  Map<String, dynamic>? getCachedUserPresence(String userId) {
    try {
      // Check memory cache first
      if (_isMemoryCacheValid('presence_$userId', _presenceCacheExpiry)) {
        return Map<String, dynamic>.from(
          _memoryCache['presence_$userId'] ?? {},
        );
      }

      final cachedData = prefs.getString('$_userPresencePrefix$userId');
      if (cachedData == null) return null;

      final presenceData = jsonDecode(cachedData) as Map<String, dynamic>;
      final timestamp = presenceData['timestamp'] as int;

      if (_isCacheExpired(timestamp, _presenceCacheExpiry)) {
        _clearCache('$_userPresencePrefix$userId');
        return null;
      }

      final presence = Map<String, dynamic>.from(presenceData['presence']);

      // Update memory cache
      _memoryCache['presence_$userId'] = presence;
      _memoryCacheTimestamps['presence_$userId'] = DateTime.now();

      return presence;
    } catch (e) {
      print('❌ Error getting cached user presence: $e');
      return null;
    }
  }

  // ============================================================================
  // USER PREFERENCES CACHING
  // ============================================================================

  /// Cache user preferences
  Future<void> cacheUserPreferences(Map<String, dynamic> preferences) async {
    try {
      final preferencesData = {
        'preferences': preferences,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(_userPreferencesKey, jsonEncode(preferencesData));

      // Memory cache
      _memoryCache['user_preferences'] = preferences;
      _memoryCacheTimestamps['user_preferences'] = DateTime.now();

      print('✅ User preferences cached');
    } catch (e) {
      print('❌ Error caching user preferences: $e');
    }
  }

  /// Get cached user preferences
  Map<String, dynamic>? getCachedUserPreferences() {
    try {
      // Check memory cache first
      if (_isMemoryCacheValid('user_preferences', _preferencesCacheExpiry)) {
        return Map<String, dynamic>.from(
          _memoryCache['user_preferences'] ?? {},
        );
      }

      final cachedData = prefs.getString(_userPreferencesKey);
      if (cachedData == null) return null;

      final preferencesData = jsonDecode(cachedData) as Map<String, dynamic>;
      final timestamp = preferencesData['timestamp'] as int;

      if (_isCacheExpired(timestamp, _preferencesCacheExpiry)) {
        _clearCache(_userPreferencesKey);
        return null;
      }

      final preferences = Map<String, dynamic>.from(
        preferencesData['preferences'],
      );

      // Update memory cache
      _memoryCache['user_preferences'] = preferences;
      _memoryCacheTimestamps['user_preferences'] = DateTime.now();

      return preferences;
    } catch (e) {
      print('❌ Error getting cached user preferences: $e');
      return null;
    }
  }

  // ============================================================================
  // CACHE UTILITIES
  // ============================================================================

  /// Check if cache is expired
  bool _isCacheExpired(int timestamp, int expiryMinutes) {
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final expiryTime = cacheTime.add(Duration(minutes: expiryMinutes));
    return DateTime.now().isAfter(expiryTime);
  }

  /// Check if memory cache is valid
  bool _isMemoryCacheValid(String key, int expiryMinutes) {
    final timestamp = _memoryCacheTimestamps[key];
    if (timestamp == null || _memoryCache[key] == null) return false;

    final expiryTime = timestamp.add(Duration(minutes: expiryMinutes));
    return DateTime.now().isBefore(expiryTime);
  }

  /// Clear specific cache
  Future<void> _clearCache(String key) async {
    try {
      await prefs.remove(key);

      // Also clear from memory cache
      final memoryKey = key.replaceAll('cached_', '').replaceAll('_', '');
      _memoryCache.remove(memoryKey);
      _memoryCacheTimestamps.remove(memoryKey);
    } catch (e) {
      print('❌ Error clearing cache: $e');
    }
  }

  /// Clear all user-related caches (useful on logout)
  Future<void> clearUserCaches() async {
    try {
      await prefs.remove(_currentUserKey);
      await prefs.remove(_partnerUserKey);
      await prefs.remove(_userPreferencesKey);

      // Clear memory cache
      _memoryCache.clear();
      _memoryCacheTimestamps.clear();

      print('✅ User caches cleared');
    } catch (e) {
      print('❌ Error clearing user caches: $e');
    }
  }

  /// Clear expired caches
  Future<void> clearExpiredCaches() async {
    try {
      final keys = prefs.getKeys();
      final expiredKeys = <String>[];

      for (final key in keys) {
        if (key.startsWith('cached_')) {
          final cachedData = prefs.getString(key);
          if (cachedData != null) {
            try {
              final data = jsonDecode(cachedData) as Map<String, dynamic>;
              final timestamp = data['timestamp'] as int?;

              if (timestamp != null && _isCacheExpired(timestamp, 60)) {
                // 1 hour general expiry
                expiredKeys.add(key);
              }
            } catch (e) {
              // Invalid cache format, mark for deletion
              expiredKeys.add(key);
            }
          }
        }
      }

      // Remove expired caches
      for (final key in expiredKeys) {
        await prefs.remove(key);
      }

      if (expiredKeys.isNotEmpty) {
        print('✅ Cleared ${expiredKeys.length} expired caches');
      }
    } catch (e) {
      print('❌ Error clearing expired caches: $e');
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    try {
      final keys = prefs.getKeys();
      final cacheKeys = keys.where((k) => k.startsWith('cached_')).toList();

      int totalSize = 0;
      final cacheInfo = <String, Map<String, dynamic>>{};

      for (final key in cacheKeys) {
        final data = prefs.getString(key);
        if (data != null) {
          totalSize += data.length;

          try {
            final parsed = jsonDecode(data) as Map<String, dynamic>;
            final timestamp = parsed['timestamp'] as int?;

            cacheInfo[key] = {
              'size': data.length,
              'timestamp': timestamp,
              'expired':
                  timestamp != null ? _isCacheExpired(timestamp, 60) : true,
            };
          } catch (e) {
            cacheInfo[key] = {
              'size': data.length,
              'timestamp': null,
              'expired': true,
              'error': e.toString(),
            };
          }
        }
      }

      return {
        'totalCaches': cacheKeys.length,
        'totalSize': totalSize,
        'memoryCacheSize': _memoryCache.length,
        'cacheDetails': cacheInfo,
      };
    } catch (e) {
      print('❌ Error getting cache stats: $e');
      return {'error': e.toString()};
    }
  }

  /// Mark last sync time for incremental updates
  Future<void> markLastSync(String dataType) async {
    try {
      await prefs.setInt(
        '$_lastSyncPrefix$dataType',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print('❌ Error marking last sync: $e');
    }
  }

  /// Get last sync time
  DateTime? getLastSync(String dataType) {
    try {
      final timestamp = prefs.getInt('$_lastSyncPrefix$dataType');
      return timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : null;
    } catch (e) {
      print('❌ Error getting last sync: $e');
      return null;
    }
  }

  /// Cache favorite chats
  Future<void> cacheFavoriteChats(List<String> favoriteChats) async {
    try {
      final data = {
        'favoriteChats': favoriteChats,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(_favoriteChatsKey, jsonEncode(data));
      _memoryCache['favorite_chats'] = favoriteChats;
      _memoryCacheTimestamps['favorite_chats'] = DateTime.now();
    } catch (e) {
      print('❌ Error caching favorite chats: $e');
    }
  }

  /// Get cached favorite chats
  List<String> getCachedFavoriteChats() {
    try {
      if (_isMemoryCacheValid('favorite_chats', 30)) {
        return List<String>.from(_memoryCache['favorite_chats'] ?? []);
      }

      final cachedData = prefs.getString(_favoriteChatsKey);
      if (cachedData == null) return [];

      final data = jsonDecode(cachedData) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;

      if (_isCacheExpired(timestamp, 30)) {
        _clearCache(_favoriteChatsKey);
        return [];
      }

      final favoriteChats = List<String>.from(data['favoriteChats'] ?? []);

      _memoryCache['favorite_chats'] = favoriteChats;
      _memoryCacheTimestamps['favorite_chats'] = DateTime.now();

      return favoriteChats;
    } catch (e) {
      print('❌ Error getting cached favorite chats: $e');
      return [];
    }
  }

  /// Dispose and cleanup
  void dispose() {
    _memoryCache.clear();
    _memoryCacheTimestamps.clear();
  }
}
