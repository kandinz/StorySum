import 'dart:convert';

class AiProviderModel {
  final String id;
  final String name;
  final String domain;
  final List<String> apiKeys;
  final List<String> models;
  final String selectedModel;
  final bool isCustom;

  const AiProviderModel({
    required this.id,
    required this.name,
    required this.domain,
    this.apiKeys = const [],
    this.models = const [],
    required this.selectedModel,
    this.isCustom = false,
  });

  /// Provider mặc định Google Gemini
  static AiProviderModel get defaultGeminiProvider => const AiProviderModel(
        id: 'google-gemini',
        name: 'Google Gemini',
        domain: 'https://generativelanguage.googleapis.com',
        apiKeys: [],
        models: [
          'gemini-2.5-flash-lite',
          'gemini-2.5-flash',
          'gemini-2.5-pro',
          'gemini-2.0-flash',
          'gemini-1.5-flash',
        ],
        selectedModel: 'gemini-2.5-flash-lite',
        isCustom: false,
      );

  /// Danh sách toàn bộ các Built-in Provider được hỗ trợ sẵn
  static List<AiProviderModel> get defaultBuiltinProviders => const [
        AiProviderModel(
          id: 'google-gemini',
          name: 'Google Gemini',
          domain: 'https://generativelanguage.googleapis.com',
          apiKeys: [],
          models: [
            'gemini-2.5-flash-lite',
            'gemini-2.5-flash',
            'gemini-2.5-pro',
            'gemini-2.0-flash',
            'gemini-1.5-flash',
          ],
          selectedModel: 'gemini-2.5-flash-lite',
          isCustom: false,
        ),
        AiProviderModel(
          id: 'openai',
          name: 'ChatGPT (OpenAI)',
          domain: 'https://api.openai.com/v1',
          apiKeys: [],
          models: [
            'gpt-4o-mini',
            'gpt-4o',
            'gpt-4.1-mini',
            'gpt-4.1',
            'o3-mini',
            'gpt-3.5-turbo',
          ],
          selectedModel: 'gpt-4o-mini',
          isCustom: false,
        ),
        AiProviderModel(
          id: 'anthropic',
          name: 'Claude (Anthropic)',
          domain: 'https://api.anthropic.com/v1',
          apiKeys: [],
          models: [
            'claude-3-5-haiku-20241022',
            'claude-3-7-sonnet-20250219',
            'claude-3-5-sonnet-20241022',
            'claude-3-haiku-20240307',
          ],
          selectedModel: 'claude-3-5-haiku-20241022',
          isCustom: false,
        ),
        AiProviderModel(
          id: 'deepseek',
          name: 'DeepSeek',
          domain: 'https://api.deepseek.com/v1',
          apiKeys: [],
          models: [
            'deepseek-chat',
            'deepseek-reasoner',
          ],
          selectedModel: 'deepseek-chat',
          isCustom: false,
        ),
        AiProviderModel(
          id: 'mimo',
          name: 'MiMo AI',
          domain: 'https://api.mimo.ai/v1',
          apiKeys: [],
          models: [
            'mimo-v2',
            'mimo-chat',
            'mimo-lite',
          ],
          selectedModel: 'mimo-v2',
          isCustom: false,
        ),
        AiProviderModel(
          id: 'openrouter',
          name: 'OpenRouter',
          domain: 'https://openrouter.ai/api/v1',
          apiKeys: [],
          models: [
            'deepseek/deepseek-chat',
            'google/gemini-2.0-flash-001',
            'anthropic/claude-3.5-haiku',
            'meta-llama/llama-3.3-70b-instruct',
            'openai/gpt-4o-mini',
          ],
          selectedModel: 'deepseek/deepseek-chat',
          isCustom: false,
        ),
        AiProviderModel(
          id: 'groq',
          name: 'Groq',
          domain: 'https://api.groq.com/openai/v1',
          apiKeys: [],
          models: [
            'llama-3.3-70b-versatile',
            'llama-3.1-8b-instant',
            'mixtral-8x7b-32768',
            'gemma2-9b-it',
          ],
          selectedModel: 'llama-3.3-70b-versatile',
          isCustom: false,
        ),
      ];

  AiProviderModel copyWith({
    String? id,
    String? name,
    String? domain,
    List<String>? apiKeys,
    List<String>? models,
    String? selectedModel,
    bool? isCustom,
  }) {
    return AiProviderModel(
      id: id ?? this.id,
      name: name ?? this.name,
      domain: domain ?? this.domain,
      apiKeys: apiKeys ?? List.from(this.apiKeys),
      models: models ?? List.from(this.models),
      selectedModel: selectedModel ?? this.selectedModel,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'domain': domain,
      'apiKeys': apiKeys,
      'models': models,
      'selectedModel': selectedModel,
      'isCustom': isCustom,
    };
  }

  factory AiProviderModel.fromMap(Map<String, dynamic> map) {
    final rawModels = map['models'];
    final List<String> parsedModels = rawModels is List
        ? rawModels.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : [];

    final rawKeys = map['apiKeys'];
    final List<String> parsedKeys = rawKeys is List
        ? rawKeys.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : [];

    final selModel = map['selectedModel']?.toString() ??
        (parsedModels.isNotEmpty ? parsedModels.first : 'default');

    return AiProviderModel(
      id: map['id']?.toString() ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: map['name']?.toString() ?? 'Custom AI',
      domain: map['domain']?.toString() ?? '',
      apiKeys: parsedKeys,
      models: parsedModels,
      selectedModel: selModel,
      isCustom: map['isCustom'] == true,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AiProviderModel.fromJson(String source) =>
      AiProviderModel.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
