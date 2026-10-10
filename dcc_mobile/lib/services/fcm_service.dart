import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import '../services/daily_nuggets_service.dart';
import '../services/auth_service.dart';

// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Note: Can't use Logger here as it requires initialization
  // Track analytics for background message
  if (message.data['userId'] != null && message.data['quoteId'] != null) {
    // Note: Can't use regular services here, would need direct HTTP call
    // Background notification received for quote: ${message.data['quoteId']}
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final Logger _logger = Logger();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _initialized = false;
  String? _currentToken;
  Function(RemoteMessage)? _onMessageOpenedCallback;
  
  // Platform detection
  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  Future<void> initialize({
    required Function(RemoteMessage) onMessageOpened,
  }) async {
    if (_initialized) return;
    
    _onMessageOpenedCallback = onMessageOpened;
    
    try {
      // Firebase should already be initialized in main.dart
      _logger.i('FCM service initializing...');
      
      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      // Initialize local notifications for rich notifications
      await _initializeLocalNotifications();
      
      // Set up message handlers (but don't request permissions yet)
      _setupMessageHandlers();
      
      // Check if app was opened from notification
      await _checkInitialMessage();
      
      // NOTE: We don't request permissions or get token during initialization.
      // This will be done when user explicitly taps "Enable Push Notifications".
      
      _initialized = true;
      _logger.i('FCM Service initialized successfully');
      
    } catch (e) {
      _logger.e('Failed to initialize FCM: $e');
      rethrow;
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    
    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );
    
    // Create notification channel for Android
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'daily_nuggets',
        'Daily Nuggets',
        description: 'Your daily inspirational quotes',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );
      
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _requestPermissions() async {
    _logger.i('🔔 Requesting notification permissions...');
    
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false, // Explicitly false to force dialog
      sound: true,
    );
    
    _logger.i('🔔 Permission request completed:');
    _logger.i('   - authorizationStatus: ${settings.authorizationStatus}');
    _logger.i('   - alert: ${settings.alert}');
    _logger.i('   - badge: ${settings.badge}');
    _logger.i('   - sound: ${settings.sound}');
    
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _logger.e('❌ Notification permissions explicitly denied');
      throw Exception('Notification permissions denied');
    } else if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      _logger.w('⚠️ Notification permissions still not determined');
      throw Exception('Notification permissions not determined');
    }
  }

  Future<void> _getAndSaveToken() async {
    try {
      // On iOS, ensure APNS token is available first
      if (Platform.isIOS) {
        _logger.i('🔔 Getting APNS token first on iOS...');
        String? apnsToken = await _messaging.getAPNSToken();
        _logger.i('🔔 APNS token: ${apnsToken != null ? "available" : "null"}');
        
        if (apnsToken == null) {
          _logger.w('⚠️ APNS token not available, waiting a moment...');
          await Future.delayed(Duration(seconds: 2));
          apnsToken = await _messaging.getAPNSToken();
          _logger.i('🔔 APNS token after delay: ${apnsToken != null ? "available" : "null"}');
        }
      }
      
      _logger.i('🔔 Attempting to get FCM token...');
      String? token = await _messaging.getToken(
        vapidKey: kIsWeb ? 'YOUR_VAPID_KEY_HERE' : null, // Add VAPID key for web
      );
      
      _logger.i('🔔 FCM getToken() returned: ${token != null ? "token exists" : "null"}');
      
      if (token != null) {
        _currentToken = token;
        _logger.i('✅ FCM Token obtained: ${token.substring(0, 10)}...');
        _logger.i('🔄 Starting token upload to server...');
        await _uploadTokenToServer(token);
        _logger.i('✅ Token upload process completed');
      } else {
        _logger.e('❌ FCM token is null - this usually means APNS is not configured in Firebase');
      }
    } catch (e) {
      _logger.e('❌ Failed to get FCM token: $e');
      _logger.e('   Stack trace: ${e.toString()}');
    }
  }

  Future<void> _uploadTokenToServer(String token) async {
    try {
      final userId = await AuthService.getCurrentUserId();
      
      if (userId == null) {
        _logger.w('No authenticated user, skipping token upload');
        return;
      }
      
      // Get current subscription to preserve settings
      final currentSub = await DailyNuggetsService.getSubscription();
      
      // Prepare notification preferences with FCM token
      final newPreferences = {
        ...?currentSub?.notificationPreferences,
        'fcmTokens': {
          _platform: token,
        }
      };
      
      _logger.i('🔄 Uploading FCM token...');
      _logger.i('   - platform: $_platform');
      _logger.i('   - token: ${token.substring(0, 20)}...');
      _logger.i('   - preferences structure: $newPreferences');
      
      // Update subscription with FCM token
      await DailyNuggetsService.updateSubscription(
        isSubscribed: currentSub?.isSubscribed ?? false,
        deliveryMethod: currentSub?.deliveryMethod ?? 'email',
        timezone: currentSub?.timezone ?? 'America/New_York',
        notificationPreferences: newPreferences,
      );
      
      _logger.i('✅ FCM token uploaded successfully for platform: $_platform');
      
      // Debug: Check what the subscription looks like after FCM token upload
      final afterUpload = await DailyNuggetsService.getSubscription();
      _logger.i('🔍 Subscription after FCM upload: ${afterUpload?.toJson()}');
      _logger.i('🔍 FCM upload - notification preferences: ${afterUpload?.notificationPreferences}');
      
    } catch (e) {
      _logger.e('Failed to upload FCM token: $e');
    }
  }

  void _onTokenRefresh(String token) {
    _logger.i('FCM token refreshed');
    _currentToken = token;
    _uploadTokenToServer(token);
  }

  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _logger.i('Foreground message received: ${message.messageId}');
      _showLocalNotification(message);
      _trackNotificationReceived(message);
    });
    
    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _logger.i('Notification opened app from background: ${message.messageId}');
      _handleNotificationTap(message);
    });
  }

  Future<void> _checkInitialMessage() async {
    // Check if app was launched from a notification
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    
    if (initialMessage != null) {
      _logger.i('App opened from terminated state via notification');
      _handleNotificationTap(initialMessage);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    
    if (notification == null) return;
    
    // Build notification details with actions
    final BigTextStyleInformation bigTextStyle = BigTextStyleInformation(
      data['fullQuote'] ?? notification.body ?? '',
      contentTitle: notification.title,
      summaryText: data['author'] ?? '',
    );
    
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'daily_nuggets',
      'Daily Nuggets',
      channelDescription: 'Your daily inspirational quotes',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: bigTextStyle,
      actions: [
        const AndroidNotificationAction(
          'favorite',
          'Favorite',
          icon: DrawableResourceAndroidBitmap('ic_favorite'),
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'share',
          'Share',
          icon: DrawableResourceAndroidBitmap('ic_share'),
          showsUserInterface: true,
        ),
      ],
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'DAILY_NUGGET',
    );
    
    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: data['quoteId'],
    );
  }

  void _onLocalNotificationTapped(NotificationResponse response) {
    _logger.i('Local notification tapped: ${response.actionId}');
    
    if (response.actionId == 'favorite') {
      _handleFavoriteAction(response.payload);
    } else if (response.actionId == 'share') {
      _handleShareAction(response.payload);
    } else {
      // Default tap - open quote
      _navigateToQuote(response.payload);
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    _trackNotificationOpened(message);
    
    if (_onMessageOpenedCallback != null) {
      _onMessageOpenedCallback!(message);
    }
    
    // Navigate based on deep link
    final deepLink = message.data['deepLink'];
    if (deepLink != null) {
      _navigateToDeepLink(deepLink);
    }
  }

  void _navigateToQuote(String? quoteId) {
    if (quoteId == null) return;
    
    // Use GoRouter for navigation
    // This assumes your app has a global navigatorKey or router reference
    // You'll need to pass this in during initialization
    _logger.i('Navigating to quote: $quoteId');
  }

  void _navigateToDeepLink(String deepLink) {
    _logger.i('Navigating to deep link: $deepLink');
    // Implement deep link navigation
  }

  void _handleFavoriteAction(String? quoteId) {
    if (quoteId == null) return;
    _logger.i('Favorite action for quote: $quoteId');
    // Implement favorite logic
  }

  void _handleShareAction(String? quoteId) {
    if (quoteId == null) return;
    _logger.i('Share action for quote: $quoteId');
    // Implement share logic
  }

  void _trackNotificationReceived(RemoteMessage message) {
    // Track analytics
    final quoteId = message.data['quoteId'];
    final userId = message.data['userId'];
    
    if (quoteId != null && userId != null) {
      _logger.i('Tracking notification received: Quote $quoteId for User $userId');
      // Send analytics event to server
    }
  }

  void _trackNotificationOpened(RemoteMessage message) {
    // Track analytics
    final quoteId = message.data['quoteId'];
    final userId = message.data['userId'];
    
    if (quoteId != null && userId != null) {
      _logger.i('Tracking notification opened: Quote $quoteId for User $userId');
      // Send analytics event to server
    }
  }

  // Public methods
  
  Future<bool> areNotificationsEnabled() async {
    final settings = await _messaging.getNotificationSettings();
    _logger.i('🔔 Notification settings check:');
    _logger.i('   - authorizationStatus: ${settings.authorizationStatus}');
    _logger.i('   - alert: ${settings.alert}');
    _logger.i('   - badge: ${settings.badge}');
    _logger.i('   - sound: ${settings.sound}');
    
    // Be more strict - only consider truly authorized, not provisional
    final isAuthorized = settings.authorizationStatus == AuthorizationStatus.authorized;
    _logger.i('   - returning isAuthorized: $isAuthorized');
    return isAuthorized;
  }

  Future<void> requestPermissions() async {
    try {
      _logger.i('🔔 FCM requestPermissions() called');
      _logger.i('🔔 FCM service initialized: $_initialized');
      
      if (!_initialized) {
        _logger.w('🔔 FCM service not initialized! Initializing now...');
        // Emergency initialization if not already done
        await initialize(onMessageOpened: (message) {
          _logger.i('Emergency initialization - message opened callback');
        });
      }
      
      _logger.i('🔔 About to call _requestPermissions()...');
      await _requestPermissions();
      _logger.i('🔔 Permissions requested, now getting FCM token...');
      await _getAndSaveToken();
      _logger.i('🔔 Token retrieval completed, current token: ${_currentToken != null ? "exists" : "null"}');
      
      // Set up token refresh listener after first successful token
      if (_currentToken != null) {
        _messaging.onTokenRefresh.listen(_onTokenRefresh);
        _logger.i('🔔 Token refresh listener set up');
      } else {
        _logger.w('🔔 No FCM token obtained, skipping refresh listener');
      }
    } catch (e) {
      _logger.e('🔔 Exception in requestPermissions(): $e');
      _logger.e('🔔 Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> disableNotifications() async {
    try {
      // Remove token from server
      final userId = await AuthService.getCurrentUserId();
      
      if (userId != null) {
        // Get current subscription to preserve settings
        final currentSub = await DailyNuggetsService.getSubscription();
        
        // Update subscription to remove FCM token and disable push
        await DailyNuggetsService.updateSubscription(
          isSubscribed: currentSub?.isSubscribed ?? false,
          deliveryMethod: currentSub?.deliveryMethod ?? 'email',
          timezone: currentSub?.timezone ?? 'America/New_York',
          notificationPreferences: {
            ...?currentSub?.notificationPreferences,
            'fcmTokens': {
              _platform: null,
            },
            'enablePush': false,
          },
        );
      }
      
      // Delete local token
      await _messaging.deleteToken();
      _currentToken = null;
      
      _logger.i('Push notifications disabled');
      
    } catch (e) {
      _logger.e('Failed to disable notifications: $e');
      rethrow;
    }
  }

  String? get currentToken => _currentToken;
  bool get isInitialized => _initialized;
}