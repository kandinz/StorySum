import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/voice_model.dart';
import '../models/ai_provider_model.dart';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;

  String _systemPrompt = AppConstants.defaultSummaryPrompt;
  String _translatePrompt = AppConstants.defaultTranslatePrompt;
  String _selectedVoiceId = AppConstants.defaultVoiceId;
  double _speed = 1.0;
  double _pitch = 1.0;
  double _volume = 1.0;
  double _fontSize = 15.0; // Kích cỡ chữ mặc định
  String _fontFamily = AppConstants.defaultFontFamily; // Font chữ đọc truyện
  AppThemeMode _appThemeMode = AppThemeMode.dark; // Chế độ giao diện (Dark/Light/System/Sepia/Warm)
  bool _autoNextChapter = false; // Mặc định false, tự chuyển chương khi phát hết
  bool _translateContent = false; // Mặc định false, không dịch nội dung
  int _audioPrefetchCount = AppConstants.defaultAudioPrefetchCount; // Mặc định 5 câu tải sẵn

  // AI Configuration (Multi-Provider: Gemini, ChatGPT, Claude, DeepSeek, MiMo, OpenRouter, Groq, Custom)
  List<AiProviderModel> _providers = AiProviderModel.defaultBuiltinProviders;
  String _activeProviderId = 'google-gemini';
  final Set<String> _failedKeysInSession = {}; // Lưu các key lỗi trong phiên hiện tại (tự reset khi mở lại app)

  static const List<Map<String, dynamic>> themeOptions = [
    {'mode': AppThemeMode.dark, 'name': 'dark', 'label': 'Dark (Tối)'},
    {'mode': AppThemeMode.light, 'name': 'light', 'label': 'Light (Sáng)'},
    {'mode': AppThemeMode.system, 'name': 'system', 'label': 'System (Hệ thống)'},
    {'mode': AppThemeMode.sepia, 'name': 'sepia', 'label': 'Sepia (Giấy vàng)'},
    {'mode': AppThemeMode.warm, 'name': 'warm', 'label': 'Warm (Ấm áp)'},
  ];

  static const List<Map<String, String>> storyFonts = [
    {'name': 'Inter', 'label': 'Inter (Google Mặc định)'},
    {'name': 'Be Vietnam Pro', 'label': 'Be Vietnam Pro (Chuẩn TV)'},
    {'name': 'Lora', 'label': 'Lora (Tiểu thuyết Serif)'},
    {'name': 'Merriweather', 'label': 'Merriweather (Cổ điển)'},
    {'name': 'Literata', 'label': 'Literata (Google Books)'},
    {'name': 'Roboto', 'label': 'Roboto (Phổ biến)'},
  ];

  List<VoiceModel> _availableVoices = VoiceModel.defaultVoices;

  String get systemPrompt => _systemPrompt;
  String get translatePrompt => _translatePrompt;
  String get selectedVoiceId => _selectedVoiceId;
  double get speed => _speed;
  double get pitch => _pitch;
  double get volume => _volume;
  double get fontSize => _fontSize;
  String get fontFamily => _fontFamily;
  AppThemeMode get appThemeMode => _appThemeMode;
  bool get autoNextChapter => _autoNextChapter;
  bool get translateContent => _translateContent;
  int get audioPrefetchCount => _audioPrefetchCount;
  List<VoiceModel> get availableVoices => _availableVoices;

  // AI & Providers Getters
  List<AiProviderModel> get providers => _providers;
  String get activeProviderId => _activeProviderId;

  AiProviderModel get activeProvider {
    return _providers.firstWhere(
      (p) => p.id == _activeProviderId,
      orElse: () => _providers.isNotEmpty ? _providers.first : AiProviderModel.defaultGeminiProvider,
    );
  }

  List<String> get availableAiProviders => _providers.map((p) => p.name).toList();
  String get aiProvider => activeProvider.name;
  String get currentProviderDomain => activeProvider.domain;
  String get selectedModel => activeProvider.selectedModel;
  List<String> get currentProviderModels => activeProvider.models;
  List<String> get currentProviderApiKeys => activeProvider.apiKeys;
  List<String> get allAvailableModels => activeProvider.models;

  Set<String> get failedKeysInSession => _failedKeysInSession;

  /// Danh sách các key đang hoạt động bình thường của Provider đang chọn (chưa bị đánh dấu lỗi phiên này)
  List<String> get workingApiKeys {
    return activeProvider.apiKeys.where((k) => !_failedKeysInSession.contains(k)).toList();
  }

  VoiceModel get currentVoice {
    return _availableVoices.firstWhere(
      (v) => v.id == _selectedVoiceId,
      orElse: () => _availableVoices.firstWhere(
        (v) => v.id == 'onnx-ngoc-huyen',
        orElse: () => _availableVoices.first,
      ),
    );
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _systemPrompt = _prefs.getString(AppConstants.keySystemPrompt) ?? AppConstants.defaultSummaryPrompt;
    _translatePrompt = _prefs.getString(AppConstants.keyTranslatePrompt) ?? AppConstants.defaultTranslatePrompt;
    _selectedVoiceId = _prefs.getString(AppConstants.keySelectedVoice) ?? AppConstants.defaultVoiceId;
    _speed = _prefs.getDouble(AppConstants.keyRate) ?? 1.0;
    _pitch = _prefs.getDouble(AppConstants.keyPitch) ?? 1.0;
    _volume = _prefs.getDouble(AppConstants.keyVolume) ?? 1.0;
    _fontSize = _prefs.getDouble(AppConstants.keyFontSize) ?? 15.0;
    _fontFamily = _prefs.getString(AppConstants.keyFontFamily) ?? AppConstants.defaultFontFamily;
    final themeStr = _prefs.getString(AppConstants.keyAppThemeMode) ?? AppConstants.defaultAppThemeMode;
    _appThemeMode = AppThemeMode.values.firstWhere(
      (e) => e.name == themeStr,
      orElse: () => AppThemeMode.dark,
    );

    _autoNextChapter = _prefs.getBool(AppConstants.keyAutoNextChapter) ?? false;
    _translateContent = _prefs.getBool(AppConstants.keyTranslateContent) ?? false;
    _audioPrefetchCount = _prefs.getInt(AppConstants.keyAudioPrefetchCount) ?? AppConstants.defaultAudioPrefetchCount;

    // 1. Tải danh sách AI Providers từ SharedPreferences
    final providersJson = _prefs.getStringList(AppConstants.keyAiProvidersJson) ?? [];
    final List<AiProviderModel> loadedProviders = [];
    for (final str in providersJson) {
      try {
        final map = jsonDecode(str);
        if (map is Map<String, dynamic>) {
          loadedProviders.add(AiProviderModel.fromMap(map));
        }
      } catch (_) {}
    }

    // Danh sách các built-in mặc định
    final builtinList = AiProviderModel.defaultBuiltinProviders;
    final List<AiProviderModel> mergedProviders = [];

    for (final builtin in builtinList) {
      final savedIndex = loadedProviders.indexWhere((p) => p.id == builtin.id);
      if (savedIndex != -1) {
        final saved = loadedProviders[savedIndex];
        // Hợp nhất models: giữ models mặc định của builtin và bổ sung các model tùy biến user đã thêm
        final combinedModels = <String>[...builtin.models];
        for (final m in saved.models) {
          if (!combinedModels.contains(m)) {
            combinedModels.add(m);
          }
        }
        mergedProviders.add(builtin.copyWith(
          domain: saved.domain.isNotEmpty ? saved.domain : builtin.domain,
          apiKeys: saved.apiKeys,
          models: combinedModels,
          selectedModel: combinedModels.contains(saved.selectedModel)
              ? saved.selectedModel
              : builtin.selectedModel,
        ));
      } else {
        mergedProviders.add(builtin);
      }
    }

    // Thêm các custom provider do user tự tạo (không nằm trong danh sách built-in)
    for (final saved in loadedProviders) {
      if (saved.isCustom || !builtinList.any((b) => b.id == saved.id)) {
        mergedProviders.add(saved);
      }
    }

    // Migration nếu trước đây người dùng lưu gemini_api_keys
    final oldGeminiKeys = _prefs.getStringList(AppConstants.keyGeminiApiKeys) ?? [];
    final geminiIndex = mergedProviders.indexWhere((p) => p.id == 'google-gemini');
    if (geminiIndex != -1 && oldGeminiKeys.isNotEmpty) {
      var gemini = mergedProviders[geminiIndex];
      final combinedGeminiKeys = <String>[...gemini.apiKeys];
      for (final k in oldGeminiKeys) {
        if (!combinedGeminiKeys.contains(k)) combinedGeminiKeys.add(k);
      }
      mergedProviders[geminiIndex] = gemini.copyWith(apiKeys: combinedGeminiKeys);
    }

    _providers = mergedProviders;

    _activeProviderId = _prefs.getString(AppConstants.keyActiveAiProviderId) ?? 'google-gemini';
    if (!_providers.any((p) => p.id == _activeProviderId)) {
      _activeProviderId = 'google-gemini';
    }

    // Reset lại toàn bộ đánh dấu key lỗi khi khởi động lại app
    _failedKeysInSession.clear();

    // Tải các giọng đọc tự nạp đã lưu từ SharedPreferences
    final customVoicesJson = _prefs.getStringList('custom_onnx_voices') ?? [];
    final List<VoiceModel> loadedCustomVoices = [];
    for (final str in customVoicesJson) {
      try {
        final map = jsonDecode(str);
        if (map is Map<String, dynamic>) {
          final v = VoiceModel.fromMap(map);
          if (v.localModelPath != null && File(v.localModelPath!).existsSync()) {
            loadedCustomVoices.add(v);
          }
        }
      } catch (_) {}
    }

    _availableVoices = [
      ...VoiceModel.defaultVoices,
      ...loadedCustomVoices,
    ];

    notifyListeners();
  }

  // ===========================================================================
  // AI & KEYS MANAGEMENT METHODS
  // ===========================================================================
  Future<void> _saveProvidersToPrefs() async {
    final list = _providers.map((p) => jsonEncode(p.toMap())).toList();
    await _prefs.setStringList(AppConstants.keyAiProvidersJson, list);
    await _prefs.setString(AppConstants.keyActiveAiProviderId, _activeProviderId);
    // Đồng bộ ngược lại các key cũ để tương thích hoàn toàn
    final gemini = _providers.firstWhere((p) => p.id == 'google-gemini', orElse: () => AiProviderModel.defaultGeminiProvider);
    await _prefs.setStringList(AppConstants.keyGeminiApiKeys, gemini.apiKeys);
  }

  Future<void> setActiveProviderById(String providerId) async {
    if (_providers.any((p) => p.id == providerId)) {
      _activeProviderId = providerId;
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> setAiProvider(String providerNameOrId) async {
    final matched = _providers.firstWhere(
      (p) => p.id == providerNameOrId || p.name == providerNameOrId,
      orElse: () => activeProvider,
    );
    _activeProviderId = matched.id;
    await _saveProvidersToPrefs();
    notifyListeners();
  }

  Future<void> addCustomProvider({
    required String name,
    required String domain,
    String? defaultModel,
  }) async {
    final cleanName = name.trim();
    var cleanDomain = domain.trim();
    if (cleanDomain.isEmpty) cleanDomain = 'https://api.openai.com/v1';

    final model = (defaultModel != null && defaultModel.trim().isNotEmpty)
        ? defaultModel.trim()
        : 'default';

    final newProvider = AiProviderModel(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: cleanName.isNotEmpty ? cleanName : 'Custom AI',
      domain: cleanDomain,
      models: [model],
      selectedModel: model,
      apiKeys: [],
      isCustom: true,
    );

    _providers.add(newProvider);
    _activeProviderId = newProvider.id;
    await _saveProvidersToPrefs();
    notifyListeners();
  }

  Future<void> updateCustomProvider({
    required String providerId,
    required String name,
    required String domain,
  }) async {
    final index = _providers.indexWhere((p) => p.id == providerId);
    if (index != -1) {
      final old = _providers[index];
      _providers[index] = old.copyWith(
        name: name.trim().isNotEmpty ? name.trim() : old.name,
        domain: domain.trim().isNotEmpty ? domain.trim() : old.domain,
      );
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> updateProviderDomain({
    required String providerId,
    required String domain,
  }) async {
    final index = _providers.indexWhere((p) => p.id == providerId);
    if (index != -1) {
      final old = _providers[index];
      _providers[index] = old.copyWith(
        domain: domain.trim().isNotEmpty ? domain.trim() : old.domain,
      );
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> resetProviderModels(String providerId) async {
    final index = _providers.indexWhere((p) => p.id == providerId);
    if (index != -1) {
      final current = _providers[index];
      final builtinMatch = AiProviderModel.defaultBuiltinProviders.firstWhere(
        (b) => b.id == providerId,
        orElse: () => current,
      );
      _providers[index] = current.copyWith(
        models: List.from(builtinMatch.models),
        selectedModel: builtinMatch.selectedModel,
      );
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> deleteCustomProvider(String providerId) async {
    final index = _providers.indexWhere((p) => p.id == providerId);
    if (index != -1 && _providers[index].isCustom) {
      _providers.removeAt(index);
      if (_activeProviderId == providerId) {
        _activeProviderId = 'google-gemini';
      }
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> setSelectedModel(String model) async {
    final clean = model.trim();
    if (clean.isEmpty) return;

    final index = _providers.indexWhere((p) => p.id == _activeProviderId);
    if (index != -1) {
      final current = _providers[index];
      final updatedModels = List<String>.from(current.models);
      if (!updatedModels.contains(clean)) {
        updatedModels.add(clean);
      }
      _providers[index] = current.copyWith(
        selectedModel: clean,
        models: updatedModels,
      );
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> addCustomModel(String model) async {
    await addModelToActiveProvider(model);
  }

  Future<void> addModelToActiveProvider(String model) async {
    final clean = model.trim();
    if (clean.isEmpty) return;

    final index = _providers.indexWhere((p) => p.id == _activeProviderId);
    if (index != -1) {
      final current = _providers[index];
      final updatedModels = List<String>.from(current.models);
      if (!updatedModels.contains(clean)) {
        updatedModels.add(clean);
      }
      _providers[index] = current.copyWith(
        selectedModel: clean,
        models: updatedModels,
      );
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> removeCustomModel(String model) async {
    await removeModelFromActiveProvider(model);
  }

  Future<void> removeModelFromActiveProvider(String model) async {
    final index = _providers.indexWhere((p) => p.id == _activeProviderId);
    if (index != -1) {
      final current = _providers[index];
      final updatedModels = List<String>.from(current.models)..remove(model);
      String newSelected = current.selectedModel;
      if (newSelected == model) {
        newSelected = updatedModels.isNotEmpty ? updatedModels.first : 'default';
      }
      _providers[index] = current.copyWith(
        selectedModel: newSelected,
        models: updatedModels,
      );
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> addGeminiApiKey(String key) async {
    await addApiKeyToActiveProvider(key);
  }

  Future<void> addApiKeyToActiveProvider(String key) async {
    final clean = key.trim();
    if (clean.isEmpty) return;

    final index = _providers.indexWhere((p) => p.id == _activeProviderId);
    if (index != -1) {
      final current = _providers[index];
      final updatedKeys = List<String>.from(current.apiKeys);
      if (!updatedKeys.contains(clean)) {
        updatedKeys.add(clean);
      }
      _providers[index] = current.copyWith(apiKeys: updatedKeys);
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  Future<void> removeGeminiApiKey(String key) async {
    await removeApiKeyFromActiveProvider(key);
  }

  Future<void> removeApiKeyFromActiveProvider(String key) async {
    final index = _providers.indexWhere((p) => p.id == _activeProviderId);
    if (index != -1) {
      final current = _providers[index];
      final updatedKeys = List<String>.from(current.apiKeys)..remove(key);
      _failedKeysInSession.remove(key);
      _providers[index] = current.copyWith(apiKeys: updatedKeys);
      await _saveProvidersToPrefs();
      notifyListeners();
    }
  }

  void markKeyFailed(String key) {
    if (activeProvider.apiKeys.contains(key) && !_failedKeysInSession.contains(key)) {
      _failedKeysInSession.add(key);
      notifyListeners();
    }
  }

  void resetFailedKeys() {
    _failedKeysInSession.clear();
    notifyListeners();
  }

  // ===========================================================================
  // SETTERS
  // ===========================================================================
  Future<void> setSystemPrompt(String prompt) async {
    _systemPrompt = prompt.trim();
    await _prefs.setString(AppConstants.keySystemPrompt, _systemPrompt);
    notifyListeners();
  }

  Future<void> setTranslatePrompt(String prompt) async {
    _translatePrompt = prompt.trim();
    await _prefs.setString(AppConstants.keyTranslatePrompt, _translatePrompt);
    notifyListeners();
  }

  Future<void> setSelectedVoice(String voiceId) async {
    _selectedVoiceId = voiceId;
    await _prefs.setString(AppConstants.keySelectedVoice, _selectedVoiceId);
    notifyListeners();
  }

  Future<void> setSpeed(double val) async {
    _speed = val;
    await _prefs.setDouble(AppConstants.keyRate, _speed);
    notifyListeners();
  }

  Future<void> setPitch(double val) async {
    _pitch = val;
    await _prefs.setDouble(AppConstants.keyPitch, _pitch);
    notifyListeners();
  }

  Future<void> setVolume(double val) async {
    _volume = val;
    await _prefs.setDouble(AppConstants.keyVolume, _volume);
    notifyListeners();
  }

  Future<void> setFontSize(double val) async {
    _fontSize = val;
    await _prefs.setDouble(AppConstants.keyFontSize, _fontSize);
    notifyListeners();
  }

  Future<void> setAutoNextChapter(bool val) async {
    _autoNextChapter = val;
    await _prefs.setBool(AppConstants.keyAutoNextChapter, _autoNextChapter);
    notifyListeners();
  }

  Future<void> setTranslateContent(bool val) async {
    _translateContent = val;
    await _prefs.setBool(AppConstants.keyTranslateContent, _translateContent);
    notifyListeners();
  }

  Future<void> setAudioPrefetchCount(int count) async {
    final cleanCount = count.clamp(1, 100);
    _audioPrefetchCount = cleanCount;
    await _prefs.setInt(AppConstants.keyAudioPrefetchCount, cleanCount);
    notifyListeners();
  }

  Future<void> setFontFamily(String font) async {
    _fontFamily = font;
    await _prefs.setString(AppConstants.keyFontFamily, _fontFamily);
    notifyListeners();
  }

  Future<void> setAppThemeMode(AppThemeMode mode) async {
    _appThemeMode = mode;
    await _prefs.setString(AppConstants.keyAppThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> addCustomVoice(VoiceModel voice) async {
    _availableVoices.removeWhere((v) => v.id == voice.id);
    _availableVoices = [..._availableVoices, voice];
    await _saveCustomVoices();
    notifyListeners();
  }

  Future<void> deleteCustomVoice(String voiceId) async {
    final index = _availableVoices.indexWhere((v) => v.id == voiceId);
    if (index != -1) {
      final voice = _availableVoices[index];
      if (voice.localModelPath != null) {
        final f = File(voice.localModelPath!);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      if (voice.localConfigPath != null && !voice.localConfigPath!.startsWith('assets/')) {
        final f = File(voice.localConfigPath!);
        if (await f.exists() && !f.path.endsWith('tokens.txt')) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      _availableVoices.removeAt(index);
      if (_selectedVoiceId == voiceId) {
        _selectedVoiceId = AppConstants.defaultVoiceId;
        await _prefs.setString(AppConstants.keySelectedVoice, _selectedVoiceId);
      }
      await _saveCustomVoices();
      notifyListeners();
    }
  }

  Future<void> _saveCustomVoices() async {
    final customVoices = _availableVoices.where(
      (v) => !VoiceModel.defaultVoices.any((dv) => dv.id == v.id),
    );
    final list = customVoices.map((v) => jsonEncode(v.toMap())).toList();
    await _prefs.setStringList('custom_onnx_voices', list);
  }
}
