import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'admin_dashboard_screen.dart';
import 'user_profile_screen.dart';
import 'registration_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool redirectToProfileAfterLogin;
  final String? initialMode;
  
  const LoginScreen({
    super.key,
    this.redirectToProfileAfterLogin = false,
    this.initialMode,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    // If initialMode is signup, navigate to registration immediately
    if (widget.initialMode == 'signup') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToRegistration();
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _navigateToRegistration() async {
    final result = await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const RegistrationScreen(),
      ),
    );
    
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.signInWithGoogle();
      
      if (result) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Google sign-in was cancelled or failed';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Google sign-in failed: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.signInWithApple();
      
      if (result) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Apple sign-in was cancelled or failed';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Apple sign-in failed: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (result) {
        if (mounted) {
          // Check if user is admin
          final isAdmin = await AuthService.isUserInAdminGroup();
          
          if (!mounted) return;
          
          if (widget.redirectToProfileAfterLogin) {
            // User came from profile deep link - redirect back to profile
            // Use push instead of pushReplacement to allow proper navigation back
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const UserProfileScreen(fromDeepLink: true),
              ),
            );
          } else if (isAdmin) {
            // Navigate to admin dashboard
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const AdminDashboardScreen(),
              ),
            );
          } else {
            // For now, just show success and go back
            // In future, this could navigate to a user-specific dashboard
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Successfully logged in!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop(true); // Return true to indicate logged in
          }
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(String error) {
    if (error.contains('UserNotFoundException')) {
      return 'User not found. Please check your email address or sign up.';
    } else if (error.contains('NotAuthorizedException')) {
      return 'Invalid email or password. Please try again.';
    } else if (error.contains('UserNotConfirmedException')) {
      return 'Account not confirmed. Please check your email.';
    } else if (error.contains('NetworkException')) {
      return 'Network error. Please check your connection.';
    } else {
      return 'Sign in failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  const SizedBox(height: 60),
                  
                  // App Logo/Title
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.secondary,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.format_quote,
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Quote Me',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your Daily Inspiration',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Login Form
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Welcome Back',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          
                          const SizedBox(height: 24),

                          // Email Field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            enabled: !_isLoading,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: Icon(Icons.email),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email address';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          // Password Field
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            textInputAction: TextInputAction.done,
                            enabled: !_isLoading,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible 
                                    ? Icons.visibility_off 
                                    : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) {
                              if (!_isLoading) {
                                _signIn();
                              }
                            },
                          ),

                          const SizedBox(height: 16),

                          // Forgot Password Link
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const ForgotPasswordScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                'Forgot Password?',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Error Message
                          if (_errorMessage != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: theme.colorScheme.error,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Sign In Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.secondary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isLoading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          theme.colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Signing In...'),
                                  ],
                                )
                              : Text(
                                  'Sign In',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                          ),

                          const SizedBox(height: 16),

                          // Divider with text
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  'or',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          // Google Sign In Button
                          GestureDetector(
                            onTap: _isLoading ? null : _signInWithGoogle,
                            child: Image.asset(
                              theme.brightness == Brightness.dark
                                  ? 'assets/icons/google/wht_google_button@3x.png'
                                  : 'assets/icons/google/blk_google_button@3x.png',
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Apple Sign In Button - Available on all platforms
                          GestureDetector(
                            onTap: _isLoading ? null : _signInWithApple,
                            child: Image.asset(
                              theme.brightness == Brightness.dark
                                  ? 'assets/icons/apple/wht_apple_button@3x.png'
                                  : 'assets/icons/apple/blk_apple_button@3x.png',
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Divider with text
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  'or',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Sign Up Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const RegistrationScreen(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              'Create New Account',
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Back to App Button
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Back to Quotes',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}