import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/services/firebase_service.dart';
import '../core/services/chat_service.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  List<FavoriteMessage> _favoriteMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadFavoriteMessages();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadFavoriteMessages() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final currentUserId = ref.read(authControllerProvider.notifier).currentUserId;
      if (currentUserId == null) {
        setState(() {
          _favoriteMessages = [];
          _isLoading = false;
        });
        return;
      }

      // Get all chats where user is participant
      final chatsQuery = await FirebaseService.chatsCollection
          .where('participants', arrayContains: currentUserId)
          .get();

      List<FavoriteMessage> favoriteMessages = [];

      // For each chat, get favorited messages
      for (final chatDoc in chatsQuery.docs) {
        final chatId = chatDoc.id;
        final chatData = chatDoc.data();
        
        try {
          // Get favorited messages for this chat
          final messagesQuery = await FirebaseService.chatsCollection
              .doc(chatId)
              .collection('messages')
              .where('favoritedBy', arrayContains: currentUserId)
              .orderBy('timestamp', descending: true)
              .get();

          // Get partner info for this chat
          final participants = List<String>.from(chatData['participants'] ?? []);
          final partnerId = participants.firstWhere(
            (id) => id != currentUserId,
            orElse: () => '',
          );

          String partnerName = 'Unknown';
          String? partnerPhotoUrl;

          if (partnerId.isNotEmpty) {
            final partnerDoc = await FirebaseService.usersCollection
                .doc(partnerId)
                .get();
            
            if (partnerDoc.exists) {
              final partnerData = partnerDoc.data() as Map<String, dynamic>;
              partnerName = partnerData['displayName'] ?? 'Unknown';
              partnerPhotoUrl = partnerData['photoURL'];
            }
          }

          // Process each favorited message
          for (final messageDoc in messagesQuery.docs) {
            final messageData = messageDoc.data();
            
            favoriteMessages.add(FavoriteMessage(
              messageId: messageDoc.id,
              chatId: chatId,
              message: messageData['message'] ?? '',
              messageType: messageData['type'] ?? 'text',
              imageUrl: messageData['imageUrl'],
              timestamp: (messageData['timestamp'] as Timestamp).toDate(),
              senderId: messageData['senderId'] ?? '',
              senderName: messageData['senderName'] ?? 'Unknown',
              partnerName: partnerName,
              partnerPhotoUrl: partnerPhotoUrl,
              isFromCurrentUser: messageData['senderId'] == currentUserId,
            ));
          }
        } catch (e) {
          print('❌ Error loading favorited messages for chat $chatId: $e');
        }
      }

      // Sort all messages by timestamp (newest first)
      favoriteMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _favoriteMessages = favoriteMessages;
        _isLoading = false;
      });

      _animationController.forward();
    } catch (e) {
      print('❌ Error loading favorite messages: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFavorite(FavoriteMessage favoriteMessage) async {
    try {
      final success = await ChatService.instance.toggleMessageFavorite(
        favoriteMessage.chatId,
        favoriteMessage.messageId,
      );

      if (success) {
        // Remove from local list
        setState(() {
          _favoriteMessages.removeWhere(
            (msg) => msg.messageId == favoriteMessage.messageId
          );
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('💔 Removed from favorites'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error removing favorite message: $e');
    }
  }

  void _copyMessage(String message) {
    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.favorite, color: Colors.white),
            SizedBox(width: 8),
            Text('Message copied with love 💕'),
          ],
        ),
        backgroundColor: const Color(0xFFFF8A95),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inDays == 0) {
      // Today: show time
      final hour = time.hour;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFCE93D8),
                const Color(0xFFFF8A95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Favorite Messages',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadFavoriteMessages,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey[50]!, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFFFF8A95),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading your favorite messages...',
                      style: TextStyle(
                        color: Color(0xFFCE93D8),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            : _favoriteMessages.isEmpty
                ? _buildEmptyState()
                : _buildFavoritesList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFCE93D8).withOpacity(0.3),
                  const Color(0xFFFF8A95).withOpacity(0.3),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_border,
              size: 60,
              color: Color(0xFFCE93D8),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '💕 No Favorite Messages Yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Long press any message and tap the heart\nto add it to your favorites! 💖',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[600],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A95),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: const Text(
              '💕 Back to Chat',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesList() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _favoriteMessages.length,
          itemBuilder: (context, index) {
            final favoriteMessage = _favoriteMessages[index];
            final animation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: _animationController,
              curve: Interval(
                index * 0.1,
                1.0,
                curve: Curves.easeOut,
              ),
            ));

            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.5),
                  end: Offset.zero,
                ).animate(animation),
                child: _buildFavoriteMessageTile(favoriteMessage),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFavoriteMessageTile(FavoriteMessage favoriteMessage) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            const Color(0xFFCE93D8).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCE93D8).withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFCE93D8).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with partner info and favorite heart
            Row(
              children: [
                // Partner avatar
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFCE93D8).withOpacity(0.2),
                  backgroundImage: favoriteMessage.partnerPhotoUrl != null
                      ? NetworkImage(favoriteMessage.partnerPhotoUrl!)
                      : null,
                  child: favoriteMessage.partnerPhotoUrl == null
                      ? Text(
                          favoriteMessage.partnerName[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFCE93D8),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                
                // Sender info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        favoriteMessage.isFromCurrentUser 
                            ? 'You' 
                            : favoriteMessage.partnerName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        _formatMessageTime(favoriteMessage.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Actions
                Row(
                  children: [
                    // Favorite heart
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFF8A95),
                            const Color(0xFFCE93D8),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // More options
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                      onSelected: (value) {
                        if (value == 'copy') {
                          _copyMessage(favoriteMessage.message);
                        } else if (value == 'remove') {
                          _showRemoveConfirmation(favoriteMessage);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'copy',
                          child: ListTile(
                            leading: Icon(Icons.copy, color: Color(0xFFCE93D8)),
                            title: Text('Copy Message'),
                            dense: true,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: ListTile(
                            leading: Icon(Icons.heart_broken, color: Colors.red),
                            title: Text('Remove Favorite'),
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Message content
            if (favoriteMessage.messageType == 'image')
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[200],
                ),
                child: favoriteMessage.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          favoriteMessage.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported,
                                    color: Colors.grey[400],
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Image not available',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    : Container(
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.image,
                          color: Colors.grey[400],
                          size: 48,
                        ),
                      ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: favoriteMessage.isFromCurrentUser
                      ? const Color(0xFFCE93D8).withOpacity(0.1)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  favoriteMessage.message,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[800],
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showRemoveConfirmation(FavoriteMessage favoriteMessage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('💔 Remove Favorite'),
        content: const Text(
          'Remove this message from your favorites?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeFavorite(favoriteMessage);
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class FavoriteMessage {
  final String messageId;
  final String chatId;
  final String message;
  final String messageType;
  final String? imageUrl;
  final DateTime timestamp;
  final String senderId;
  final String senderName;
  final String partnerName;
  final String? partnerPhotoUrl;
  final bool isFromCurrentUser;

  FavoriteMessage({
    required this.messageId,
    required this.chatId,
    required this.message,
    required this.messageType,
    this.imageUrl,
    required this.timestamp,
    required this.senderId,
    required this.senderName,
    required this.partnerName,
    this.partnerPhotoUrl,
    required this.isFromCurrentUser,
  });
}