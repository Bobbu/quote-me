import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';

class FavoriteHeartButton extends StatefulWidget {
  final String quoteId;
  final bool initialIsFavorite;
  final VoidCallback? onFavoriteChanged;
  final double size;
  final bool showTooltip;

  const FavoriteHeartButton({
    super.key,
    required this.quoteId,
    this.initialIsFavorite = false,
    this.onFavoriteChanged,
    this.size = 24.0,
    this.showTooltip = true,
  });

  @override
  State<FavoriteHeartButton> createState() => _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends State<FavoriteHeartButton>
    with SingleTickerProviderStateMixin {
  bool _isFavorite = false;
  bool _isLoading = false;
  bool _isSignedIn = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initialIsFavorite;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _checkAuthAndFavoriteStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndFavoriteStatus() async {
    try {
      final isSignedIn = await AuthService.isSignedIn();
      if (!isSignedIn) {
        setState(() {
          _isSignedIn = false;
        });
        return;
      }

      setState(() {
        _isSignedIn = true;
      });

      // Check if initially favorited if not already set
      if (!widget.initialIsFavorite) {
        final isFav = await FavoritesService.isFavorite(widget.quoteId);
        if (mounted) {
          setState(() {
            _isFavorite = isFav;
          });
        }
      }
    } catch (e) {
      LoggerService.error('Error checking auth/favorite status', error: e);
      if (mounted) {
        setState(() {
          _isSignedIn = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_isSignedIn) {
      _showSignInDialog();
      return;
    }

    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final newStatus = await FavoritesService.toggleFavorite(widget.quoteId);
      
      if (mounted) {
        setState(() {
          _isFavorite = newStatus;
          _isLoading = false;
        });

        // Animate the heart
        _animationController.forward().then((_) {
          _animationController.reverse();
        });

        // Show feedback
        if (newStatus) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.favorite, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Added to favorites'),
                ],
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.favorite_border, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Removed from favorites'),
                ],
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.green,
            ),
          );
        }

        widget.onFavoriteChanged?.call();
      }
    } catch (e) {
      LoggerService.error('Error toggling favorite', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showSignInDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign In Required'),
          content: const Text(
            'Please sign in to save quotes to your favorites.',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Sign In'),
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to login screen
                Navigator.pushNamed(context, '/login');
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSignedIn) {
      return const SizedBox.shrink();
    }

    Widget heartIcon = AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Icon(
            _isFavorite ? Icons.favorite : Icons.favorite_border,
            size: widget.size,
            color: Colors.red,
          ),
        );
      },
    );

    if (_isLoading) {
      heartIcon = SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(
          strokeWidth: 2.0,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    Widget button = IconButton(
      onPressed: _toggleFavorite,
      icon: heartIcon,
      tooltip: widget.showTooltip 
        ? (_isFavorite ? 'Remove from favorites' : 'Add to favorites')
        : null,
      constraints: BoxConstraints(
        minWidth: widget.size + 8,
        minHeight: widget.size + 8,
      ),
      padding: EdgeInsets.all(widget.size * 0.1),
    );

    return button;
  }
}