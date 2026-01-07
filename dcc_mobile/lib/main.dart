import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/quote_screen.dart';
import 'screens/user_profile_screen.dart';
import 'services/auth_service.dart';
import 'services/logger_service.dart';
import 'services/fcm_service.dart';
import 'themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize logger
  LoggerService.initialize();
  
  // Configure URL strategy for web
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  
  await dotenv.load(fileName: ".env");
  
  try {
    await AuthService.configure();
  } catch (e) {
    LoggerService.error('Failed to configure auth service', error: e);
  }
  
  // Initialize Firebase and FCM for mobile platforms only
  if (!kIsWeb) {
    try {
      // Initialize Firebase first
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      LoggerService.info('Firebase initialized successfully');
      
      // Then initialize FCM service
      await FCMService().initialize(
        onMessageOpened: (RemoteMessage message) {
          LoggerService.info('FCM message opened: ${message.messageId}');
          _handleNotificationNavigation(message);
        },
      );
      LoggerService.info('FCM service initialized successfully');
    } catch (e) {
      LoggerService.error('Failed to initialize Firebase/FCM service', error: e);
    }
  }
  
  runApp(const QuoteMeApp());
}

// Handle notification navigation
void _handleNotificationNavigation(RemoteMessage message) {
  final deepLink = message.data['deepLink'];
  final quoteId = message.data['quoteId'];
  
  if (deepLink != null) {
    _router.go(deepLink);
  } else if (quoteId != null) {
    _router.go('/quote/$quoteId');
  } else {
    _router.go('/');
  }
}

class QuoteMeApp extends StatefulWidget {
  const QuoteMeApp({super.key});

  @override
  State<QuoteMeApp> createState() => _QuoteMeAppState();
  
  // Static method to access theme update
  static void updateTheme(ThemeMode themeMode) {
    _QuoteMeAppState.updateTheme(themeMode);
  }
}

class _QuoteMeAppState extends State<QuoteMeApp> {
  ThemeMode _themeMode = ThemeMode.system;
  
  // Static reference for global access
  static _QuoteMeAppState? _instance;
  
  @override
  void initState() {
    super.initState();
    _instance = this;
    _loadThemePreference();
  }
  
  @override
  void dispose() {
    _instance = null;
    super.dispose();
  }
  
  // Static method to access theme update from anywhere
  static void updateTheme(ThemeMode themeMode) {
    _instance?.updateThemeMode(themeMode);
  }
  
  void _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString('theme_mode') ?? 'system';
    setState(() {
      _themeMode = _getThemeModeFromString(themeString);
    });
  }
  
  ThemeMode _getThemeModeFromString(String themeString) {
    switch (themeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
  
  void updateThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = themeMode.toString().split('.').last;
    await prefs.setString('theme_mode', themeString);
    
    setState(() {
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Quote Me',
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}

// GoRouter configuration
final GoRouter _router = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  redirect: (BuildContext context, GoRouterState state) {
    // Handle custom scheme deep links
    final uri = state.uri;
    LoggerService.debug('🔗 Incoming URI: ${uri.toString()}');
    LoggerService.debug('   - scheme: ${uri.scheme}');
    LoggerService.debug('   - host: ${uri.host}');
    LoggerService.debug('   - path: ${uri.path}');
    LoggerService.debug('   - query: ${uri.query}');
    
    // Check for OAuth callback from Cognito
    if (kIsWeb && uri.queryParameters.containsKey('code')) {
      LoggerService.info('🔑 OAuth callback detected - letting Amplify handle automatically');
      // Let Amplify handle this automatically - don't interfere
      return '/';
    }
    
    // Check if it's a custom scheme deep link
    if (uri.scheme == 'quoteme') {
      String newPath;
      
      if (uri.path.isNotEmpty && uri.path != '/') {
        // quoteme:///profile -> path = "/profile"
        newPath = uri.path;
      } else if (uri.host.isNotEmpty) {
        // quoteme://profile -> host = "profile", path = ""
        newPath = '/${uri.host}';
      } else {
        // fallback to home
        newPath = '/';
      }
      
      LoggerService.debug('🔄 Redirecting from ${uri.toString()} to $newPath');
      return newPath;
    }
    
    // No redirect needed for regular navigation
    return null;
  },
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        LoggerService.debug('🏠 Navigating to home screen');
        return const QuoteScreen();
      },
    ),
    GoRoute(
      path: '/quote/:id',
      builder: (BuildContext context, GoRouterState state) {
        final quoteId = state.pathParameters['id']!;
        LoggerService.debug('🔗 Deep link - navigating to quote screen with ID: $quoteId');
        // Use ValueKey to force widget recreation when quote ID changes
        return QuoteScreen(key: ValueKey(quoteId), initialQuoteId: quoteId);
      },
    ),
    GoRoute(
      path: '/profile',
      builder: (BuildContext context, GoRouterState state) {
        LoggerService.debug('👤 Navigating to user profile screen via deep link');
        return const UserProfileScreen(fromDeepLink: true);
      },
    ),
    GoRoute(
      path: '/auth-success',
      builder: (BuildContext context, GoRouterState state) {
        LoggerService.debug('🔐 OAuth success callback received');
        // OAuth success - redirect to home screen
        return const QuoteScreen();
      },
    ),
    GoRoute(
      path: '/test-route',
      builder: (BuildContext context, GoRouterState state) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Test Route Works!', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        );
      },
    ),
    GoRoute(
      path: '/auth/callback',
      builder: (BuildContext context, GoRouterState state) {
        final code = state.uri.queryParameters['code'];
        final error = state.uri.queryParameters['error'];
        
        // Add this critical log message that was missing
        LoggerService.info('🔐 OAuth callback route HIT! Code: $code, Error: $error');
        LoggerService.debug('🔍 Full URI: ${state.uri.toString()}');
        
        if (error != null) {
          LoggerService.error('OAuth error: $error');
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  Text('OAuth Error: $error', style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          );
        }
        
        if (code == null) {
          LoggerService.error('No authorization code received in OAuth callback');
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text('No authorization code received', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          );
        }
        
        LoggerService.info('✅ OAuth callback successful with code: $code');
        
        // Show success message and redirect after a short delay
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🎉 OAuth Success! Code: ${code.substring(0, 8)}...'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
            
            // Wait 2 seconds then redirect to home
            Future.delayed(const Duration(seconds: 2), () {
              if (context.mounted) {
                context.go('/');
              }
            });
          }
        });
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('OAuth Callback'),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'OAuth Callback Received!', 
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Authorization code: ${code.substring(0, 12)}...',
                    style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Processing... Redirecting to home soon.'),
                ],
              ),
            ),
          ),
        );
      },
    ),
    GoRoute(
      path: '/auth-signout',
      builder: (BuildContext context, GoRouterState state) {
        LoggerService.debug('🚪 OAuth signout callback received, redirecting to home');
        return const QuoteScreen();
      },
    ),
  ],
);

// Note: OAuth callback handling is now done automatically by Amplify

