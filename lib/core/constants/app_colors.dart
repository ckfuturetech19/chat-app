import 'package:flutter/material.dart';

class AppColors {
  // Primary romantic colors
  static const Color primaryPink = Color(0xFFFFE4E6);
  static const Color primaryRose = Color(0xFFFECDD3);
  static const Color primaryDeepRose = Color(0xFFFB7185);
  
  // Secondary purple tones
  static const Color secondaryPurple = Color(0xFFF3E8FF);
  static const Color secondaryLavender = Color(0xFFDDD6FE);
  static const Color secondaryDeepPurple = Color(0xFFA78BFA);
  
  // Accent gold tones
  static const Color accentGold = Color(0xFFFEF3C7);
  static const Color accentYellow = Color(0xFFFDE68A);
  static const Color accentDeepGold = Color(0xFFF59E0B);
  
  // Neutral tones
  static const Color neutralCream = Color(0xFFFFFBEB);
  static const Color neutralIvory = Color(0xFFFEF7ED);
  static const Color neutralWarm = Color(0xFFFAF5F5);
  
  // Message bubble colors
  static const Color myMessageBubble = Color(0xFFF8BBD9);
  static const Color partnerMessageBubble = Color(0xFFE0E7FF);
  
  // Status colors
  static const Color online = Color(0xFF22C55E);
  static const Color offline = Color(0xFF94A3B8);
  static const Color typing = Color(0xFFFB7185);
  
  // Text colors
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);
  
  // Heart animation colors
  static const List<Color> heartColors = [
    Color(0xFFFF69B4),
    Color(0xFFFF1493),
    Color(0xFFFF6347),
    Color(0xFFFF69B4),
    Color(0xFFDA70D6),
  ];
  
  // Gradient combinations
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFBEB),
      Color(0xFFFFE4E6),
      Color(0xFFF3E8FF),
    ],
    stops: [0.0, 0.5, 1.0],
  );
  
  static const LinearGradient chatBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFFBEB),
      Color(0xFFFAF5F5),
    ],
  );
  
  static const LinearGradient myMessageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF8BBD9),
      Color(0xFFFB7185),
    ],
  );
  
  static const LinearGradient partnerMessageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE0E7FF),
      Color(0xFFA78BFA),
    ],
  );
  
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFB7185),
      Color(0xFFA78BFA),
    ],
  );
  
  static const LinearGradient heartGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF69B4),
      Color(0xFFFF1493),
    ],
  );
}