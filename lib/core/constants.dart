class AppConstants {
  // API
  static const String apiBaseUrl = 'https://api.giantagent.com';
  static const int apiTimeout = 30;
  
  // Database
  static const String databaseName = 'giant_agent.db';
  static const int databaseVersion = 1;
  
  // Shared Preferences Keys
  static const String prefThemeMode = 'theme_mode';
  static const String prefLanguage = 'language';
  static const String prefNotifications = 'notifications';
  static const String prefAutoSave = 'auto_save';
  static const String prefFontSize = 'font_size';
  
  // File Limits
  static const int maxFileSize = 10 * 1024 * 1024; // 10 MB
  static const List<String> allowedFileExtensions = ['txt', 'json', 'csv', 'md', 'dart', 'py', 'js', 'html', 'css'];
  static const List<String> allowedImageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
  
  // Messages
  static const String defaultErrorMessage = 'حدث خطأ. يرجى المحاولة مرة أخرى.';
  static const String networkErrorMessage = 'لا يوجد اتصال بالإنترنت.';
  static const String fileTooLargeMessage = 'الملف كبير جداً. الحد الأقصى 10 ميجابايت.';
  static const String invalidFileTypeMessage = 'نوع الملف غير مدعوم.';
  
  // Animation
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration shortAnimationDuration = Duration(milliseconds: 150);
  static const Duration longAnimationDuration = Duration(milliseconds: 500);
  
  // Limits
  static const int maxRecentModels = 5;
  static const int maxConversationTitleLength = 50;
  static const int maxMessagePreviewLength = 100;
}
