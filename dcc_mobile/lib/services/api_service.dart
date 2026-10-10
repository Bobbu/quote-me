import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'logger_service.dart';

class ApiService {
  static final String baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
  static final String apiKey = dotenv.env['API_KEY'] ?? '';

  // Testable methods that accept HTTP client for dependency injection
  Future<Map<String, dynamic>?> getRandomQuoteWithClient(
    http.Client client, 
    List<String> tags, 
    {int retryCount = 0}
  ) async {
    try {
      String url = '$baseUrl/quote';
      if (tags.isNotEmpty && !tags.contains('All')) {
        final tagsParam = tags.join(',');
        url += '?tags=$tagsParam';
      }
      
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 500 && retryCount < 3) {
        await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
        return await getRandomQuoteWithClient(client, tags, retryCount: retryCount + 1);
      } else if (response.statusCode == 429) {
        return null; // Rate limited
      } else {
        throw Exception('Failed to load quote: ${response.statusCode}');
      }
    } catch (e) {
      if (retryCount < 3) {
        await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
        return await getRandomQuoteWithClient(client, tags, retryCount: retryCount + 1);
      }
      LoggerService.error('Error fetching quote', error: e);
      return null;
    }
  }

  Future<List<String>> getAvailableTagsWithClient(http.Client client) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/tags'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<String>.from(data['tags'] ?? []);
      } else {
        throw Exception('Failed to load tags: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('Error fetching tags', error: e);
      return [];
    }
  }

  Future<Map<String, dynamic>?> getQuoteByIdWithClient(http.Client client, String id) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/quote/$id'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return null; // Quote not found
      } else {
        throw Exception('Failed to load quote: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('Error fetching quote by ID', error: e);
      return null;
    }
  }

  static Future<List<String>> getTags() async {
    try {
      LoggerService.debug('📡 Fetching tags from public API...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/tags'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      LoggerService.debug('📡 Tags response status: ${response.statusCode}');
      LoggerService.debug('📡 Tags response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tags = List<String>.from(data['tags'] ?? []);
        LoggerService.info('✅ Successfully loaded ${tags.length} tags from public API');
        return tags;
      } else {
        throw Exception('Failed to load tags: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching tags: $e', error: e);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getRandomQuote({List<String>? tags}) async {
    try {
      LoggerService.debug('📡 Fetching quote from optimized API...');
      
      String url = '$baseUrl/quote';
      if (tags != null && tags.isNotEmpty && !tags.contains('All')) {
        final tagsParam = tags.join(',');
        url += '?tags=$tagsParam';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        LoggerService.info('✅ Successfully loaded quote from optimized API (2x faster!)');
        return data;
      } else if (response.statusCode == 500) {
        // Retry logic for 500 errors
        await Future.delayed(Duration(milliseconds: 500));
        return await getRandomQuote(tags: tags);
      } else if (response.statusCode == 429) {
        LoggerService.warning('⚠️ API rate limit reached');
        throw Exception('API rate limit reached. Please try again later.');
      } else {
        throw Exception('Failed to load quote: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching quote: $e', error: e);
      rethrow;
    }
  }
  
  /// Get a specific quote by ID using optimized endpoint
  static Future<Map<String, dynamic>?> getQuoteById(String id) async {
    try {
      LoggerService.debug('📡 Fetching specific quote from optimized API...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/quote/$id'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        LoggerService.info('✅ Successfully loaded specific quote from optimized API');
        return data;
      } else if (response.statusCode == 404) {
        LoggerService.warning('⚠️ Quote not found: $id');
        return null;
      } else if (response.statusCode == 429) {
        LoggerService.warning('⚠️ API rate limit reached');
        throw Exception('API rate limit reached. Please try again later.');
      } else {
        throw Exception('Failed to load quote: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching quote by ID: $e', error: e);
      rethrow;
    }
  }

  /// Get quotes by specific author using optimized endpoint
  static Future<List<Map<String, dynamic>>> getQuotesByAuthor(String author, {int? limit, String? nextToken}) async {
    try {
      LoggerService.debug('📡 Fetching quotes by author from optimized API...');
      
      String url = '$baseUrl/quotes/author/${Uri.encodeComponent(author)}';
      List<String> queryParams = [];
      
      if (limit != null) queryParams.add('limit=$limit');
      if (nextToken != null) queryParams.add('nextToken=${Uri.encodeComponent(nextToken)}');
      
      if (queryParams.isNotEmpty) {
        url += '?${queryParams.join('&')}';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        LoggerService.info('✅ Successfully loaded ${quotes.length} quotes by author from optimized API');
        return quotes;
      } else if (response.statusCode == 429) {
        LoggerService.warning('⚠️ API rate limit reached');
        throw Exception('API rate limit reached. Please try again later.');
      } else {
        throw Exception('Failed to load quotes by author: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching quotes by author: $e', error: e);
      rethrow;
    }
  }

  /// Get quotes by specific tag using optimized endpoint
  static Future<List<Map<String, dynamic>>> getQuotesByTag(String tag, {int? limit, String? nextToken}) async {
    try {
      LoggerService.debug('📡 Fetching quotes by tag from optimized API...');
      
      String url = '$baseUrl/quotes/tag/${Uri.encodeComponent(tag)}';
      List<String> queryParams = [];
      
      if (limit != null) queryParams.add('limit=$limit');
      if (nextToken != null) queryParams.add('nextToken=${Uri.encodeComponent(nextToken)}');
      
      if (queryParams.isNotEmpty) {
        url += '?${queryParams.join('&')}';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        LoggerService.info('✅ Successfully loaded ${quotes.length} quotes by tag from optimized API');
        return quotes;
      } else if (response.statusCode == 429) {
        LoggerService.warning('⚠️ API rate limit reached');
        throw Exception('API rate limit reached. Please try again later.');
      } else {
        throw Exception('Failed to load quotes by tag: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching quotes by tag: $e', error: e);
      rethrow;
    }
  }

  /// Search quotes using optimized endpoint
  static Future<List<Map<String, dynamic>>> searchQuotes(String query, {int? limit, String? nextToken}) async {
    try {
      LoggerService.debug('📡 Searching quotes from optimized API...');
      
      String url = '$baseUrl/search';
      List<String> queryParams = ['q=${Uri.encodeComponent(query)}'];
      
      if (limit != null) queryParams.add('limit=$limit');
      if (nextToken != null) queryParams.add('nextToken=${Uri.encodeComponent(nextToken)}');
      
      url += '?${queryParams.join('&')}';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        LoggerService.info('✅ Successfully searched ${quotes.length} quotes from optimized API');
        return quotes;
      } else if (response.statusCode == 429) {
        LoggerService.warning('⚠️ API rate limit reached');
        throw Exception('API rate limit reached. Please try again later.');
      } else {
        throw Exception('Failed to search quotes: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error searching quotes: $e', error: e);
      rethrow;
    }
  }
}