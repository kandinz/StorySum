import 'dart:io';
import 'package:flutter/material.dart' hide WordBoundary;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chapter_model.dart';
import '../models/summary_model.dart';
import '../models/saved_audio_item.dart';
import '../models/sentence_item.dart';
import '../services/crawler_service.dart';
import '../services/summary_service.dart';
import '../services/onnx_tts_service.dart';
import '../services/unified_tts_service.dart';
import '../services/story_import_service.dart';
import '../models/voice_model.dart';
import '../core/database/database_helper.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/audio_exporter.dart';
import '../core/utils/text_normalizer.dart';
import 'settings_provider.dart';
import 'player_state_provider.dart';

class PreloadedChapter {
  final ChapterModel chapter;
  final SummaryModel? summary;
  final List<SentenceItem> summarySentences;
  final List<SentenceItem> contentSentences;

  PreloadedChapter({
    required this.chapter,
    this.summary,
    this.summarySentences = const [],
    this.contentSentences = const [],
  });
}

class AppStateProvider extends ChangeNotifier {
  final CrawlerService crawlerService = CrawlerService();
  final SummaryService summaryService = SummaryService();
  final UnifiedTtsService unifiedTtsService = UnifiedTtsService();
  OnnxTtsService get onnxTtsService => unifiedTtsService.onnxTtsService;
  final DatabaseHelper db = DatabaseHelper.instance;

  // Controllers
  final TextEditingController urlController = TextEditingController(
    text: AppConstants.defaultStoryUrl,
  );
  final TextEditingController chapterController = TextEditingController(
    text: AppConstants.defaultChapterNumber.toString(),
  );

  // Processing state
  bool _isProcessing = false;
  String _currentStatusMessage = '';
  double _overallProgress = 0.0;
  String _headerTitle = 'Chưa tải chương nào';

  ChapterModel? _currentChapter;
  SummaryModel? _currentSummary;

  // Sentence-level audio state
  List<SentenceItem> _summarySentences = [];
  List<SentenceItem> _contentSentences = [];
  int? _activeSentenceIndex;
  int _currentSummarySentenceIndex = 0;
  int _currentContentSentenceIndex = 0;
  AudioSourceType _activeAudioSource = AudioSourceType.summary;
  int _generationSessionId = 0;

  // Last played tracking
  String? _lastPlayedStoryTitle;
  int? _lastPlayedChapterNumber;
  int? _lastPlayedSentenceIndex;
  AudioSourceType _lastPlayedSource = AudioSourceType.summary;
  String? _lastPlayedStoryUrl;

  // Preloading Next Chapter State
  PreloadedChapter? _preloadedNextChapter;
  bool _isPreloadingNext = false;
  int? _preloadingChapterNumber;
  String _preloadStatusMessage = '';
  int _preloadTaskId = 0;
  Future<PreloadedChapter?>? _inFlightPreloadFuture;

  // Background Story Crawler & File Import State
  final StoryImportService storyImportService = StoryImportService();
  bool _isBackgroundCrawling = false;
  bool _isImportingFile = false;
  String? _bgCrawlStoryTitle;
  String? _bgCrawlBaseUrl;
  int _bgCrawlCurrentChapter = 0;
  int _bgCrawlSuccessCount = 0;
  int _bgCrawlTaskId = 0;
  bool _bgCrawlPausedForPriority = false;
  String? _summaryErrorMessage;

  List<SavedAudioItem> _savedAudios = [];
  List<ChapterModel> _historyChapters = [];

  // Getters
  bool get isProcessing => _isProcessing;
  bool get isImportingFile => _isImportingFile;
  String get currentStatusMessage => _currentStatusMessage;
  String? get summaryErrorMessage => _summaryErrorMessage;
  double get overallProgress => _overallProgress;
  String get headerTitle => _headerTitle;
  ChapterModel? get currentChapter => _currentChapter;
  SummaryModel? get currentSummary => _currentSummary;

  // Background crawler getters
  bool get isBackgroundCrawling => _isBackgroundCrawling;
  String? get bgCrawlStoryTitle => _bgCrawlStoryTitle;
  String? get bgCrawlBaseUrl => _bgCrawlBaseUrl;
  int get bgCrawlCurrentChapter => _bgCrawlCurrentChapter;
  int get bgCrawlSuccessCount => _bgCrawlSuccessCount;

  List<SentenceItem> get summarySentences => _summarySentences;
  List<SentenceItem> get contentSentences => _contentSentences;
  int? get activeSentenceIndex => _activeSentenceIndex;
  int get currentSummarySentenceIndex => _currentSummarySentenceIndex;
  int get currentContentSentenceIndex => _currentContentSentenceIndex;
  AudioSourceType get activeAudioSource => _activeAudioSource;

  /// Tính toán index câu hợp lệ (Nếu là câu cuối hoặc đã phát hết thì đổi lại thành index = 0 / câu đầu tiên)
  int getEffectiveSentenceIndex(int savedIndex, int totalSentences) {
    if (totalSentences <= 0) return 0;
    if (savedIndex >= totalSentences) {
      return 0; // Đã phát hết toàn bộ chương -> phát lại từ câu đầu tiên (index 0)
    }
    if (savedIndex < 0) {
      return 0; // Chưa phát -> câu đầu tiên (index 0)
    }
    return savedIndex;
  }

  // Last played getters
  String? get lastPlayedStoryTitle => _lastPlayedStoryTitle;
  int? get lastPlayedChapterNumber => _lastPlayedChapterNumber;
  int? get lastPlayedSentenceIndex => _lastPlayedSentenceIndex;
  AudioSourceType get lastPlayedSource => _lastPlayedSource;
  String? get lastPlayedStoryUrl => _lastPlayedStoryUrl;

  List<SavedAudioItem> get savedAudios => _savedAudios;
  List<ChapterModel> get historyChapters => _historyChapters;

  // Preload getters
  bool get isPreloadingNext => _isPreloadingNext;
  bool get hasPreloadedNext => _preloadedNextChapter != null;
  int? get preloadedNextChapterNumber => _preloadedNextChapter?.chapter.chapterNumber;
  String get preloadStatusMessage => _preloadStatusMessage;

  /// Kiểm tra xem người dùng đã chọn/tải chương truyện nào chưa
  bool get hasActiveChapter => _currentChapter != null;

  /// Tiêu đề truyện hiển thị trên thanh top bar của ứng dụng
  String get displayStoryTitle {
    if (_currentChapter != null && _currentChapter!.storyTitle.trim().isNotEmpty) {
      return _currentChapter!.storyTitle.trim();
    }
    return '';
  }

  /// Nhãn hiển thị chương dùng cho phần Tóm tắt & Nội dung (VD: "chương 123: Chuyện gì vậy?")
  String get chapterDisplayLabel {
    if (_currentChapter != null) {
      final title = _currentChapter!.chapterTitle.trim();
      if (title.toLowerCase().startsWith('chương') ||
          title.toLowerCase().startsWith('hồi') ||
          title.toLowerCase().startsWith('chap') ||
          title.toLowerCase().startsWith('chapter')) {
        return title.replaceFirst(RegExp(r'^Chương', caseSensitive: false), 'chương');
      }
      if (title.isNotEmpty) {
        return 'chương ${_currentChapter!.chapterNumber}: $title';
      }
      return 'chương ${_currentChapter!.chapterNumber}';
    }
    final inputNum = chapterController.text.trim();
    if (inputNum.isNotEmpty) {
      return 'chương $inputNum';
    }
    return '';
  }

  /// Tiêu đề chương hiển thị trực tiếp dưới tên truyện ở header
  String get displayChapterSubtitle {
    if (_currentChapter != null) {
      final title = _currentChapter!.chapterTitle.trim();
      if (title.isNotEmpty) {
        if (title.toLowerCase().startsWith('chương') ||
            title.toLowerCase().startsWith('hồi') ||
            title.toLowerCase().startsWith('chap') ||
            title.toLowerCase().startsWith('chapter')) {
          return title;
        }
        return 'Chương ${_currentChapter!.chapterNumber}: $title';
      }
      return 'Chương ${_currentChapter!.chapterNumber}';
    }
    return '';
  }

  /// Kiểm tra xem một chương có phải là chương được phát gần nhất không
  bool isLastPlayedChapter(String storyTitle, int chapterNumber) {
    if (_lastPlayedStoryTitle != null && _lastPlayedChapterNumber != null) {
      return _lastPlayedStoryTitle!.trim().toLowerCase() == storyTitle.trim().toLowerCase() &&
          _lastPlayedChapterNumber == chapterNumber;
    }
    if (_savedAudios.isNotEmpty) {
      final first = _savedAudios.first;
      return first.storyTitle.trim().toLowerCase() == storyTitle.trim().toLowerCase() &&
          first.chapterNumber == chapterNumber;
    }
    return false;
  }

  /// Định dạng tiêu đề header chỉ hiển thị số chương và tên chương
  String _formatChapterHeader(ChapterModel chapter) {
    final title = chapter.chapterTitle.trim();
    if (title.toLowerCase().startsWith('chương') ||
        title.toLowerCase().startsWith('hồi') ||
        title.toLowerCase().startsWith('chap') ||
        title.toLowerCase().startsWith('chapter')) {
      return title;
    }
    return 'Chương ${chapter.chapterNumber}: $title';
  }

  /// Tách văn bản thành danh sách câu hoàn chỉnh
  List<SentenceItem> splitIntoSentences(String text) {
    if (text.trim().isEmpty) return [];
    final normalized = TextNormalizer.normalize(text).replaceAll('\r\n', '\n');
    final regex = RegExp(r'(?<=[.!?…])\s+|\n+');
    final rawList = normalized.split(regex);
    final List<SentenceItem> items = [];
    int idx = 0;
    for (final raw in rawList) {
      final t = raw.trim();
      if (t.isNotEmpty && RegExp(r'[a-zA-Z0-9\u00C0-\u1EF9]').hasMatch(t)) {
        items.add(SentenceItem(index: idx++, text: t));
      }
    }
    return items;
  }

  /// Tách câu cho phần Tóm tắt và Nội dung kèm dòng tiêu đề chương ở đầu để đọc TTS cùng nội dung
  List<SentenceItem> buildSentenceListWithHeader(String text, ChapterModel chapter) {
    final header = _formatChapterHeader(chapter).trim();
    String content = text.trim();
    if (header.isNotEmpty) {
      // Tránh lặp nếu nội dung đã bắt đầu bằng header
      if (!content.toLowerCase().startsWith(header.toLowerCase())) {
        content = '$header\n\n$content';
      }
    }
    return splitIntoSentences(content);
  }

  /// Quét nhanh và gắn ngay tức thì các file audio câu đã tồn tại trên đĩa (0s delay)
  Future<List<SentenceItem>> _attachExistingAudioFiles({
    required List<SentenceItem> sentences,
    required String storyTitle,
    required int chapterNumber,
    required String type,
    String? voiceId,
    VoiceModel? voice,
  }) async {
    if (sentences.isEmpty) return sentences;
    final extension = voice != null
        ? UnifiedTtsService.getAudioExtension(voice)
        : (voiceId != null && voiceId.startsWith('onnx') ? 'wav' : 'mp3');

    final List<SentenceItem> result = [];
    for (final s in sentences) {
      if (s.hasAudio) {
        result.add(s);
        continue;
      }
      try {
        final expectedPath = await AudioExporter.generateSentenceAudioFilePath(
          storyTitle: storyTitle,
          chapterNumber: chapterNumber,
          type: type,
          sentenceIndex: s.index,
          sentenceText: s.text,
          voiceId: voiceId,
          extension: extension,
        );
        final file = File(expectedPath);
        if (await file.exists() && await file.length() > 500) {
          result.add(s.copyWith(audioPath: expectedPath));
        } else {
          result.add(s);
        }
      } catch (_) {
        result.add(s);
      }
    }
    return result;
  }

  Future<void> loadSavedData() async {
    _savedAudios = await db.getAllSavedAudios();
    _historyChapters = await db.getAllChapters();

    try {
      final prefs = await SharedPreferences.getInstance();
      _lastPlayedStoryTitle = prefs.getString(AppConstants.keyLastPlayedStory);
      _lastPlayedChapterNumber = prefs.getInt(AppConstants.keyLastPlayedChapter);
      _lastPlayedSentenceIndex = prefs.getInt(AppConstants.keyLastPlayedSentenceIndex);
      final sourceStr = prefs.getString(AppConstants.keyLastPlayedSource) ?? 'summary';
      _lastPlayedSource = sourceStr == 'content' ? AudioSourceType.content : AudioSourceType.summary;
      _lastPlayedStoryUrl = prefs.getString(AppConstants.keyLastPlayedStoryUrl);

      if (_lastPlayedStoryUrl != null && _lastPlayedStoryUrl!.isNotEmpty) {
        urlController.text = _lastPlayedStoryUrl!;
      }
      if (_lastPlayedChapterNumber != null && _lastPlayedChapterNumber! > 0) {
        chapterController.text = _lastPlayedChapterNumber.toString();
      }
    } catch (_) {}

    notifyListeners();
  }

  /// Dán link từ Clipboard, giữ nguyên vẹn link gốc, tự động nhận diện số chương và tự động tải lại truyện
  Future<bool> pasteFromClipboard({
    SettingsProvider? settings,
    PlayerStateProvider? player,
  }) async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
      String rawUrl = data.text!.trim();
      rawUrl = crawlerService.normalizeUrl(rawUrl);
      urlController.text = rawUrl; // Giữ nguyên vẹn link truyện không cắt chương

      final detectedChapter = crawlerService.extractChapterNumberFromUrl(rawUrl);
      if (detectedChapter != null) {
        chapterController.text = detectedChapter.toString();
      } else {
        chapterController.text = '1';
      }
      notifyListeners();

      if (settings != null && player != null && !_isProcessing) {
        await reloadCurrentChapter(settings: settings, player: player, forceRefresh: true);
      }
      return true;
    }
    return false;
  }

  /// Load một truyện từ URL bất kỳ được nhập vào ô tìm kiếm hoặc dán từ clipboard
  Future<void> loadFromUrl(
    String rawUrl, {
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) async {
    String trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;
    trimmed = crawlerService.normalizeUrl(trimmed);

    urlController.text = trimmed;
    final detectedChapter = crawlerService.extractChapterNumberFromUrl(trimmed);
    if (detectedChapter != null) {
      chapterController.text = detectedChapter.toString();
    } else {
      chapterController.text = '1';
    }
    notifyListeners();

    await reloadCurrentChapter(settings: settings, player: player, forceRefresh: true);

    // Tự động khởi động tiến trình tải ngầm toàn bộ truyện từ chương 1 đến hết
    if (_currentChapter != null && _currentChapter!.storyTitle.isNotEmpty) {
      startBackgroundStoryCrawl(
        baseUrl: trimmed,
        storyTitle: _currentChapter!.storyTitle,
        settings: settings,
        startChapter: 1,
      );
    }
  }

  /// So sánh hai tên truyện linh hoạt (loại bỏ tiền tố Truyện, khoảng trắng thừa, chữ hoa/thường)
  static bool isSameStory(String titleA, String titleB) {
    final cleanA = titleA.toLowerCase().replaceAll(RegExp(r'^(truyện|truyen)\s+'), '').trim();
    final cleanB = titleB.toLowerCase().replaceAll(RegExp(r'^(truyện|truyen)\s+'), '').trim();
    if (cleanA.isEmpty || cleanB.isEmpty) return false;
    if (cleanA == cleanB) return true;
    return cleanA.contains(cleanB) || cleanB.contains(cleanA);
  }

  /// Dừng tiến trình tải ngầm truyện
  void stopBackgroundCrawl() {
    _isBackgroundCrawling = false;
    _bgCrawlStoryTitle = null;
    _bgCrawlTaskId++;
    notifyListeners();
  }

  /// Bắt đầu crawl ngầm toàn bộ truyện: Tải các chương lớn hơn chương đang đọc trước, khi đến chương cuối mới tải lại các chương còn thiếu phía trước
  void startBackgroundStoryCrawl({
    required String baseUrl,
    required String storyTitle,
    required SettingsProvider settings,
    int? startChapter,
    int? maxChapters,
  }) {
    if (baseUrl.trim().isEmpty || storyTitle.trim().isEmpty) return;
    if (baseUrl.startsWith('file://')) return; // File offline không cần crawl

    _bgCrawlTaskId++;
    final currentTaskId = _bgCrawlTaskId;

    int effectiveStartChapter = startChapter ?? 1;
    if (startChapter == null) {
      if (_currentChapter != null && isSameStory(_currentChapter!.storyTitle, storyTitle)) {
        effectiveStartChapter = _currentChapter!.chapterNumber + 1;
      }
    }

    _isBackgroundCrawling = true;
    _bgCrawlStoryTitle = storyTitle;
    _bgCrawlBaseUrl = baseUrl;
    _bgCrawlCurrentChapter = effectiveStartChapter;
    _bgCrawlSuccessCount = 0;
    notifyListeners();

    _runBackgroundCrawlLoop(
      taskId: currentTaskId,
      baseUrl: baseUrl,
      storyTitle: storyTitle,
      settings: settings,
      startChapter: effectiveStartChapter,
      maxChapters: maxChapters,
    );
  }

  Future<void> _runBackgroundCrawlLoop({
    required int taskId,
    required String baseUrl,
    required String storyTitle,
    required SettingsProvider settings,
    required int startChapter,
    int? maxChapters,
  }) async {
    const int batchSize = 3; // Tải đồng thời 3 chương mỗi lượt để tăng tốc độ tải gấp 3-5 lần
    int consecutiveErrors = 0;
    int currentChapter = startChapter;

    // GIAI ĐOẠN 1: Tải các chương lớn hơn chương đang đọc về phía trước (startChapter -> hết truyện)
    while (_isBackgroundCrawling && taskId == _bgCrawlTaskId) {
      if (maxChapters != null && currentChapter > maxChapters) {
        break;
      }
      if (consecutiveErrors >= 15) {
        // Đã đến chương cuối cùng của truyện (404 hoặc hết chương liên tiếp)
        break;
      }

      // Nếu người dùng đang thao tác tải ưu tiên 1 chương nào đó -> tạm dừng worker ngầm nhường băng thông
      while (_bgCrawlPausedForPriority && _isBackgroundCrawling && taskId == _bgCrawlTaskId) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (!_isBackgroundCrawling || taskId != _bgCrawlTaskId) break;

      // Chuẩn bị danh sách batch các số chương cần tải
      final List<int> batchChapters = [];
      for (int i = 0; i < batchSize; i++) {
        final cNum = currentChapter + i;
        if (maxChapters != null && cNum > maxChapters) break;
        batchChapters.add(cNum);
      }
      if (batchChapters.isEmpty) break;

      _bgCrawlCurrentChapter = batchChapters.first;
      notifyListeners();

      // 1. Kiểm tra song song những chương đã có trong DB
      final checkFutures = batchChapters.map((cNum) async {
        final existing = await db.getChapterByStoryAndNumber(storyTitle, cNum);
        return MapEntry(cNum, existing != null && existing.content.trim().isNotEmpty);
      });
      final existingMap = Map.fromEntries(await Future.wait(checkFutures));
      final chaptersToFetch = batchChapters.where((cNum) => existingMap[cNum] != true).toList();

      if (chaptersToFetch.isEmpty) {
        currentChapter += batchChapters.length;
        consecutiveErrors = 0;
        continue;
      }

      // 2. Tải đồng thời các chương chưa có (có retry 1 lần nếu gặp lỗi mạng tạm thời)
      final fetchFutures = chaptersToFetch.map((cNum) async {
        for (int attempt = 0; attempt < 2; attempt++) {
          try {
            final targetUrl = crawlerService.buildChapterUrl(baseUrl, cNum);
            final crawledChapter = await crawlerService.fetchChapter(
              baseUrl: targetUrl.isNotEmpty ? targetUrl : baseUrl,
              chapterNumber: cNum,
            );
            if (crawledChapter.content.trim().length > 100) {
              return MapEntry(cNum, crawledChapter);
            }
          } catch (_) {
            if (attempt == 0) await Future.delayed(const Duration(milliseconds: 300));
          }
        }
        return MapEntry(cNum, null);
      });

      final fetchResults = await Future.wait(fetchFutures);
      if (!_isBackgroundCrawling || taskId != _bgCrawlTaskId) break;

      final List<ChapterModel> chaptersToInsert = [];
      final List<SavedAudioItem> audiosToInsert = [];

      for (final entry in fetchResults) {
        final chapter = entry.value;
        if (chapter != null) {
          final normalizedChapter = chapter.copyWith(storyTitle: storyTitle);
          chaptersToInsert.add(normalizedChapter);

          final audioItem = SavedAudioItem(
            id: 'audio_${normalizedChapter.id}',
            title: normalizedChapter.chapterTitle,
            storyTitle: storyTitle,
            chapterNumber: normalizedChapter.chapterNumber,
            audioPath: '',
            content: normalizedChapter.content,
            chapterId: normalizedChapter.id,
            voiceUsed: settings.currentVoice.name,
          );
          audiosToInsert.add(audioItem);

          consecutiveErrors = 0;
        } else {
          consecutiveErrors++;
        }
      }

      if (chaptersToInsert.isNotEmpty) {
        await db.insertChaptersBatch(chaptersToInsert);
        await db.insertAudiosBatch(audiosToInsert);

        for (final audioItem in audiosToInsert) {
          _savedAudios.removeWhere((a) =>
              isSameStory(a.storyTitle, storyTitle) &&
              a.chapterNumber == audioItem.chapterNumber);
          _savedAudios.insert(0, audioItem);
        }
        for (final chapterItem in chaptersToInsert) {
          _historyChapters.removeWhere((c) =>
              isSameStory(c.storyTitle, storyTitle) &&
              c.chapterNumber == chapterItem.chapterNumber);
          _historyChapters.insert(0, chapterItem);
        }

        _bgCrawlSuccessCount += chaptersToInsert.length;
        _bgCrawlCurrentChapter = chaptersToInsert.last.chapterNumber;
        notifyListeners();
      }

      currentChapter += batchChapters.length;
      // Delay ngắn giữa các batch để giữ băng thông mượt mà
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // GIAI ĐOẠN 2: Khi đã tải đến chương cuối cùng -> Tải lại các chương còn thiếu từ chương 1 đến trước startChapter
    if (_isBackgroundCrawling && taskId == _bgCrawlTaskId && startChapter > 1) {
      final List<int> missingChapters = [];
      for (int cNum = 1; cNum < startChapter; cNum++) {
        final existing = await db.getChapterByStoryAndNumber(storyTitle, cNum);
        if (existing == null || existing.content.trim().isEmpty) {
          missingChapters.add(cNum);
        }
      }

      for (int i = 0; i < missingChapters.length; i += batchSize) {
        if (!_isBackgroundCrawling || taskId != _bgCrawlTaskId) break;

        while (_bgCrawlPausedForPriority && _isBackgroundCrawling && taskId == _bgCrawlTaskId) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        if (!_isBackgroundCrawling || taskId != _bgCrawlTaskId) break;

        final batch = missingChapters.sublist(
          i,
          (i + batchSize < missingChapters.length) ? i + batchSize : missingChapters.length,
        );

        _bgCrawlCurrentChapter = batch.first;
        notifyListeners();

        final fetchFutures = batch.map((cNum) async {
          for (int attempt = 0; attempt < 2; attempt++) {
            try {
              final targetUrl = crawlerService.buildChapterUrl(baseUrl, cNum);
              final crawledChapter = await crawlerService.fetchChapter(
                baseUrl: targetUrl.isNotEmpty ? targetUrl : baseUrl,
                chapterNumber: cNum,
              );
              if (crawledChapter.content.trim().length > 100) {
                return MapEntry(cNum, crawledChapter);
              }
            } catch (_) {
              if (attempt == 0) await Future.delayed(const Duration(milliseconds: 300));
            }
          }
          return MapEntry(cNum, null);
        });

        final results = await Future.wait(fetchFutures);
        if (!_isBackgroundCrawling || taskId != _bgCrawlTaskId) break;

        final List<ChapterModel> chaptersToInsert = [];
        final List<SavedAudioItem> audiosToInsert = [];

        for (final entry in results) {
          final chapter = entry.value;
          if (chapter != null) {
            final normalizedChapter = chapter.copyWith(storyTitle: storyTitle);
            chaptersToInsert.add(normalizedChapter);

            final audioItem = SavedAudioItem(
              id: 'audio_${normalizedChapter.id}',
              title: normalizedChapter.chapterTitle,
              storyTitle: storyTitle,
              chapterNumber: normalizedChapter.chapterNumber,
              audioPath: '',
              content: normalizedChapter.content,
              chapterId: normalizedChapter.id,
              voiceUsed: settings.currentVoice.name,
            );
            audiosToInsert.add(audioItem);
          }
        }

        if (chaptersToInsert.isNotEmpty) {
          await db.insertChaptersBatch(chaptersToInsert);
          await db.insertAudiosBatch(audiosToInsert);

          for (final audioItem in audiosToInsert) {
            _savedAudios.removeWhere((a) =>
                isSameStory(a.storyTitle, storyTitle) &&
                a.chapterNumber == audioItem.chapterNumber);
            _savedAudios.insert(0, audioItem);
          }
          for (final chapterItem in chaptersToInsert) {
            _historyChapters.removeWhere((c) =>
                isSameStory(c.storyTitle, storyTitle) &&
                c.chapterNumber == chapterItem.chapterNumber);
            _historyChapters.insert(0, chapterItem);
          }

          _bgCrawlSuccessCount += chaptersToInsert.length;
          notifyListeners();
        }

        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (taskId == _bgCrawlTaskId) {
      _isBackgroundCrawling = false;
      notifyListeners();
    }
  }

  /// Nhập truyện từ file (TXT, EPUB,...) và mở truyện đọc ngay lập tức
  Future<bool> importStoryFromFile({
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) async {
    try {
      _isImportingFile = true;
      notifyListeners();

      final result = await storyImportService.pickAndImportStory();
      if (result == null) {
        _isImportingFile = false;
        notifyListeners();
        return false;
      }

      // Lưu hàng loạt chương vào database bằng Transaction Batch
      await db.insertChaptersBatch(result.chapters);

      // Tạo và lưu danh sách SavedAudioItem
      final audioItems = result.chapters.map((chap) => SavedAudioItem(
        id: 'audio_${chap.id}',
        title: chap.chapterTitle,
        storyTitle: chap.storyTitle,
        chapterNumber: chap.chapterNumber,
        audioPath: '',
        content: chap.content,
        chapterId: chap.id,
        voiceUsed: settings.currentVoice.name,
      )).toList();

      await db.insertAudiosBatch(audioItems);

      // Cập nhật danh sách _savedAudios và _historyChapters
      _savedAudios = await db.getAllSavedAudios();
      _historyChapters = await db.getAllChapters();

      _isImportingFile = false;
      notifyListeners();

      // Mở truyện mới nhập ra đọc ngay tại chương 1
      await selectStory(result.storyTitle, settings: settings, player: player);

      return true;
    } catch (e) {
      _isImportingFile = false;
      notifyListeners();
      return false;
    }
  }

  /// Chọn một truyện từ kho truyện (tự động tải chương đang đọc gần nhất hoặc chương 1)
  Future<void> selectStory(
    String storyTitle, {
    required SettingsProvider settings,
    required PlayerStateProvider player,
    int? targetChapterNumber,
  }) async {
    final cleanTitle = storyTitle.trim().toLowerCase();
    final storyChapters = _savedAudios
        .where((a) => a.storyTitle.trim().toLowerCase() == cleanTitle)
        .toList();

    if (storyChapters.isEmpty) {
      final dbChapters = await db.getChaptersByStory(storyTitle);
      if (dbChapters.isNotEmpty) {
        final firstChap = dbChapters.first;
        final targetNum = targetChapterNumber ?? firstChap.chapterNumber;
        chapterController.text = targetNum.toString();
        if (firstChap.sourceUrl.isNotEmpty) {
          urlController.text = firstChap.sourceUrl;
        }
        await reloadCurrentChapter(settings: settings, player: player);
        return;
      }
      return;
    }

    storyChapters.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    SavedAudioItem targetItem = storyChapters.first;

    if (targetChapterNumber != null) {
      final match = storyChapters.where((c) => c.chapterNumber == targetChapterNumber).toList();
      if (match.isNotEmpty) targetItem = match.first;
    } else {
      // Tìm chương đọc gần nhất
      SavedAudioItem? latestPlayed;
      for (final c in storyChapters) {
        if (c.lastPlayedAt != null) {
          if (latestPlayed == null || c.lastPlayedAt!.isAfter(latestPlayed.lastPlayedAt!)) {
            latestPlayed = c;
          }
        }
      }
      if (latestPlayed != null) {
        targetItem = latestPlayed;
      }
    }

    await loadSavedChapter(
      targetItem,
      settings: settings,
      player: player,
      focusLastPlayed: true,
    );
  }

  /// Nạp lại truyện/chương đã đọc lần trước nếu hiện tại chưa có chương nào đang mở
  Future<bool> loadLastPlayedOrRecent({
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) async {
    if (_currentChapter != null) return true;

    // 1. Kiểm tra truyện đọc gần nhất được lưu trong SharedPreferences / state
    if (_lastPlayedStoryTitle != null && _lastPlayedStoryTitle!.trim().isNotEmpty) {
      final title = _lastPlayedStoryTitle!.trim();
      final targetNum = _lastPlayedChapterNumber;
      await selectStory(title, settings: settings, player: player, targetChapterNumber: targetNum);
      if (_currentChapter != null) return true;
    }

    // 2. Kiểm tra chương đọc gần nhất trong _savedAudios
    if (_savedAudios.isNotEmpty) {
      final sorted = List<SavedAudioItem>.from(_savedAudios);
      sorted.sort((a, b) {
        if (a.lastPlayedAt != null && b.lastPlayedAt != null) {
          return b.lastPlayedAt!.compareTo(a.lastPlayedAt!);
        }
        if (a.lastPlayedAt != null) return -1;
        if (b.lastPlayedAt != null) return 1;
        return 0;
      });
      final item = sorted.first;
      await loadSavedChapter(item, settings: settings, player: player, focusLastPlayed: true);
      if (_currentChapter != null) return true;
    }

    // 3. Kiểm tra trong DB nếu _savedAudios chưa nạp
    final allAudios = await db.getAllSavedAudios();
    if (allAudios.isNotEmpty) {
      allAudios.sort((a, b) {
        if (a.lastPlayedAt != null && b.lastPlayedAt != null) {
          return b.lastPlayedAt!.compareTo(a.lastPlayedAt!);
        }
        if (a.lastPlayedAt != null) return -1;
        if (b.lastPlayedAt != null) return 1;
        return 0;
      });
      final item = allAudios.first;
      await loadSavedChapter(item, settings: settings, player: player, focusLastPlayed: true);
      if (_currentChapter != null) return true;
    }

    return false;
  }

  /// Chuyển thẳng đến chương được chỉ định (Ưu tiên nạp từ đã lưu nếu có, nếu chưa có thì tải ưu tiên ngay lập tức)
  Future<void> changeToChapter(
    int chapterNumber, {
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) async {
    chapterController.text = chapterNumber.toString();
    final currentUrl = urlController.text.trim();
    if (currentUrl.isNotEmpty && !currentUrl.startsWith('file://')) {
      final updatedUrl = crawlerService.buildChapterUrl(currentUrl, chapterNumber);
      if (updatedUrl.isNotEmpty) {
        urlController.text = updatedUrl;
      }
    }
    notifyListeners();

    // 1. Kiểm tra trong danh sách Đã lưu
    final savedItem = await _findSavedAudio(chapterNumber, _currentChapter?.storyTitle);
    if (savedItem != null) {
      await loadSavedChapter(
        savedItem,
        settings: settings,
        player: player,
        focusLastPlayed: true,
      );
      return;
    }

    // 2. Nếu chưa có, tải trực tiếp chương này với độ ưu tiên cao nhất
    await reloadCurrentChapter(
      settings: settings,
      player: player,
      forceRefresh: true,
    );
  }

  /// Lấy danh sách tất cả các chương đã lưu của truyện hiện tại
  Future<List<SavedAudioItem>> getChaptersForCurrentStory() async {
    final storyTitle = _currentChapter?.storyTitle ?? _lastPlayedStoryTitle ?? '';
    if (storyTitle.trim().isEmpty) return [];

    final clean = storyTitle.trim().toLowerCase();
    final list = _savedAudios.where((a) => a.storyTitle.trim().toLowerCase() == clean).toList();
    list.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    return list;
  }

  /// Tăng/giảm số chương
  void changeChapter(int delta) {
    int? current = int.tryParse(chapterController.text.trim());
    if (current != null) {
      int next = current + delta;
      if (next < 1) next = 1;
      chapterController.text = next.toString();
      final currentUrl = urlController.text.trim();
      if (currentUrl.isNotEmpty) {
        final updatedUrl = crawlerService.buildChapterUrl(currentUrl, next);
        if (updatedUrl.isNotEmpty) {
          urlController.text = updatedUrl;
        }
      }
      notifyListeners();
    }
  }

  void setChapter(String val) {
    chapterController.text = val;
    notifyListeners();
  }

  /// Tìm kiếm một chương trong danh sách Đã Lưu (in-memory hoặc database) theo tên truyện và số chương
  Future<SavedAudioItem?> _findSavedAudio(int chapterNum, [String? storyTitle]) async {
    final cleanStoryTitle = storyTitle?.trim();

    if (cleanStoryTitle != null && cleanStoryTitle.isNotEmpty) {
      final memoryMatch = _savedAudios.where((a) {
        return a.chapterNumber == chapterNum &&
            isSameStory(a.storyTitle, cleanStoryTitle);
      }).toList();

      if (memoryMatch.isNotEmpty) {
        return memoryMatch.first;
      }

      final dbMatch = await db.getSavedAudioByStoryAndNumber(cleanStoryTitle, chapterNum);
      if (dbMatch != null) return dbMatch;

      final allAudios = await db.getAllSavedAudios();
      for (final a in allAudios) {
        if (a.chapterNumber == chapterNum && isSameStory(a.storyTitle, cleanStoryTitle)) {
          return a;
        }
      }
      return null;
    }

    return null;
  }

  /// Nút [<] Chương trước (Ưu tiên nạp từ Đã Lưu nếu có)
  Future<void> goToPreviousChapter({
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) async {
    await player.stop(resetPause: false);
    _generationSessionId++; // Hủy tiến trình tạo câu cũ

    final currentNum = _currentChapter?.chapterNumber ?? int.tryParse(chapterController.text.trim()) ?? 1;
    final prevChapterNum = currentNum > 1 ? currentNum - 1 : 1;
    chapterController.text = prevChapterNum.toString();
    final storyTitle = _currentChapter?.storyTitle ?? '';

    final savedItem = await _findSavedAudio(prevChapterNum, storyTitle);
    if (savedItem != null) {
      await loadSavedChapter(
        savedItem,
        settings: settings,
        player: player,
        focusLastPlayed: true,
        autoPlay: false,
      );
      return;
    }

    await reloadCurrentChapter(
      settings: settings,
      player: player,
      autoPlay: false,
    );
  }

  /// Nút [>] Chương sau (Ưu tiên nạp từ Bộ nhớ đệm Preloaded / Đã Lưu để chuyển ngay tức thì 0s delay)
  Future<void> goToNextChapter({
    required SettingsProvider settings,
    required PlayerStateProvider player,
    bool isAutoNext = false,
  }) async {
    final wasPlaying = player.isPlaying;
    // Chỉ tự phát tiếp khi chuyển tự động khi nghe hết chương (isAutoNext) VÀ người dùng không bấm pause
    final shouldAutoPlay = isAutoNext && !player.isPausedByUser && wasPlaying;
    await player.stop(resetPause: false);
    _generationSessionId++; // Hủy tiến trình tạo câu cũ

    final currentNum = _currentChapter?.chapterNumber ?? int.tryParse(chapterController.text.trim()) ?? 1;
    final nextChapterNum = currentNum + 1;
    chapterController.text = nextChapterNum.toString();
    final storyTitle = _currentChapter?.storyTitle ?? '';

    // 1. Kiểm tra xem chương tiếp theo đã được tải trước trong bộ nhớ đệm (_preloadedNextChapter) -> CHUYỂN THẲNG NGAY TỨC THÌ
    if (_preloadedNextChapter != null &&
        _preloadedNextChapter!.chapter.chapterNumber == nextChapterNum &&
        (storyTitle.isEmpty || _preloadedNextChapter!.chapter.storyTitle.toLowerCase().trim() == storyTitle.toLowerCase().trim())) {
      final preloaded = _preloadedNextChapter!;
      _preloadedNextChapter = null;
      _isPreloadingNext = false;
      _preloadingChapterNumber = null;
      _inFlightPreloadFuture = null;

      _currentChapter = preloaded.chapter;
      _currentSummary = preloaded.summary;
      _summarySentences = preloaded.summarySentences;
      _contentSentences = preloaded.contentSentences;

      _currentSummarySentenceIndex = getEffectiveSentenceIndex(preloaded.chapter.lastPlayedSummaryIndex, _summarySentences.length);
      _currentContentSentenceIndex = getEffectiveSentenceIndex(preloaded.chapter.lastPlayedContentIndex, _contentSentences.length);
      _activeSentenceIndex = _activeAudioSource == AudioSourceType.summary ? _currentSummarySentenceIndex : _currentContentSentenceIndex;

      if (preloaded.chapter.sourceUrl.isNotEmpty) {
        urlController.text = preloaded.chapter.sourceUrl;
      } else {
        final updatedUrl = crawlerService.buildChapterUrl(urlController.text.trim(), nextChapterNum);
        if (updatedUrl.isNotEmpty) {
          urlController.text = updatedUrl;
        }
      }

      _headerTitle = _formatChapterHeader(preloaded.chapter);
      _currentStatusMessage = '';
      _overallProgress = 1.0;

      _isProcessing = false;
      notifyListeners();

      // Nếu chuyển chương tự động khi nghe hết chương trước -> tiếp tục phát tiếp
      if (shouldAutoPlay) {
        _startSequentialGeneration(
          chapter: preloaded.chapter,
          settings: settings,
          player: player,
          startIndex: _activeSentenceIndex ?? 0,
        );

        if (_activeAudioSource == AudioSourceType.summary && _summarySentences.isEmpty && _currentChapter != null) {
          await summarizeCurrentChapter(settings);
        }
        final targetList = _activeAudioSource == AudioSourceType.summary ? _summarySentences : _contentSentences;
        if (targetList.isNotEmpty) {
          final startIdx = _activeSentenceIndex ?? 0;
          await playSentence(
            sourceType: _activeAudioSource,
            sentenceIndex: startIdx,
            settings: settings,
            player: player,
          );
        }
      }

      // Tiếp tục tải ngầm chương kế tiếp
      _preloadNextChapter(settings: settings, player: player);
      return;
    }

    // 2. Kiểm tra xem chương tiếp theo ĐÃ CÓ TRONG MỤC ĐÃ LƯU chưa
    final savedItem = await _findSavedAudio(nextChapterNum, storyTitle);
    if (savedItem != null) {
      await loadSavedChapter(
        savedItem,
        settings: settings,
        player: player,
        focusLastPlayed: true,
        autoPlay: shouldAutoPlay,
      );
      return;
    }

    // 3. Nếu đang có luồng tải ngầm cho đúng chương này -> chờ tải xong rồi hiển thị
    if (_isPreloadingNext && _preloadingChapterNumber == nextChapterNum && _inFlightPreloadFuture != null) {
      _isProcessing = true;
      _headerTitle = 'Đang tải Chương $nextChapterNum...';
      _currentStatusMessage = 'Đang tải dữ liệu chương $nextChapterNum...';
      notifyListeners();
      await _inFlightPreloadFuture;

      if (_preloadedNextChapter != null && _preloadedNextChapter!.chapter.chapterNumber == nextChapterNum) {
        await goToNextChapter(settings: settings, player: player, isAutoNext: isAutoNext);
        return;
      }
    }

    await reloadCurrentChapter(settings: settings, player: player, autoPlay: shouldAutoPlay);
  }

  /// Nút [🔄] Tải lại / Lấy dữ liệu chương hiện tại (ưu tiên nạp từ đã lưu nếu có sẵn)
  Future<void> reloadCurrentChapter({
    required SettingsProvider settings,
    required PlayerStateProvider player,
    bool forceRefresh = false,
    bool? autoPlay,
  }) async {
    final shouldAutoPlay = (autoPlay ?? false) && !player.isPausedByUser;
    if (_isProcessing) return;

    final inputUrl = urlController.text.trim();
    final chapterInput = chapterController.text.trim();
    final chapterNum = int.tryParse(chapterInput) ?? 1;

    if (inputUrl.isEmpty) {
      _currentStatusMessage = 'Vui lòng nhập Link truyện!';
      _headerTitle = 'Chưa có link truyện';
      notifyListeners();
      return;
    }

    // Nếu không phải forceRefresh, kiểm tra xem chương đã có trong Đã Lưu chưa để load ngay lập tức 0s
    if (!forceRefresh) {
      final savedItem = await _findSavedAudio(chapterNum, _currentChapter?.storyTitle);
      if (savedItem != null && ((savedItem.content?.isNotEmpty == true) || (savedItem.summaryText?.isNotEmpty == true))) {
        await loadSavedChapter(
          savedItem,
          settings: settings,
          player: player,
          focusLastPlayed: false,
          autoPlay: shouldAutoPlay,
        );
        return;
      }
    }

    final targetUrl = crawlerService.buildChapterUrl(inputUrl, chapterNum);
    if (targetUrl.isNotEmpty && urlController.text != targetUrl) {
      urlController.text = targetUrl;
    }

    await player.stop(resetPause: false);
    _generationSessionId++; // Hủy tiến trình tạo cũ
    _activeSentenceIndex = null;

    _isProcessing = true;
    _headerTitle = 'Đang tải Chương $chapterNum...';
    _currentStatusMessage = 'Đang crawl dữ liệu thuần chương $chapterNum...';
    _overallProgress = 0.1;
    notifyListeners();

    _bgCrawlPausedForPriority = true;
    try {
      // 1. Crawl nội dung sạch
      var chapter = await crawlerService.fetchChapter(
        baseUrl: targetUrl.isNotEmpty ? targetUrl : inputUrl,
        chapterNumber: chapterNum,
      );

      // Dịch nội dung sang tiếng Việt nếu được bật
      if (settings.translateContent) {
        _overallProgress = 0.25;
        _currentStatusMessage = 'Đang dịch nội dung sang tiếng Việt...';
        notifyListeners();

        final translated = await summaryService.translateText(
          text: chapter.content,
          apiKeys: settings.workingApiKeys,
          modelName: settings.selectedModel,
          domain: settings.currentProviderDomain,
          providerName: settings.aiProvider,
          providerId: settings.activeProviderId,
          customPrompt: settings.translatePrompt,
          onKeyFailed: (failedKey) => settings.markKeyFailed(failedKey),
        );

        chapter = chapter.copyWith(
          content: translated,
          wordCount: translated.split(RegExp(r'\s+')).length,
        );
      }

      _currentChapter = chapter;
      _headerTitle = _formatChapterHeader(chapter);
      await db.insertChapter(chapter);
      _historyChapters.removeWhere((c) => isSameStory(c.storyTitle, chapter.storyTitle) && c.chapterNumber == chapter.chapterNumber);
      _historyChapters.insert(0, chapter);

      // Tách câu nội dung ngay lập tức từ dữ liệu crawl được & gắn audio có sẵn
      final rawContent = buildSentenceListWithHeader(chapter.content, chapter);
      _contentSentences = await _attachExistingAudioFiles(
        sentences: rawContent,
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        type: 'content',
        voiceId: settings.selectedVoiceId,
      );

      // Kiểm tra xem đã có bản tóm tắt trong DB chưa để hiển thị sẵn
      final existingSummary = await db.getSummaryByChapterId(chapter.id);
      if (existingSummary != null && existingSummary.summaryText.trim().isNotEmpty) {
        _currentSummary = existingSummary;
        final rawSummary = buildSentenceListWithHeader(existingSummary.summaryText, chapter);
        _summarySentences = await _attachExistingAudioFiles(
          sentences: rawSummary,
          storyTitle: chapter.storyTitle,
          chapterNumber: chapter.chapterNumber,
          type: 'summary',
          voiceId: settings.selectedVoiceId,
        );
      } else {
        _currentSummary = null;
        _summarySentences = [];
      }

      await _saveOrUpdateAudioItem(chapter, _currentSummary, settings);

      _currentSummarySentenceIndex = getEffectiveSentenceIndex(chapter.lastPlayedSummaryIndex, _summarySentences.length);
      _currentContentSentenceIndex = getEffectiveSentenceIndex(chapter.lastPlayedContentIndex, _contentSentences.length);
      _activeSentenceIndex = _activeAudioSource == AudioSourceType.summary
          ? _currentSummarySentenceIndex
          : _currentContentSentenceIndex;

      _overallProgress = 1.0;
      _isProcessing = false;
      _currentStatusMessage = '';
      notifyListeners();

      // Tự động tải ngầm trước chương kế tiếp
      _preloadNextChapter(settings: settings, player: player);

      // Tự động phát nếu đang bật autoplay và không pause
      if (shouldAutoPlay) {
        _startSequentialGeneration(
          chapter: chapter,
          settings: settings,
          player: player,
          startIndex: _activeSentenceIndex ?? 0,
        );

        if (_activeAudioSource == AudioSourceType.summary && _summarySentences.isEmpty) {
          await summarizeCurrentChapter(settings);
        }
        final targetList = _activeAudioSource == AudioSourceType.summary ? _summarySentences : _contentSentences;
        if (targetList.isNotEmpty) {
          final startIdx = _activeSentenceIndex ?? 0;
          playSentence(
            sourceType: _activeAudioSource,
            sentenceIndex: startIdx,
            settings: settings,
            player: player,
          );
        }
      }
    } catch (e) {
      _isProcessing = false;
      _currentStatusMessage = 'Lỗi tải chương: $e';
      _headerTitle = 'Lỗi tải Chương $chapterNum';
      notifyListeners();
    } finally {
      _bgCrawlPausedForPriority = false;
    }
  }

  /// Helper lưu hoặc cập nhật SavedAudioItem
  Future<void> _saveOrUpdateAudioItem(ChapterModel chapter, SummaryModel? summary, SettingsProvider settings) async {
    final audioItem = SavedAudioItem(
      id: 'audio_${chapter.id}',
      title: chapter.chapterTitle,
      storyTitle: chapter.storyTitle,
      chapterNumber: chapter.chapterNumber,
      audioPath: '',
      summaryText: summary?.summaryText ?? '',
      content: chapter.content,
      chapterId: chapter.id,
      voiceUsed: settings.currentVoice.name,
      lastPlayedSentenceIndex: chapter.lastPlayedSentenceIndex,
      lastPlayedSummaryIndex: chapter.lastPlayedSummaryIndex,
      lastPlayedContentIndex: chapter.lastPlayedContentIndex,
      lastPlayedSource: chapter.lastPlayedSource,
      lastPlayedAt: chapter.lastPlayedAt,
    );

    await db.insertAudio(audioItem);
    _savedAudios.removeWhere((a) => isSameStory(a.storyTitle, chapter.storyTitle) && a.chapterNumber == chapter.chapterNumber);
    _savedAudios.insert(0, audioItem);
    notifyListeners();
  }

  /// Lưu vị trí câu cuối đã phát vào SQLite và SharedPreferences (lưu riêng cho Tóm tắt & Nội dung)
  Future<void> _saveLastPlayedPosition({
    required String storyTitle,
    required int chapterNumber,
    required int sentenceIndex,
    required AudioSourceType sourceType,
    String? storyUrl,
  }) async {
    try {
      if (sourceType == AudioSourceType.summary) {
        _currentSummarySentenceIndex = sentenceIndex;
      } else {
        _currentContentSentenceIndex = sentenceIndex;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyLastPlayedStory, storyTitle);
      await prefs.setInt(AppConstants.keyLastPlayedChapter, chapterNumber);
      await prefs.setInt(AppConstants.keyLastPlayedSentenceIndex, sentenceIndex);
      await prefs.setString(AppConstants.keyLastPlayedSource, sourceType.name);
      if (storyUrl != null && storyUrl.isNotEmpty) {
        await prefs.setString(AppConstants.keyLastPlayedStoryUrl, storyUrl);
      }

      // Per-chapter key
      final cleanStory = storyTitle.trim().toLowerCase();
      final chapterKey = 'last_sentence_${cleanStory}_$chapterNumber';
      final sourceKey = 'last_source_${cleanStory}_$chapterNumber';
      final summaryKey = 'last_summary_idx_${cleanStory}_$chapterNumber';
      final contentKey = 'last_content_idx_${cleanStory}_$chapterNumber';

      await prefs.setInt(chapterKey, sentenceIndex);
      await prefs.setString(sourceKey, sourceType.name);
      if (sourceType == AudioSourceType.summary) {
        await prefs.setInt(summaryKey, sentenceIndex);
      } else {
        await prefs.setInt(contentKey, sentenceIndex);
      }

      // Cập nhật Database SQLite
      await db.updateLastPlayedPosition(
        storyTitle: storyTitle,
        chapterNumber: chapterNumber,
        sentenceIndex: sentenceIndex,
        sourceType: sourceType.name,
      );

      // Cập nhật in-memory list
      final audioIdx = _savedAudios.indexWhere(
        (a) => a.storyTitle.trim().toLowerCase() == cleanStory && a.chapterNumber == chapterNumber,
      );
      if (audioIdx != -1) {
        final old = _savedAudios[audioIdx];
        _savedAudios[audioIdx] = old.copyWith(
          lastPlayedSentenceIndex: sentenceIndex,
          lastPlayedSummaryIndex: sourceType == AudioSourceType.summary ? sentenceIndex : old.lastPlayedSummaryIndex,
          lastPlayedContentIndex: sourceType == AudioSourceType.content ? sentenceIndex : old.lastPlayedContentIndex,
          lastPlayedSource: sourceType.name,
          lastPlayedAt: DateTime.now(),
        );
      }
    } catch (e) {
      print('Lỗi lưu vị trí câu cuối: $e');
    }
  }

  /// Tổng hợp TTS cho một câu đơn lẻ
  /// Xử lý đồng bộ lại trạng thái âm thanh và tự động tạo audio khi người dùng đổi giọng đọc
  Future<void> onVoiceChanged({
    required SettingsProvider settings,
    PlayerStateProvider? player,
  }) async {
    // 1. Tạm dừng phát nếu đang phát
    if (player != null && player.isPlaying) {
      await player.stop();
      player.resetManualPause();
    }

    // 2. Hủy tiến trình tạo audio của giọng cũ
    ++_generationSessionId;

    if (_currentChapter == null) {
      notifyListeners();
      return;
    }

    // 3. Quét lại audio của giọng mới cho tóm tắt & nội dung
    if (_summarySentences.isNotEmpty) {
      _summarySentences = await _attachExistingAudioFiles(
        sentences: _summarySentences.map((s) => s.copyWith(audioPath: null, isGenerating: false, hasError: false)).toList(),
        storyTitle: _currentChapter!.storyTitle,
        chapterNumber: _currentChapter!.chapterNumber,
        type: 'summary',
        voiceId: settings.selectedVoiceId,
      );
    }

    if (_contentSentences.isNotEmpty) {
      _contentSentences = await _attachExistingAudioFiles(
        sentences: _contentSentences.map((s) => s.copyWith(audioPath: null, isGenerating: false, hasError: false)).toList(),
        storyTitle: _currentChapter!.storyTitle,
        chapterNumber: _currentChapter!.chapterNumber,
        type: 'content',
        voiceId: settings.selectedVoiceId,
      );
    }

    notifyListeners();

    // 4. Nếu đang phát và không pause, khởi chạy tiến trình sinh audio cho tab đang chọn
    if (player != null && player.isPlaying && !player.isPausedByUser) {
      _startSequentialGeneration(
        chapter: _currentChapter!,
        settings: settings,
        player: player,
        startIndex: 0,
      );
    }
  }

  /// Tổng hợp TTS cho một câu đơn lẻ
  Future<String?> _synthesizeSingleSentence({
    required SentenceItem sentence,
    required ChapterModel chapter,
    required SettingsProvider settings,
    required String audioType,
  }) async {
    try {
      final voice = settings.currentVoice;
      final extension = UnifiedTtsService.getAudioExtension(voice);

      final expectedPath = await AudioExporter.generateSentenceAudioFilePath(
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        type: audioType,
        sentenceIndex: sentence.index,
        sentenceText: sentence.text,
        voiceId: settings.selectedVoiceId,
        extension: extension,
      );

      final file = File(expectedPath);
      if (await file.exists() && await file.length() > 500) {
        return expectedPath;
      }

      String cleanText = TextNormalizer.normalize(sentence.text).replaceAll('•', '').trim();
      if (cleanText.isEmpty || !RegExp(r'[a-zA-Z0-9\u00C0-\u1EF9]').hasMatch(cleanText)) {
        return null;
      }

      final result = await unifiedTtsService.synthesize(
        text: cleanText,
        voice: voice,
        outputFilePath: expectedPath,
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        audioType: '${audioType}_s${sentence.index}',
        speed: settings.speed,
      );
      return result.audioFilePath;
    } catch (e) {
      print('Lỗi synthesize câu ${sentence.index} ($audioType): $e');
      return null;
    }
  }

  /// Tiến trình chạy ngầm sinh audio cho phần đang được chọn (tóm tắt hoặc nội dung)
  void _startSequentialGeneration({
    required ChapterModel chapter,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    int startIndex = 0,
  }) {
    if (!player.isPlaying || player.isPausedByUser) return;
    final sessionId = ++_generationSessionId;

    if (_activeAudioSource == AudioSourceType.summary && _summarySentences.isNotEmpty) {
      _startSummaryAudioGeneration(
        chapter: chapter,
        settings: settings,
        player: player,
        sessionId: sessionId,
        startIndex: startIndex,
      );
    } else if (_contentSentences.isNotEmpty) {
      _startContentAudioGeneration(
        chapter: chapter,
        settings: settings,
        player: player,
        sessionId: sessionId,
        startIndex: startIndex,
      );
    }
  }

  /// Tiến trình tạo audio riêng cho các câu tóm tắt (tải trước số câu theo setting prefetch)
  void _startSummaryAudioGeneration({
    required ChapterModel chapter,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required int sessionId,
    int startIndex = 0,
  }) {
    if (!player.isPlaying || player.isPausedByUser) return;
    Future.microtask(() async {
      final prefetchLimit = settings.audioPrefetchCount;
      final maxIndex = (startIndex + prefetchLimit < _summarySentences.length)
          ? startIndex + prefetchLimit
          : _summarySentences.length - 1;

      for (int i = startIndex; i <= maxIndex; i++) {
        if (sessionId != _generationSessionId || !player.isPlaying || player.isPausedByUser || i >= _summarySentences.length) return;

        final voice = settings.currentVoice;
        final extension = UnifiedTtsService.getAudioExtension(voice);

        final expectedPath = await AudioExporter.generateSentenceAudioFilePath(
          storyTitle: chapter.storyTitle,
          chapterNumber: chapter.chapterNumber,
          type: 'summary',
          sentenceIndex: i,
          sentenceText: _summarySentences[i].text,
          voiceId: settings.selectedVoiceId,
          extension: extension,
        );
        if (await File(expectedPath).exists() && await File(expectedPath).length() > 500) {
          _summarySentences[i] = _summarySentences[i].copyWith(audioPath: expectedPath);
          notifyListeners();
        } else if (!_summarySentences[i].hasAudio && !_summarySentences[i].isGenerating) {
          _summarySentences[i] = _summarySentences[i].copyWith(isGenerating: true);
          notifyListeners();

          final path = await _synthesizeSingleSentence(
            sentence: _summarySentences[i],
            chapter: chapter,
            settings: settings,
            audioType: 'summary',
          );

          if (sessionId != _generationSessionId || !player.isPlaying || player.isPausedByUser) return;

          _summarySentences[i] = _summarySentences[i].copyWith(
            audioPath: path,
            isGenerating: false,
            hasError: path == null,
          );
          notifyListeners();

          // Nghỉ nhẹ 50ms giữa các câu để CPU/GPU nhường luồng mượt mà cho UI
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    });
  }

  /// Tiến trình tạo audio riêng cho các câu toàn văn nội dung (tải trước số câu theo setting prefetch)
  void _startContentAudioGeneration({
    required ChapterModel chapter,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required int sessionId,
    int startIndex = 0,
  }) {
    if (!player.isPlaying || player.isPausedByUser) return;
    Future.microtask(() async {
      final prefetchLimit = settings.audioPrefetchCount;
      final maxIndex = (startIndex + prefetchLimit < _contentSentences.length)
          ? startIndex + prefetchLimit
          : _contentSentences.length - 1;

      for (int i = startIndex; i <= maxIndex; i++) {
        if (sessionId != _generationSessionId || !player.isPlaying || player.isPausedByUser || i >= _contentSentences.length) return;

        final voice = settings.currentVoice;
        final extension = UnifiedTtsService.getAudioExtension(voice);

        final expectedPath = await AudioExporter.generateSentenceAudioFilePath(
          storyTitle: chapter.storyTitle,
          chapterNumber: chapter.chapterNumber,
          type: 'content',
          sentenceIndex: i,
          sentenceText: _contentSentences[i].text,
          voiceId: settings.selectedVoiceId,
          extension: extension,
        );
        if (await File(expectedPath).exists() && await File(expectedPath).length() > 500) {
          _contentSentences[i] = _contentSentences[i].copyWith(audioPath: expectedPath);
          notifyListeners();
        } else if (!_contentSentences[i].hasAudio && !_contentSentences[i].isGenerating) {
          _contentSentences[i] = _contentSentences[i].copyWith(isGenerating: true);
          notifyListeners();

          final path = await _synthesizeSingleSentence(
            sentence: _contentSentences[i],
            chapter: chapter,
            settings: settings,
            audioType: 'content',
          );

          if (sessionId != _generationSessionId || !player.isPlaying || player.isPausedByUser) return;

          _contentSentences[i] = _contentSentences[i].copyWith(
            audioPath: path,
            isGenerating: false,
            hasError: path == null,
          );
          notifyListeners();

          // Nghỉ nhẹ 50ms giữa các câu để CPU/GPU nhường luồng mượt mà cho UI
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    });
  }

  /// Đảm bảo nạp trước buffer âm thanh cho các câu kế tiếp (Lookahead theo prefetchCount)
  void ensureLookaheadAudio({
    required AudioSourceType sourceType,
    required int fromIndex,
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) {
    if (_currentChapter == null || !player.isPlaying || player.isPausedByUser) return;
    final sessionId = _generationSessionId;
    final list = sourceType == AudioSourceType.summary ? _summarySentences : _contentSentences;
    final prefetchLimit = settings.audioPrefetchCount;
    final maxIndex = (fromIndex + prefetchLimit < list.length) ? fromIndex + prefetchLimit : list.length - 1;

    Future.microtask(() async {
      for (int i = fromIndex; i <= maxIndex; i++) {
        if (sessionId != _generationSessionId || _currentChapter == null || !player.isPlaying || player.isPausedByUser) return;
        if (i < 0 || i >= list.length) continue;

        final voice = settings.currentVoice;
        final extension = UnifiedTtsService.getAudioExtension(voice);

        final expectedPath = await AudioExporter.generateSentenceAudioFilePath(
          storyTitle: _currentChapter!.storyTitle,
          chapterNumber: _currentChapter!.chapterNumber,
          type: sourceType == AudioSourceType.summary ? 'summary' : 'content',
          sentenceIndex: i,
          sentenceText: list[i].text,
          voiceId: settings.selectedVoiceId,
          extension: extension,
        );

        if (await File(expectedPath).exists() && await File(expectedPath).length() > 500) {
          if (sourceType == AudioSourceType.summary) {
            _summarySentences[i] = _summarySentences[i].copyWith(audioPath: expectedPath);
          } else {
            _contentSentences[i] = _contentSentences[i].copyWith(audioPath: expectedPath);
          }
          notifyListeners();
        } else if (!list[i].hasAudio && !list[i].isGenerating) {
          if (sourceType == AudioSourceType.summary) {
            _summarySentences[i] = _summarySentences[i].copyWith(isGenerating: true);
          } else {
            _contentSentences[i] = _contentSentences[i].copyWith(isGenerating: true);
          }
          notifyListeners();

          final path = await _synthesizeSingleSentence(
            sentence: list[i],
            chapter: _currentChapter!,
            settings: settings,
            audioType: sourceType == AudioSourceType.summary ? 'summary' : 'content',
          );

          if (sessionId != _generationSessionId || _currentChapter == null || !player.isPlaying || player.isPausedByUser) return;

          if (sourceType == AudioSourceType.summary) {
            _summarySentences[i] = _summarySentences[i].copyWith(
              audioPath: path,
              isGenerating: false,
              hasError: path == null,
            );
          } else {
            _contentSentences[i] = _contentSentences[i].copyWith(
              audioPath: path,
              isGenerating: false,
              hasError: path == null,
            );
          }
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    });
  }

  /// Phát một câu cụ thể (Ưu tiên tạo ngay nếu câu chưa có audio)
  Future<void> playSentence({
    required AudioSourceType sourceType,
    required int sentenceIndex,
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) async {
    if (_currentChapter == null) return;
    final list = sourceType == AudioSourceType.summary ? _summarySentences : _contentSentences;
    if (sentenceIndex < 0 || sentenceIndex >= list.length) return;

    if (!settings.autoNextChapter) {
      await settings.setAutoNextChapter(true);
    }

    _activeAudioSource = sourceType;
    _activeSentenceIndex = sentenceIndex;
    notifyListeners();

    // Lưu vị trí câu cuối đã phát
    _lastPlayedStoryTitle = _currentChapter!.storyTitle;
    _lastPlayedChapterNumber = _currentChapter!.chapterNumber;
    _lastPlayedSentenceIndex = sentenceIndex;
    _lastPlayedSource = sourceType;
    _lastPlayedStoryUrl = _currentChapter!.sourceUrl;

    _saveLastPlayedPosition(
      storyTitle: _currentChapter!.storyTitle,
      chapterNumber: _currentChapter!.chapterNumber,
      sentenceIndex: sentenceIndex,
      sourceType: sourceType,
      storyUrl: _currentChapter!.sourceUrl,
    );

    var item = list[sentenceIndex];

    // Nếu câu này chưa có audio, ưu tiên sinh ngay lập tức
    if (!item.hasAudio) {
      if (sourceType == AudioSourceType.summary) {
        _summarySentences[sentenceIndex] = item.copyWith(isGenerating: true);
      } else {
        _contentSentences[sentenceIndex] = item.copyWith(isGenerating: true);
      }
      notifyListeners();

      final audioPath = await _synthesizeSingleSentence(
        sentence: item,
        chapter: _currentChapter!,
        settings: settings,
        audioType: sourceType == AudioSourceType.summary ? 'summary' : 'content',
      );

      if (sourceType == AudioSourceType.summary) {
        _summarySentences[sentenceIndex] = _summarySentences[sentenceIndex].copyWith(
          audioPath: audioPath,
          isGenerating: false,
          hasError: audioPath == null,
        );
        item = _summarySentences[sentenceIndex];
      } else {
        _contentSentences[sentenceIndex] = _contentSentences[sentenceIndex].copyWith(
          audioPath: audioPath,
          isGenerating: false,
          hasError: audioPath == null,
        );
        item = _contentSentences[sentenceIndex];
      }
      notifyListeners();
    }

    // Phát câu nếu đã sẵn sàng
    if (item.hasAudio && _activeSentenceIndex == sentenceIndex) {
      final typeName = sourceType == AudioSourceType.summary ? 'Tóm tắt' : 'Nội dung';
      await player.playAudio(
        filePath: item.audioPath!,
        title: '${_currentChapter!.storyTitle} - C${_currentChapter!.chapterNumber} ($typeName câu ${sentenceIndex + 1})',
        storyTitle: _currentChapter!.storyTitle,
        chapterNumber: _currentChapter!.chapterNumber,
        audioSource: sourceType,
        sentenceIndex: sentenceIndex,
      );
    }

    // Tự động duy trì nạp trước lookahead buffer theo setting
    ensureLookaheadAudio(
      sourceType: sourceType,
      fromIndex: sentenceIndex,
      settings: settings,
      player: player,
    );
  }

  /// Xử lý khi kết thúc phát một câu audio -> Tự động phát câu tiếp theo liên tục không nghỉ
  Future<void> handleSentenceComplete({
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) async {
    if (_activeSentenceIndex == null) return;

    // Nếu người dùng đã chủ động tạm dừng (pause) -> KHÔNG tự chuyển câu
    if (player.isPausedByUser) {
      return;
    }

    final list = _activeAudioSource == AudioSourceType.summary ? _summarySentences : _contentSentences;
    int nextIndex = _activeSentenceIndex! + 1;

    // Bỏ qua các câu không có chữ nếu có
    while (nextIndex < list.length &&
        (!RegExp(r'[a-zA-Z0-9\u00C0-\u1EF9]').hasMatch(list[nextIndex].text) ||
         list[nextIndex].text.trim().isEmpty)) {
      nextIndex++;
    }

    if (nextIndex < list.length) {
      // Tự động phát câu tiếp theo liên tục không nghỉ
      await playSentence(
        sourceType: _activeAudioSource,
        sentenceIndex: nextIndex,
        settings: settings,
        player: player,
      );
    } else {
      // Đã phát hết toàn bộ các câu của phần hiện tại!
      _activeSentenceIndex = null;
      notifyListeners();

      // Lưu trạng thái đã hoàn thành chương (sentenceIndex = list.length -> biểu thị 154/154)
      if (_currentChapter != null) {
        await _saveLastPlayedPosition(
          storyTitle: _currentChapter!.storyTitle,
          chapterNumber: _currentChapter!.chapterNumber,
          sentenceIndex: list.length,
          sourceType: _activeAudioSource,
          storyUrl: _currentChapter!.sourceUrl,
        );
      }

      // Nếu bật tự chuyển chương -> chuyển chương tiếp theo và tiếp tục phát
      if (settings.autoNextChapter && !_isProcessing) {
        await goToNextChapter(settings: settings, player: player, isAutoNext: true);
      }
    }
  }

  /// Nút Play/Pause chính ở thanh Bottom Bar - Tự động phát theo tab đang chọn (Tóm tắt hoặc Nội dung)
  Future<void> toggleMainPlayPause({
    required SettingsProvider settings,
    required PlayerStateProvider player,
    AudioSourceType? currentSource,
  }) async {
    final targetSource = currentSource ?? _activeAudioSource;

    // 1. Nếu đang phát:
    if (player.isPlaying) {
      // Nếu đang phát đúng tab đang xem -> Tạm dừng (Hủy ngay lập tức mọi tiến trình sinh audio)
      if (_activeAudioSource == targetSource) {
        _generationSessionId++;
        _preloadTaskId++;
        await player.pause();
        notifyListeners();
        return;
      }
      // Nếu đang phát tab khác nhưng người dùng bấm Play ở tab này -> Chuyển sang phát tab này
      await player.stop(resetPause: false);
    }

    // 2. Tự động bật tính năng autoplay (tự chuyển & phát chương tiếp theo) khi bấm Play
    if (!settings.autoNextChapter) {
      await settings.setAutoNextChapter(true);
    }

    // 3. Nếu đang tạm dừng và cùng nguồn audio trước đó -> Tiếp tục phát và nạp trước lookahead
    if (player.currentAudioPath != null &&
        _activeSentenceIndex != null &&
        _activeAudioSource == targetSource &&
        player.isPausedByUser) {
      await player.play();
      ensureLookaheadAudio(
        sourceType: targetSource,
        fromIndex: _activeSentenceIndex!,
        settings: settings,
        player: player,
      );
      return;
    }

    // 4. Nếu chuyển sang tab Tóm tắt mà chưa có tóm tắt -> tự động tóm tắt rồi phát
    if (targetSource == AudioSourceType.summary && _summarySentences.isEmpty && _currentChapter != null) {
      await summarizeCurrentChapter(settings);
    }

    final list = targetSource == AudioSourceType.summary ? _summarySentences : _contentSentences;
    if (list.isEmpty) return;

    int targetIdx = targetSource == AudioSourceType.summary
        ? _currentSummarySentenceIndex
        : _currentContentSentenceIndex;
    targetIdx = getEffectiveSentenceIndex(targetIdx, list.length);

    await playSentence(
      sourceType: targetSource,
      sentenceIndex: targetIdx,
      settings: settings,
      player: player,
    );
  }

  /// Chuyển đổi tab hiển thị và nạp audio chính xác theo tab đó (Tóm tắt <-> Toàn văn)
  Future<void> switchAudioTab(
    AudioSourceType newSource, {
    required SettingsProvider settings,
    required PlayerStateProvider player,
  }) async {
    if (_activeAudioSource == newSource) return;

    final wasPlaying = player.isPlaying && !player.isPausedByUser;
    if (player.isPlaying) {
      await player.stop(resetPause: false);
    }

    _activeAudioSource = newSource;
    _generationSessionId++; // Hủy tiến trình sinh audio của tab trước

    // 1. Nếu chuyển sang Tóm tắt mà chưa có tóm tắt -> tóm tắt ngay
    if (newSource == AudioSourceType.summary && _summarySentences.isEmpty && _currentChapter != null) {
      await summarizeCurrentChapter(settings);
    }

    // 2. Lấy index câu đã lưu của tab mới (Nếu là câu cuối thì chuyển về index = 0 / câu 1)
    final list = newSource == AudioSourceType.summary ? _summarySentences : _contentSentences;
    int targetIdx = newSource == AudioSourceType.summary
        ? _currentSummarySentenceIndex
        : _currentContentSentenceIndex;
    targetIdx = getEffectiveSentenceIndex(targetIdx, list.length);

    if (newSource == AudioSourceType.summary) {
      _currentSummarySentenceIndex = targetIdx;
    } else {
      _currentContentSentenceIndex = targetIdx;
    }
    _activeSentenceIndex = targetIdx;
    notifyListeners();

    // 3. Nếu trước đó đang phát -> tiếp tục sinh audio và phát tiếp tab mới
    if (wasPlaying) {
      if (_currentChapter != null) {
        _startSequentialGeneration(
          chapter: _currentChapter!,
          settings: settings,
          player: player,
          startIndex: targetIdx,
        );
      }

      if (list.isNotEmpty) {
        await playSentence(
          sourceType: newSource,
          sentenceIndex: targetIdx,
          settings: settings,
          player: player,
        );
      }
    }

    // 4. Kích hoạt tự tải trước chương tiếp theo
    _preloadNextChapter(settings: settings, player: player);
  }

  /// Tự động tóm tắt chương hiện tại nếu chưa có bản tóm tắt nào
  Future<void> autoSummarizeIfEmpty(SettingsProvider settings) async {
    if (_currentChapter == null || _isProcessing) return;
    if (settings.workingApiKeys.isEmpty) return;
    if (_summarySentences.isEmpty && (_currentSummary == null || _currentSummary!.summaryText.trim().isEmpty)) {
      await summarizeCurrentChapter(settings);
    }
  }

  /// Dừng phát toàn bộ và reset trạng thái câu
  void stopPlayback({required PlayerStateProvider player}) {
    _activeSentenceIndex = null;
    player.stop();
    notifyListeners();
  }

  Future<void> summarizeCurrentChapter(SettingsProvider settings) async {
    if (_currentChapter == null) return;
    _isProcessing = true;
    _currentStatusMessage = 'Đang tóm tắt AI...';
    _summaryErrorMessage = null;
    notifyListeners();
    try {
      final summary = await summaryService.summarizeText(
        chapterId: _currentChapter!.id,
        text: _currentChapter!.content,
        apiKeys: settings.workingApiKeys,
        modelName: settings.selectedModel,
        domain: settings.currentProviderDomain,
        providerName: settings.aiProvider,
        providerId: settings.activeProviderId,
        customPrompt: settings.systemPrompt,
        onKeyFailed: (failedKey) => settings.markKeyFailed(failedKey),
      );
      _currentSummary = summary;
      _summaryErrorMessage = null;
      await db.insertSummary(summary);
      await _saveOrUpdateAudioItem(_currentChapter!, summary, settings);
      final rawSummary = buildSentenceListWithHeader(summary.summaryText.isNotEmpty ? summary.summaryText : _currentChapter!.content, _currentChapter!);
      _summarySentences = await _attachExistingAudioFiles(
        sentences: rawSummary,
        storyTitle: _currentChapter!.storyTitle,
        chapterNumber: _currentChapter!.chapterNumber,
        type: 'summary',
        voiceId: settings.selectedVoiceId,
      );
      _currentStatusMessage = 'Đã tóm tắt xong!';
    } catch (e) {
      _summaryErrorMessage = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      _currentStatusMessage = 'Lỗi tóm tắt: $_summaryErrorMessage';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> generateTtsForCurrent({
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required bool readFullContent,
  }) async {
    if (_currentChapter == null) return;
    if (readFullContent) {
      if (_contentSentences.isNotEmpty) {
        await playSentence(
          sourceType: AudioSourceType.content,
          sentenceIndex: 0,
          settings: settings,
          player: player,
        );
      }
    } else {
      if (_summarySentences.isNotEmpty) {
        await playSentence(
          sourceType: AudioSourceType.summary,
          sentenceIndex: 0,
          settings: settings,
          player: player,
        );
      }
    }
  }

  /// Tải ngầm trước nội dung, tóm tắt và audio của chương tiếp theo
  Future<void> _preloadNextChapter({
    required SettingsProvider settings,
    PlayerStateProvider? player,
  }) async {
    final currentNum = _currentChapter?.chapterNumber ?? int.tryParse(chapterController.text.trim()) ?? 1;
    final nextChapterNum = currentNum + 1;
    final currentStoryTitle = _currentChapter?.storyTitle ?? '';

    if (_isPreloadingNext && _preloadingChapterNumber == nextChapterNum) return;
    if (_preloadedNextChapter != null &&
        _preloadedNextChapter!.chapter.chapterNumber == nextChapterNum &&
        (currentStoryTitle.isEmpty ||
            _preloadedNextChapter!.chapter.storyTitle.toLowerCase().trim() == currentStoryTitle.toLowerCase().trim())) {
      // Nếu đã preload nhưng đang chọn Tab Tóm tắt mà bản preload chưa có tóm tắt -> tiếp tục chạy để tạo tóm tắt
      if (_activeAudioSource == AudioSourceType.summary &&
          (_preloadedNextChapter!.summary == null || _preloadedNextChapter!.summary!.summaryText.trim().isEmpty)) {
        // Tiếp tục xuống dưới để tạo tóm tắt
      } else {
        // Đảm bảo audio theo đúng tab đang chọn được nạp sẵn
        if (player != null && player.isPlaying && !player.isPausedByUser) {
          _preloadAudioForChapter(
            preloaded: _preloadedNextChapter!,
            settings: settings,
            taskId: _preloadTaskId,
            player: player,
          );
        }
        return;
      }
    }

    final taskId = ++_preloadTaskId;

    // 1. Kiểm tra xem chương tiếp theo ĐÃ CÓ TRONG MỤC ĐÃ LƯU CHƯA
    final savedItem = await _findSavedAudio(nextChapterNum, currentStoryTitle);
    if (savedItem != null) {
      if (taskId != _preloadTaskId) return;
      ChapterModel? chapter;
      if (savedItem.chapterId != null && savedItem.chapterId!.isNotEmpty) {
        chapter = await db.getChapter(savedItem.chapterId!);
      }
      chapter ??= await db.getChapterByStoryAndNumber(savedItem.storyTitle, nextChapterNum);
      final bodyText = savedItem.content ?? savedItem.summaryText ?? '';
      chapter ??= ChapterModel(
        id: savedItem.chapterId ?? 'saved_${savedItem.id}',
        storyTitle: savedItem.storyTitle,
        chapterTitle: savedItem.title.isNotEmpty ? savedItem.title : 'Chương $nextChapterNum',
        chapterNumber: nextChapterNum,
        sourceUrl: '',
        content: bodyText,
        wordCount: bodyText.split(RegExp(r'\s+')).length,
      );

      SummaryModel? summary;
      if (chapter.id.isNotEmpty) {
        summary = await db.getSummaryByChapterId(chapter.id);
      }
      if (summary == null && savedItem.summaryText != null && savedItem.summaryText!.trim().isNotEmpty) {
        summary = SummaryModel(
          id: 'sum_${chapter.id}',
          chapterId: chapter.id,
          summaryText: savedItem.summaryText!,
        );
      }

      // Nếu đang chọn Tab Tóm tắt mà chưa có tóm tắt -> tự động tóm tắt AI trước
      if (_activeAudioSource == AudioSourceType.summary &&
          (summary == null || summary.summaryText.trim().isEmpty) &&
          chapter.content.trim().isNotEmpty) {
        try {
          _preloadStatusMessage = 'Đang tự tóm tắt trước chương $nextChapterNum...';
          notifyListeners();
          summary = await summaryService.summarizeText(
            chapterId: chapter.id,
            text: chapter.content,
            apiKeys: settings.workingApiKeys,
            modelName: settings.selectedModel,
            domain: settings.currentProviderDomain,
            providerName: settings.aiProvider,
            providerId: settings.activeProviderId,
            customPrompt: settings.systemPrompt,
            onKeyFailed: (failedKey) => settings.markKeyFailed(failedKey),
          );
          await db.insertSummary(summary);
        } catch (sumErr) {
          print('Lỗi tóm tắt khi preload saved item: $sumErr');
        }
      }

      final rawSummary = (summary != null && summary.summaryText.isNotEmpty)
          ? buildSentenceListWithHeader(summary.summaryText, chapter)
          : <SentenceItem>[];
      final rawContent = buildSentenceListWithHeader(chapter.content, chapter);

      final summarySentences = await _attachExistingAudioFiles(
        sentences: rawSummary,
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        type: 'summary',
        voiceId: settings.selectedVoiceId,
      );
      final contentSentences = await _attachExistingAudioFiles(
        sentences: rawContent,
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        type: 'content',
        voiceId: settings.selectedVoiceId,
      );

      final preloaded = PreloadedChapter(
        chapter: chapter,
        summary: summary,
        summarySentences: summarySentences,
        contentSentences: contentSentences,
      );

      _preloadedNextChapter = preloaded;
      _isPreloadingNext = false;
      _preloadingChapterNumber = null;
      _inFlightPreloadFuture = null;
      _preloadStatusMessage = 'Chương $nextChapterNum đã có sẵn trong Đã Lưu';
      notifyListeners();

      // Sinh ngầm audio nếu chưa có theo đúng tab đang chọn và đang phát
      if (player != null && player.isPlaying && !player.isPausedByUser) {
        _preloadAudioForChapter(
          preloaded: preloaded,
          settings: settings,
          taskId: taskId,
          player: player,
        );
      }
      return;
    }

    // 2. Chưa có trong Đã Lưu -> Tìm Base URL
    ChapterModel? existingDbChapter;
    if (currentStoryTitle.isNotEmpty) {
      existingDbChapter = await db.getChapterByStoryAndNumber(currentStoryTitle.trim(), nextChapterNum);
    }

    String baseUrl = '';
    if (_currentChapter != null && _currentChapter!.sourceUrl.isNotEmpty) {
      baseUrl = _currentChapter!.sourceUrl;
    }

    if (baseUrl.isEmpty && currentStoryTitle.isNotEmpty) {
      final allChapters = await db.getAllChapters();
      for (final c in allChapters) {
        if (c.storyTitle.toLowerCase().trim() == currentStoryTitle.toLowerCase().trim() && c.sourceUrl.isNotEmpty) {
          baseUrl = c.sourceUrl;
          if (baseUrl.isNotEmpty) break;
        }
      }
    }

    if (baseUrl.isEmpty && urlController.text.trim().isNotEmpty) {
      baseUrl = urlController.text.trim();
    }

    if (existingDbChapter == null && baseUrl.isEmpty) {
      _preloadStatusMessage = '';
      notifyListeners();
      return;
    }

    _isPreloadingNext = true;
    _preloadingChapterNumber = nextChapterNum;
    _preloadStatusMessage = 'Đang tự tải trước chương $nextChapterNum...';
    notifyListeners();

    final taskFuture = _executePreloadTask(
      taskId: taskId,
      nextChapterNum: nextChapterNum,
      currentStoryTitle: currentStoryTitle,
      baseUrl: baseUrl,
      existingDbChapter: existingDbChapter,
      settings: settings,
      player: player,
    );
    _inFlightPreloadFuture = taskFuture;
    await taskFuture;
  }

  Future<PreloadedChapter?> _executePreloadTask({
    required int taskId,
    required int nextChapterNum,
    required String currentStoryTitle,
    required String baseUrl,
    required ChapterModel? existingDbChapter,
    required SettingsProvider settings,
    PlayerStateProvider? player,
  }) async {
    try {
      ChapterModel chapter;
      if (existingDbChapter != null && existingDbChapter.content.trim().isNotEmpty) {
        chapter = existingDbChapter;
      } else {
        chapter = await crawlerService.fetchChapter(
          baseUrl: baseUrl,
          chapterNumber: nextChapterNum,
        );

        if (settings.translateContent) {
          if (taskId != _preloadTaskId) return null;
          _preloadStatusMessage = 'Đang dịch chương $nextChapterNum...';
          notifyListeners();

          try {
            final translated = await summaryService.translateText(
              text: chapter.content,
              apiKeys: settings.workingApiKeys,
              modelName: settings.selectedModel,
              domain: settings.currentProviderDomain,
              providerName: settings.aiProvider,
              providerId: settings.activeProviderId,
              customPrompt: settings.translatePrompt,
              onKeyFailed: (failedKey) => settings.markKeyFailed(failedKey),
            );

            chapter = chapter.copyWith(
              content: translated,
              wordCount: translated.split(RegExp(r'\s+')).length,
            );
          } catch (transErr) {
            print('Lỗi dịch khi preload: $transErr');
          }
        }

        final normalizedStoryTitle = currentStoryTitle.trim().isNotEmpty ? currentStoryTitle.trim() : chapter.storyTitle;
        chapter = chapter.copyWith(storyTitle: normalizedStoryTitle);

        await db.insertChapter(chapter);
        _historyChapters.removeWhere((c) =>
            isSameStory(c.storyTitle, normalizedStoryTitle) &&
            c.chapterNumber == chapter.chapterNumber);
        _historyChapters.insert(0, chapter);
      }

      if (taskId != _preloadTaskId) return null;

      final normalizedStoryTitle = currentStoryTitle.trim().isNotEmpty ? currentStoryTitle.trim() : chapter.storyTitle;
      chapter = chapter.copyWith(storyTitle: normalizedStoryTitle);

      SummaryModel? summary;
      try {
        summary = await db.getSummaryByChapterId(chapter.id);
      } catch (_) {}

      // Nếu đang chọn Tab Tóm tắt mà chương tiếp theo chưa có tóm tắt -> tự động tóm tắt AI trước
      if (_activeAudioSource == AudioSourceType.summary &&
          (summary == null || summary.summaryText.trim().isEmpty) &&
          chapter.content.trim().isNotEmpty) {
        if (taskId != _preloadTaskId) return null;
        _preloadStatusMessage = 'Đang tự tóm tắt AI trước chương $nextChapterNum...';
        notifyListeners();

        try {
          summary = await summaryService.summarizeText(
            chapterId: chapter.id,
            text: chapter.content,
            apiKeys: settings.workingApiKeys,
            modelName: settings.selectedModel,
            domain: settings.currentProviderDomain,
            providerName: settings.aiProvider,
            providerId: settings.activeProviderId,
            customPrompt: settings.systemPrompt,
            onKeyFailed: (failedKey) => settings.markKeyFailed(failedKey),
          );
          await db.insertSummary(summary);
        } catch (sumErr) {
          print('Lỗi tóm tắt khi preload: $sumErr');
        }
      }

      if (taskId != _preloadTaskId) return null;

      final rawSummary = (summary != null && summary.summaryText.isNotEmpty)
          ? buildSentenceListWithHeader(summary.summaryText, chapter)
          : <SentenceItem>[];
      final rawContent = buildSentenceListWithHeader(chapter.content, chapter);

      final summarySentences = await _attachExistingAudioFiles(
        sentences: rawSummary,
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        type: 'summary',
        voiceId: settings.selectedVoiceId,
      );
      final contentSentences = await _attachExistingAudioFiles(
        sentences: rawContent,
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        type: 'content',
        voiceId: settings.selectedVoiceId,
      );

      // Lưu vào thư viện Đã Lưu
      final audioItem = SavedAudioItem(
        id: 'audio_${chapter.id}',
        title: chapter.chapterTitle,
        storyTitle: normalizedStoryTitle,
        chapterNumber: chapter.chapterNumber,
        audioPath: '',
        summaryText: summary?.summaryText ?? '',
        content: chapter.content,
        chapterId: chapter.id,
        voiceUsed: settings.currentVoice.name,
      );

      await db.insertAudio(audioItem);
      _savedAudios.removeWhere((a) =>
          isSameStory(a.storyTitle, normalizedStoryTitle) &&
          a.chapterNumber == chapter.chapterNumber);
      _savedAudios.insert(0, audioItem);

      final preloaded = PreloadedChapter(
        chapter: chapter,
        summary: summary,
        summarySentences: summarySentences,
        contentSentences: contentSentences,
      );

      _preloadedNextChapter = preloaded;
      _preloadStatusMessage = 'Đang tạo trước audio chương $nextChapterNum...';
      notifyListeners();

      // CHUYỂN NGẦM AUDIO CHƯƠNG TIẾP THEO THEO TAB ĐANG CHỌN (NẾU ĐANG PHÁT)
      if (player != null && player.isPlaying && !player.isPausedByUser) {
        await _preloadAudioForChapter(
          preloaded: preloaded,
          settings: settings,
          taskId: taskId,
          player: player,
        );
      }

      if (taskId == _preloadTaskId) {
        _preloadStatusMessage = 'Chương $nextChapterNum đã tải xong & có sẵn audio!';
        notifyListeners();
      }
      return preloaded;
    } catch (e) {
      print('Preload next chapter $nextChapterNum error: $e');
      if (taskId == _preloadTaskId) {
        _preloadStatusMessage = 'Đã là chương cuối hoặc không tìm thấy chương tiếp theo';
      }
      return null;
    } finally {
      if (taskId == _preloadTaskId) {
        _isPreloadingNext = false;
        _preloadingChapterNumber = null;
        _inFlightPreloadFuture = null;
        notifyListeners();
      }
    }
  }

  /// Sinh ngầm audio offline cho các câu của chương preload theo đúng tab đang chọn
  Future<void> _preloadAudioForChapter({
    required PreloadedChapter preloaded,
    required SettingsProvider settings,
    required int taskId,
    PlayerStateProvider? player,
  }) async {
    if (player != null && (!player.isPlaying || player.isPausedByUser)) return;
    final chapter = preloaded.chapter;
    final prefetchLimit = settings.audioPrefetchCount;
    final voice = settings.currentVoice;
    final extension = UnifiedTtsService.getAudioExtension(voice);

    // 1. Tự động sinh audio cho Tóm tắt nếu tab tóm tắt đang chọn và có câu tóm tắt
    if (_activeAudioSource == AudioSourceType.summary && preloaded.summarySentences.isNotEmpty) {
      final limit = preloaded.summarySentences.length < prefetchLimit ? preloaded.summarySentences.length : prefetchLimit;
      for (int i = 0; i < limit; i++) {
        if (taskId != _preloadTaskId || (player != null && (!player.isPlaying || player.isPausedByUser))) return;

        final expectedPath = await AudioExporter.generateSentenceAudioFilePath(
          storyTitle: chapter.storyTitle,
          chapterNumber: chapter.chapterNumber,
          type: 'summary',
          sentenceIndex: i,
          sentenceText: preloaded.summarySentences[i].text,
          voiceId: settings.selectedVoiceId,
          extension: extension,
        );

        if (await File(expectedPath).exists() && await File(expectedPath).length() > 500) {
          preloaded.summarySentences[i] = preloaded.summarySentences[i].copyWith(audioPath: expectedPath);
        } else {
          final path = await _synthesizeSingleSentence(
            sentence: preloaded.summarySentences[i],
            chapter: chapter,
            settings: settings,
            audioType: 'summary',
          );
          if (taskId != _preloadTaskId || (player != null && (!player.isPlaying || player.isPausedByUser))) return;
          if (path != null) {
            preloaded.summarySentences[i] = preloaded.summarySentences[i].copyWith(
              audioPath: path,
              isGenerating: false,
            );
          }
          await Future.delayed(const Duration(milliseconds: 60));
        }
      }
    }

    // 2. Tự động sinh audio cho Toàn văn nội dung nếu tab nội dung đang chọn
    if (_activeAudioSource == AudioSourceType.content && preloaded.contentSentences.isNotEmpty) {
      final limit = preloaded.contentSentences.length < prefetchLimit ? preloaded.contentSentences.length : prefetchLimit;
      for (int i = 0; i < limit; i++) {
        if (taskId != _preloadTaskId || (player != null && (!player.isPlaying || player.isPausedByUser))) return;

        final expectedPath = await AudioExporter.generateSentenceAudioFilePath(
          storyTitle: chapter.storyTitle,
          chapterNumber: chapter.chapterNumber,
          type: 'content',
          sentenceIndex: i,
          sentenceText: preloaded.contentSentences[i].text,
          voiceId: settings.selectedVoiceId,
          extension: extension,
        );

        if (await File(expectedPath).exists() && await File(expectedPath).length() > 500) {
          preloaded.contentSentences[i] = preloaded.contentSentences[i].copyWith(audioPath: expectedPath);
        } else {
          final path = await _synthesizeSingleSentence(
            sentence: preloaded.contentSentences[i],
            chapter: chapter,
            settings: settings,
            audioType: 'content',
          );
          if (taskId != _preloadTaskId || (player != null && (!player.isPlaying || player.isPausedByUser))) return;
          if (path != null) {
            preloaded.contentSentences[i] = preloaded.contentSentences[i].copyWith(
              audioPath: path,
              isGenerating: false,
            );
          }
          await Future.delayed(const Duration(milliseconds: 60));
        }
      }
    }
  }
  /// Nạp chương từ mục Đã Lưu với tùy chọn focus vào câu đã phát lần cuối
  Future<void> loadSavedChapter(
    SavedAudioItem item, {
    required SettingsProvider settings,
    required PlayerStateProvider player,
    bool focusLastPlayed = true,
    bool autoPlay = false,
  }) async {
    final shouldAutoPlay = autoPlay && !player.isPausedByUser;
    final sessionId = ++_generationSessionId;
    await player.stop(resetPause: false);

    _isProcessing = true;
    _currentStatusMessage = 'Đang tải lại chương đã lưu...';
    _overallProgress = 0.1;
    notifyListeners();

    try {
      ChapterModel? fetchedChapter;
      if (item.chapterId != null && item.chapterId!.isNotEmpty) {
        fetchedChapter = await db.getChapter(item.chapterId!);
      }
      fetchedChapter ??= await db.getChapterByStoryAndNumber(item.storyTitle, item.chapterNumber);

      String sourceUrl = fetchedChapter?.sourceUrl ?? '';
      if (sourceUrl.isEmpty && item.storyTitle.trim().isNotEmpty) {
        final allChapters = await db.getAllChapters();
        for (final c in allChapters) {
          if (c.storyTitle.toLowerCase().trim() == item.storyTitle.toLowerCase().trim() && c.sourceUrl.isNotEmpty) {
            sourceUrl = c.sourceUrl;
            break;
          }
        }
      }

      final bodyText = (fetchedChapter?.content.trim().isNotEmpty == true)
          ? fetchedChapter!.content
          : (item.content?.trim().isNotEmpty == true)
              ? item.content!
              : (item.summaryText?.trim().isNotEmpty == true)
                  ? item.summaryText!
                  : '';

      ChapterModel chapter = (fetchedChapter ??
              ChapterModel(
                id: item.chapterId ?? 'saved_${item.id}',
                storyTitle: item.storyTitle,
                chapterTitle: item.title.isNotEmpty ? item.title : 'Chương ${item.chapterNumber}',
                chapterNumber: item.chapterNumber,
                sourceUrl: sourceUrl,
                content: bodyText,
                wordCount: bodyText.split(RegExp(r'\s+')).length,
              ))
          .copyWith(
        sourceUrl: sourceUrl.isNotEmpty ? sourceUrl : (fetchedChapter?.sourceUrl ?? ''),
      );

      // Nếu nội dung vẫn rỗng nhưng có link nguồn -> tải lại từ crawler
      if (chapter.content.trim().isEmpty && chapter.sourceUrl.isNotEmpty) {
        try {
          final fetched = await crawlerService.fetchChapter(
            baseUrl: chapter.sourceUrl,
            chapterNumber: chapter.chapterNumber,
          );
          chapter = chapter.copyWith(
            content: fetched.content,
            wordCount: fetched.wordCount,
            chapterTitle: fetched.chapterTitle.isNotEmpty ? fetched.chapterTitle : chapter.chapterTitle,
          );
          await db.insertChapter(chapter);
        } catch (_) {}
      }

      _currentChapter = chapter;
      chapterController.text = item.chapterNumber.toString();

      if (chapter.sourceUrl.isNotEmpty) {
        urlController.text = chapter.sourceUrl;
      }

      if (_preloadedNextChapter != null &&
          (_preloadedNextChapter!.chapter.chapterNumber != item.chapterNumber + 1 ||
              _preloadedNextChapter!.chapter.storyTitle.toLowerCase().trim() != item.storyTitle.toLowerCase().trim())) {
        _preloadedNextChapter = null;
      }

      // Nạp câu nội dung toàn văn và gắn audio có sẵn
      final rawContentSentences = buildSentenceListWithHeader(chapter.content, chapter);
      _contentSentences = await _attachExistingAudioFiles(
        sentences: rawContentSentences,
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        type: 'content',
        voiceId: settings.selectedVoiceId,
      );

      // Nạp tóm tắt AI từ Database / Item
      SummaryModel? summary;
      if (chapter.id.isNotEmpty) {
        summary = await db.getSummaryByChapterId(chapter.id);
      }
      if (summary == null && item.summaryText != null && item.summaryText!.trim().isNotEmpty) {
        summary = SummaryModel(
          id: 'summary_${chapter.id}',
          chapterId: chapter.id,
          summaryText: item.summaryText!,
        );
      }

      if (sessionId != _generationSessionId) return;

      _currentSummary = summary;

      // Tạo danh sách câu tóm tắt và gắn audio có sẵn
      final rawSummarySentences = (summary != null && summary.summaryText.trim().isNotEmpty)
          ? buildSentenceListWithHeader(summary.summaryText, chapter)
          : <SentenceItem>[];

      _summarySentences = await _attachExistingAudioFiles(
        sentences: rawSummarySentences,
        storyTitle: chapter.storyTitle,
        chapterNumber: chapter.chapterNumber,
        type: 'summary',
        voiceId: settings.selectedVoiceId,
      );

      // Xác định vị trí câu cuối đã phát cho cả Tóm tắt và Nội dung
      int savedSummaryIdx = item.lastPlayedSummaryIndex;
      int savedContentIdx = item.lastPlayedContentIndex;
      String savedSourceStr = item.lastPlayedSource;

      try {
        final prefs = await SharedPreferences.getInstance();
        final cleanStory = chapter.storyTitle.trim().toLowerCase();
        final sourceKey = 'last_source_${cleanStory}_${chapter.chapterNumber}';
        final summaryKey = 'last_summary_idx_${cleanStory}_${chapter.chapterNumber}';
        final contentKey = 'last_content_idx_${cleanStory}_${chapter.chapterNumber}';

        if (prefs.containsKey(summaryKey)) {
          savedSummaryIdx = prefs.getInt(summaryKey) ?? savedSummaryIdx;
        }
        if (prefs.containsKey(contentKey)) {
          savedContentIdx = prefs.getInt(contentKey) ?? savedContentIdx;
        }
        if (prefs.containsKey(sourceKey)) {
          savedSourceStr = prefs.getString(sourceKey) ?? savedSourceStr;
        }
      } catch (_) {}

      _currentSummarySentenceIndex = getEffectiveSentenceIndex(savedSummaryIdx, _summarySentences.length);
      _currentContentSentenceIndex = getEffectiveSentenceIndex(savedContentIdx, _contentSentences.length);

      AudioSourceType targetSource = AudioSourceType.summary;
      if (savedSourceStr == 'content' && _contentSentences.isNotEmpty) {
        targetSource = AudioSourceType.content;
      } else {
        targetSource = _summarySentences.isNotEmpty
            ? AudioSourceType.summary
            : AudioSourceType.content;
      }

      final targetSentenceIndex = targetSource == AudioSourceType.summary
          ? _currentSummarySentenceIndex
          : _currentContentSentenceIndex;

      _activeAudioSource = targetSource;
      _activeSentenceIndex = targetSentenceIndex;

      _headerTitle = _formatChapterHeader(chapter);
      _currentStatusMessage = '';
      _overallProgress = 1.0;
      _isProcessing = false;
      notifyListeners();

      // Tự động tải ngầm trước chương kế tiếp
      _preloadNextChapter(settings: settings, player: player);

      // Tự động phát nếu autoplay được bật và không pause
      if (shouldAutoPlay) {
        _startSequentialGeneration(
          chapter: chapter,
          settings: settings,
          player: player,
          startIndex: targetSentenceIndex,
        );

        final currentPlayList = _activeAudioSource == AudioSourceType.summary ? _summarySentences : _contentSentences;
        if (currentPlayList.isNotEmpty) {
          playSentence(
            sourceType: _activeAudioSource,
            sentenceIndex: targetSentenceIndex,
            settings: settings,
            player: player,
          );
        }
      }

    } catch (e) {
      _isProcessing = false;
      _currentStatusMessage = 'Lỗi tải chương đã lưu: $e';
      notifyListeners();
    }
  }

  Future<void> deleteSavedChapter(String id) async {
    final itemIndex = _savedAudios.indexWhere((a) => a.id == id);
    if (itemIndex != -1) {
      final item = _savedAudios[itemIndex];
      if (item.audioPath.isNotEmpty) {
        final file = File(item.audioPath);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      if (item.chapterId != null && item.chapterId!.isNotEmpty) {
        await db.deleteChapter(item.chapterId!);
        await db.deleteSummary(item.chapterId!);
      }
      await db.deleteAudio(id);
      _savedAudios.removeAt(itemIndex);
      notifyListeners();
    }
  }

  Future<void> clearAllSaved() async {
    for (var item in _savedAudios) {
      if (item.audioPath.isNotEmpty) {
        final file = File(item.audioPath);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
    await db.clearAllData();
    _savedAudios.clear();
    _historyChapters.clear();
    notifyListeners();
  }

  Future<void> deleteSavedStory(String storyTitle) async {
    final toDelete = _savedAudios
        .where((a) => a.storyTitle.trim().toLowerCase() == storyTitle.trim().toLowerCase())
        .toList();
    for (final item in toDelete) {
      if (item.audioPath.isNotEmpty) {
        final file = File(item.audioPath);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      if (item.chapterId != null && item.chapterId!.isNotEmpty) {
        await db.deleteChapter(item.chapterId!);
        await db.deleteSummary(item.chapterId!);
      }
      await db.deleteAudio(item.id);
    }
    _savedAudios.removeWhere(
        (a) => a.storyTitle.trim().toLowerCase() == storyTitle.trim().toLowerCase());
    _historyChapters.removeWhere(
        (c) => c.storyTitle.trim().toLowerCase() == storyTitle.trim().toLowerCase());
    notifyListeners();
  }

  Future<void> deleteSavedAudio(String id) async {
    await deleteSavedChapter(id);
  }
}
