import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'daily_nuggets_service.dart';

/// User settings shared by every screen that opens Settings.
class AppSettings {
  final bool audioEnabled;
  final Set<String> selectedCategories;
  final Map<String, String>? selectedVoice;
  final double speechRate;
  final double pitch;
  final int quoteRetrievalLimit;
  final int maxReturnedQuotes;

  const AppSettings({
    required this.audioEnabled,
    required this.selectedCategories,
    required this.selectedVoice,
    required this.speechRate,
    required this.pitch,
    required this.quoteRetrievalLimit,
    required this.maxReturnedQuotes,
  });
}

/// Single place that reads and writes settings, so all entry points stay in sync.
class SettingsService {
  /// Always reads the latest stored values (never a cached copy).
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final voiceName = prefs.getString('selected_voice_name');
    final voiceLocale = prefs.getString('selected_voice_locale');
    return AppSettings(
      audioEnabled: prefs.getBool('audio_enabled') ?? false,
      selectedCategories: (prefs.getStringList('selected_categories') ?? ['All']).toSet(),
      selectedVoice: voiceName != null && voiceLocale != null
          ? {'name': voiceName, 'locale': voiceLocale}
          : null,
      speechRate: prefs.getDouble('speech_rate') ?? 0.5,
      pitch: prefs.getDouble('pitch') ?? 1.0,
      quoteRetrievalLimit: prefs.getInt('quote_retrieval_limit') ?? 50,
      maxReturnedQuotes: prefs.getInt('max_returned_quotes') ?? 5,
    );
  }

  /// Persists settings and syncs the tag filter to the user's Daily Nuggets subscription.
  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('audio_enabled', settings.audioEnabled);
    await prefs.setStringList('selected_categories', settings.selectedCategories.toList());
    unawaited(DailyNuggetsService.syncTagFilter(settings.selectedCategories));
    await prefs.setInt('quote_retrieval_limit', settings.quoteRetrievalLimit);
    await prefs.setInt('max_returned_quotes', settings.maxReturnedQuotes);
    await prefs.setDouble('speech_rate', settings.speechRate);
    await prefs.setDouble('pitch', settings.pitch);

    final voice = settings.selectedVoice;
    if (voice != null) {
      await prefs.setString('selected_voice_name', voice['name']!);
      await prefs.setString('selected_voice_locale', voice['locale']!);
    }
  }
}
