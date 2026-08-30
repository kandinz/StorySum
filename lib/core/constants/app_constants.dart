class AppConstants {
  static const String appName = 'StorySum';
  static const String appVersion = '1.0.59';

  // Default Story Link & Chapter
  static const String defaultStoryUrl = 'https://xtruyen.vn/truyen/pham-nhan-tu-tien/chuong-1/';
  static const int defaultChapterNumber = 1;

  // Default System Prompts
  static const String defaultSummaryPrompt = 
      'Dưới đây là nội dung của một chương truyện. Hãy tóm tắt lại toàn bộ chương thành một đoạn văn liền mạch, dễ hiểu, không tách phần. Tóm tắt phải nêu đầy đủ diễn biến chính, nguyên nhân dẫn đến hành động của nhân vật, các bước ngoặt quan trọng, và mối liên hệ giữa các sự kiện. Giữ nguyên tên nhân vật và mạch truyện gốc. Không thêm hoặc bịa nội dung không có trong chương.';
  static const String defaultTranslatePrompt = 
      'Hãy dịch toàn bộ nội dung chương truyện sau sang tiếng Việt một cách mượt mà, tự nhiên, văn phong truyện dịch chuẩn, giữ nguyên tên riêng, địa danh và các đại từ xưng hô phù hợp ngữ cảnh. Không thêm hoặc bớt nội dung ngoài chương truyện.';
  
  // Voices (Mặc định chọn Giọng nữ phổ thông TikTok vi_female_huong)
  static const String defaultVoiceId = 'tiktok-vi_female_huong';
  static const String defaultVoiceName = 'Giọng nữ phổ thông';

  // Database Tables
  static const String tableChapters = 'chapters';
  static const String tableSummaries = 'summaries';
  static const String tableAudios = 'saved_audios';
  static const String tableBookmarks = 'bookmarks';

  // Storage Keys - Reading & Theme
  static const String keyFontSize = 'app_font_size';
  static const String keyFontFamily = 'app_font_family';
  static const String defaultFontFamily = 'Inter';
  static const String keyAppThemeMode = 'app_theme_mode';
  static const String defaultAppThemeMode = 'dark';

  // Storage Keys - Audio & Playback
  static const String keySelectedVoice = 'selected_voice_id';
  static const String keyPitch = 'voice_pitch';
  static const String keyRate = 'voice_rate';
  static const String keyVolume = 'voice_volume';
  static const String keyAutoNextChapter = 'auto_next_chapter';
  static const String keyAudioPrefetchCount = 'audio_prefetch_count';
  static const int defaultAudioPrefetchCount = 5;
  static const String keySleepTimerMinutes = 'sleep_timer_minutes';
  static const int defaultSleepTimerMinutes = 30;

  // Storage Keys - Background Music (BGM)
  static const String keyBgmEnabled = 'bgm_enabled';
  static const String keyBgmVolume = 'bgm_volume';
  static const String keySelectedBgmTrack = 'selected_bgm_track_id';
  static const String keyCustomBgmTracks = 'custom_bgm_tracks_json';
  static const double defaultBgmVolume = 0.2; // 20%
  static const String defaultBgmTrackId = 'bgm1';

  // Storage Keys - AI & Translation Prompts
  static const String keySystemPrompt = 'summary_system_prompt';
  static const String keyTranslatePrompt = 'translate_system_prompt';
  static const String keyTranslateContent = 'translate_content_enabled';

  // Storage Keys - AI Multi-Providers
  static const String defaultGeminiModel = 'gemini-2.5-flash-lite';
  static const String keyAiProvidersJson = 'custom_ai_providers_list';
  static const String keyActiveAiProviderId = 'selected_ai_provider_id';
  static const String keyGeminiApiKeys = 'gemini_api_keys';

  // Storage Keys - Last Played Position
  static const String keyLastPlayedStory = 'last_played_story_title';
  static const String keyLastPlayedChapter = 'last_played_chapter_number';
  static const String keyLastPlayedSentenceIndex = 'last_played_sentence_index';
  static const String keyLastPlayedSource = 'last_played_source_type';
  static const String keyLastPlayedStoryUrl = 'last_played_story_url';

  // Feedback & Bug Report Google Form URL
  static const String feedbackFormUrl = 'https://forms.gle/4jWbNkJqWjD1gQfM7';
}
