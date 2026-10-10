import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'auth_service.dart';
import 'logger_service.dart';

class OpenAIImageGenerator {
  static const int _timeoutSeconds = 30; // Quick response for job submission

  /// Saves a custom image URL directly to a quote without AI generation
  /// This is useful for quotes that fail AI moderation
  /// Automatically extracts direct image URLs from sharing pages
  static Future<bool> saveCustomImageUrl({
    required String quoteId,
    required String imageUrl,
  }) async {
    try {
      // Try to extract direct image URL from sharing pages
      String finalImageUrl = await _extractDirectImageUrl(imageUrl);
      
      final idToken = await AuthService.getIdToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/admin/save-custom-image'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'quote_id': quoteId,
          'image_url': finalImageUrl,
        }),
      ).timeout(Duration(seconds: _timeoutSeconds));

      return response.statusCode == 200;
    } catch (e) {
      LoggerService.error('Error saving custom image URL: $e', error: e);
      return false;
    }
  }

  /// Attempts to extract a direct image URL from sharing pages
  /// Falls back to the original URL if extraction fails
  static Future<String> _extractDirectImageUrl(String url) async {
    try {
      // If it's already a direct image URL (common extensions), return as-is
      if (url.toLowerCase().contains(RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)(\?|$)'))) {
        return url;
      }

      // Check for known sharing page patterns and extract direct image URLs
      if (url.contains('reve.com/share/') || url.contains('app.reve.com/share/')) {
        // For reve.com sharing pages, fetch the page and extract og:image
        final response = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Mozilla/5.0 (compatible; Quote-Me-App/1.0)'},
        ).timeout(Duration(seconds: 10));

        if (response.statusCode == 200) {
          // Look for og:image meta tag
          final ogImageMatch = RegExp(r'<meta\s+property="og:image"\s+content="([^"]+)"')
              .firstMatch(response.body);
          if (ogImageMatch != null) {
            return ogImageMatch.group(1)!;
          }
        }
      }

      // Add more sharing page patterns here as needed
      // if (url.contains('other-service.com/share/')) { ... }

      // If no extraction pattern matches, return original URL
      return url;
    } catch (e) {
      LoggerService.error('Error extracting direct image URL: $e', error: e);
      // If extraction fails, return the original URL
      return url;
    }
  }

  /// Submits an image generation job and returns a job ID
  /// The actual generation happens asynchronously
  static Future<String> submitImageGenerationJob({
    required String quote,
    required String author,
    String? tags,
    String? quoteId,
  }) async {
    try {
      final idToken = await AuthService.getIdToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/admin/generate-image'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'quote': quote,
          'author': author,
          'tags': tags ?? '',
          if (quoteId != null) 'quote_id': quoteId,
        }),
      ).timeout(Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 202) {  // Accepted
        final data = jsonDecode(response.body);
        return data['jobId'] ?? '';
      } else {
        throw Exception('Failed to submit job: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Error submitting job: $e');
    }
  }

  /// Checks the status of an image generation job
  static Future<Map<String, dynamic>> checkJobStatus(String jobId) async {
    try {
      final idToken = await AuthService.getIdToken();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/admin/image-generation-status/$jobId'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Job not found');
      } else {
        throw Exception('Failed to check status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error checking status: $e');
    }
  }

  /// Legacy method for backward compatibility - now submits async job
  static Future<String> generateImageForQuote({
    required String quote,
    required String author,
    String? tags,
    String? quoteId,
  }) async {
    // Submit the job
    final jobId = await submitImageGenerationJob(
      quote: quote,
      author: author,
      tags: tags,
      quoteId: quoteId,
    );
    
    // For backward compatibility, return the job ID
    // The UI should be updated to handle async generation
    return jobId;
  }

  /// Generates a test image using the backend proxy
  static Future<String> generateTestImage() async {
    return submitImageGenerationJob(
      quote: "The only way to do great work is to love what you do.",
      author: "Steve Jobs",
      tags: "motivation, success, passion",
    );
  }
}