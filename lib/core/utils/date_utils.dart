import 'package:intl/intl.dart';
import 'package:onlyus/core/constants/app_strings.dart';

class AppDateUtils {
  // Private constructor to prevent instantiation
  AppDateUtils._();

  // Format message timestamp for display
  static String formatMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (messageDate == today) {
      // Today: show time only
      return DateFormat('h:mm a').format(dateTime);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(messageDate).inDays < 7) {
      // This week: show day name
      return DateFormat('EEE').format(dateTime);
    } else if (dateTime.year == now.year) {
      // This year: show month and day
      return DateFormat('MMM d').format(dateTime);
    } else {
      // Different year: show month, day, and year
      return DateFormat('MMM d, y').format(dateTime);
    }
  }

  // Format detailed timestamp for message info
  static String formatDetailedTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    final timeString = DateFormat('h:mm a').format(dateTime);
    
    if (messageDate == today) {
      return 'Today at $timeString';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday at $timeString';
    } else if (now.difference(messageDate).inDays < 7) {
      final dayName = DateFormat('EEEE').format(dateTime);
      return '$dayName at $timeString';
    } else {
      final dateString = DateFormat('MMMM d, y').format(dateTime);
      return '$dateString at $timeString';
    }
  }

  // Format date separator for chat
  static String formatDateSeparator(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (now.difference(messageDate).inDays < 7) {
      return DateFormat('EEEE').format(dateTime);
    } else if (dateTime.year == now.year) {
      return DateFormat('MMMM d').format(dateTime);
    } else {
      return DateFormat('MMMM d, y').format(dateTime);
    }
  }

  // Format last seen time
  static String formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'Last seen unknown';
    
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inMinutes < 1) {
      return AppStrings.justNow;
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return AppStrings.yesterday;
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return AppStrings.longAgo;
    }
  }

  // Format relative time (like "2 minutes ago")
  static String formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inSeconds < 30) {
      return AppStrings.justNow;
    } else if (difference.inMinutes < 1) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes${minutes == 1 ? ' minute' : ' minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours${hours == 1 ? ' hour' : ' hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days${days == 1 ? ' day' : ' days'} ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks${weeks == 1 ? ' week' : ' weeks'} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months${months == 1 ? ' month' : ' months'} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years${years == 1 ? ' year' : ' years'} ago';
    }
  }

  // Format join date for profile
  static String formatJoinDate(DateTime joinDate) {
    return DateFormat('MMMM d, y').format(joinDate);
  }

  // Format birthday
  static String formatBirthday(DateTime birthday) {
    final now = DateTime.now();
    if (birthday.year == now.year) {
      return DateFormat('MMMM d').format(birthday);
    } else {
      return DateFormat('MMMM d, y').format(birthday);
    }
  }

  // Check if date is today
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && 
           date.month == now.month && 
           date.day == now.day;
  }

  // Check if date is yesterday
  static bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return date.year == yesterday.year && 
           date.month == yesterday.month && 
           date.day == yesterday.day;
  }

  // Check if date is this week
  static bool isThisWeek(DateTime date) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    
    return date.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
           date.isBefore(endOfWeek.add(const Duration(days: 1)));
  }

  // Check if date is this month
  static bool isThisMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  // Check if date is this year
  static bool isThisYear(DateTime date) {
    return date.year == DateTime.now().year;
  }

  // Get time difference in a human-readable format
  static String getTimeDifference(DateTime startTime, DateTime endTime) {
    final difference = endTime.difference(startTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} days';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes';
    } else {
      return '${difference.inSeconds} seconds';
    }
  }

  // Format duration (like call duration)
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  // Get age from birthday
  static int getAge(DateTime birthday) {
    final now = DateTime.now();
    int age = now.year - birthday.year;
    
    if (now.month < birthday.month || 
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    
    return age;
  }

  // Get days until next birthday
  static int getDaysUntilBirthday(DateTime birthday) {
    final now = DateTime.now();
    final thisYearBirthday = DateTime(now.year, birthday.month, birthday.day);
    
    if (thisYearBirthday.isBefore(now)) {
      // Birthday already passed this year, calculate for next year
      final nextYearBirthday = DateTime(now.year + 1, birthday.month, birthday.day);
      return nextYearBirthday.difference(now).inDays;
    } else {
      return thisYearBirthday.difference(now).inDays;
    }
  }

  // Format time range
  static String formatTimeRange(DateTime start, DateTime end) {
    final startTime = DateFormat('h:mm a').format(start);
    final endTime = DateFormat('h:mm a').format(end);
    
    if (isToday(start) && isToday(end)) {
      return '$startTime - $endTime';
    } else if (start.day == end.day) {
      final date = formatDateSeparator(start);
      return '$date, $startTime - $endTime';
    } else {
      final startDate = formatDetailedTime(start);
      final endDate = formatDetailedTime(end);
      return '$startDate - $endDate';
    }
  }

  // Get greeting based on time of day
  static String getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }

  // Check if it's a special romantic time
  static bool isRomanticTime() {
    final now = DateTime.now();
    
    // Check for Valentine's Day
    if (now.month == 2 && now.day == 14) return true;
    
    // Check for New Year's Eve
    if (now.month == 12 && now.day == 31) return true;
    
    // Check for Christmas
    if (now.month == 12 && now.day == 25) return true;
    
    // Check for evening hours (sunset time)
    if (now.hour >= 18 && now.hour <= 22) return true;
    
    return false;
  }

  // Get romantic date suggestions
  static List<String> getRomanticDateSuggestions() {
    final now = DateTime.now();
    final suggestions = <String>[];
    
    if (now.month == 2 && now.day == 14) {
      suggestions.add("Happy Valentine's Day! 💕");
    }
    
    if (now.month == 12 && now.day == 25) {
      suggestions.add("Merry Christmas, my love! 🎄❤️");
    }
    
    if (now.month == 1 && now.day == 1) {
      suggestions.add("Happy New Year! Here's to another year together! 🥂");
    }
    
    // Weekend suggestions
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      suggestions.add("Perfect weekend for some quality time together! 💖");
    }
    
    // Evening suggestions
    if (now.hour >= 18 && now.hour <= 22) {
      suggestions.add("Beautiful evening for a romantic chat! 🌅");
    }
    
    return suggestions;
  }

  // Format anniversary date
  static String formatAnniversary(DateTime anniversaryDate) {
    final now = DateTime.now();
    final years = now.year - anniversaryDate.year;
    final months = now.month - anniversaryDate.month;
    final days = now.day - anniversaryDate.day;
    
    if (years > 0) {
      return '$years ${years == 1 ? 'year' : 'years'} together';
    } else if (months > 0) {
      return '$months ${months == 1 ? 'month' : 'months'} together';
    } else if (days > 0) {
      return '$days ${days == 1 ? 'day' : 'days'} together';
    } else {
      return 'Together since today! 💕';
    }
  }

  // Get chat statistics time periods
  static Map<String, DateTime> getChatStatisticsPeriods() {
    final now = DateTime.now();
    
    return {
      'today': DateTime(now.year, now.month, now.day),
      'yesterday': DateTime(now.year, now.month, now.day - 1),
      'thisWeek': now.subtract(Duration(days: now.weekday - 1)),
      'lastWeek': now.subtract(Duration(days: now.weekday + 6)),
      'thisMonth': DateTime(now.year, now.month, 1),
      'lastMonth': DateTime(now.year, now.month - 1, 1),
      'thisYear': DateTime(now.year, 1, 1),
      'lastYear': DateTime(now.year - 1, 1, 1),
    };
  }

  // Format chat session duration
  static String formatChatSession(DateTime startTime, DateTime? endTime) {
    final end = endTime ?? DateTime.now();
    final duration = end.difference(startTime);
    
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  // Check if dates should show separator in chat
  static bool shouldShowDateSeparator(DateTime? previousDate, DateTime currentDate) {
    if (previousDate == null) return true;
    
    final prevDay = DateTime(previousDate.year, previousDate.month, previousDate.day);
    final currDay = DateTime(currentDate.year, currentDate.month, currentDate.day);
    
    return !prevDay.isAtSameMomentAs(currDay);
  }

  // Format typing timestamp
  static String formatTypingTime() {
    return DateFormat('h:mm a').format(DateTime.now());
  }

  // Get message count by time period
  static Map<String, int> getMessageCountByPeriod(List<DateTime> messageTimes) {
    final now = DateTime.now();
    final counts = <String, int>{
      'today': 0,
      'yesterday': 0,
      'thisWeek': 0,
      'thisMonth': 0,
      'older': 0,
    };
    
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);
    
    for (final time in messageTimes) {
      final messageDay = DateTime(time.year, time.month, time.day);
      
      if (messageDay.isAtSameMomentAs(today)) {
        counts['today'] = counts['today']! + 1;
      } else if (messageDay.isAtSameMomentAs(yesterday)) {
        counts['yesterday'] = counts['yesterday']! + 1;
      } else if (time.isAfter(weekStart)) {
        counts['thisWeek'] = counts['thisWeek']! + 1;
      } else if (time.isAfter(monthStart)) {
        counts['thisMonth'] = counts['thisMonth']! + 1;
      } else {
        counts['older'] = counts['older']! + 1;
      }
    }
    
    return counts;
  }

  // Format timezone-aware time
  static String formatTimezoneAwareTime(DateTime dateTime, {String? timezone}) {
    // Note: For full timezone support, you might want to use the timezone package
    // This is a simplified implementation
    return DateFormat('h:mm a').format(dateTime);
  }

  // Get business hours status
  static String getBusinessHoursStatus() {
    final hour = DateTime.now().hour;
    
    if (hour >= 9 && hour < 17) {
      return 'Business hours';
    } else if (hour >= 17 && hour < 22) {
      return 'Evening';
    } else if (hour >= 22 || hour < 6) {
      return 'Late night';
    } else {
      return 'Early morning';
    }
  }

  // Calculate reading time estimate
  static String estimateReadingTime(String text) {
    final wordCount = text.split(RegExp(r'\s+')).length;
    final wordsPerMinute = 200; // Average reading speed
    final minutes = (wordCount / wordsPerMinute).ceil();
    
    if (minutes < 1) {
      return 'Less than 1 min read';
    } else if (minutes == 1) {
      return '1 min read';
    } else {
      return '$minutes min read';
    }
  }

  // Format export timestamp
  static String formatForExport(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd_HH-mm-ss').format(dateTime);
  }

  // Get romantic time suggestions
  static List<String> getRomanticTimeSuggestions(DateTime dateTime) {
    final suggestions = <String>[];
    final hour = dateTime.hour;
    
    if (hour >= 6 && hour < 12) {
      suggestions.addAll([
        'Good morning, beautiful! ☀️',
        'Rise and shine, my love! 🌅',
        'Morning kisses! 😘',
      ]);
    } else if (hour >= 12 && hour < 17) {
      suggestions.addAll([
        'Good afternoon, gorgeous! 🌞',
        'Hope your day is as lovely as you! 💖',
        'Thinking of you! 💭❤️',
      ]);
    } else if (hour >= 17 && hour < 22) {
      suggestions.addAll([
        'Good evening, my love! 🌅',
        'How was your day, beautiful? 💕',
        'Perfect time for some us time! 💑',
      ]);
    } else {
      suggestions.addAll([
        'Good night, sweet dreams! 🌙',
        'Sleep tight, my love! 😴💤',
        'Dream of us! 💫❤️',
      ]);
    }
    
    return suggestions;
  }

  // Check if it's a milestone date
  static bool isMilestone(DateTime date, DateTime relationshipStart) {
    final difference = date.difference(relationshipStart);
    final days = difference.inDays;
    
    // Check for various milestones
    return days == 30 ||    // 1 month
           days == 100 ||   // 100 days
           days == 365 ||   // 1 year
           days == 500 ||   // 500 days
           days == 730 ||   // 2 years
           days == 1000 ||  // 1000 days
           days % 365 == 0; // Yearly anniversaries
  }

  // Get milestone message
  static String getMilestoneMessage(DateTime date, DateTime relationshipStart) {
    final difference = date.difference(relationshipStart);
    final days = difference.inDays;
    
    if (days == 30) return '🎉 1 Month Together! 💕';
    if (days == 100) return '🎉 100 Days of Love! 💖';
    if (days == 365) return '🎉 1 Year Anniversary! 💍';
    if (days == 500) return '🎉 500 Days Together! 🌟';
    if (days == 730) return '🎉 2 Years of Us! 💝';
    if (days == 1000) return '🎉 1000 Days of Love! ✨';
    if (days % 365 == 0 && days > 730) {
      final years = days ~/ 365;
      return '🎉 $years Years Together! 💞';
    }
    
    return '';
  }
}