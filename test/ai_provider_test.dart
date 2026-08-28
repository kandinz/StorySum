import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_story/models/ai_provider_model.dart';
import 'package:app_story/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiProviderModel Tests', () {
    test('Default Gemini Provider has correct configuration', () {
      final gemini = AiProviderModel.defaultGeminiProvider;
      expect(gemini.id, 'google-gemini');
      expect(gemini.name, 'Google Gemini');
      expect(gemini.domain, 'https://generativelanguage.googleapis.com');
      expect(gemini.isCustom, false);
      expect(gemini.models, contains('gemini-2.5-flash-lite'));
      expect(gemini.selectedModel, 'gemini-2.5-flash-lite');
    });

    test('Default Built-in Providers contains all 7 major providers', () {
      final builtins = AiProviderModel.defaultBuiltinProviders;
      final ids = builtins.map((p) => p.id).toList();

      expect(ids, containsAll([
        'google-gemini',
        'openai',
        'anthropic',
        'deepseek',
        'mimo',
        'openrouter',
        'groq',
      ]));

      // Verify each provider has built-in models
      for (final provider in builtins) {
        expect(provider.models, isNotEmpty, reason: 'Provider ${provider.name} should have default models');
        expect(provider.models, contains(provider.selectedModel));
        expect(provider.domain, isNotEmpty);
      }
    });

    test('Serialization toMap and fromMap works correctly', () {
      final custom = AiProviderModel(
        id: 'custom_123',
        name: 'DeepSeek',
        domain: 'https://api.deepseek.com/v1',
        apiKeys: ['sk-key1', 'sk-key2'],
        models: ['deepseek-chat', 'deepseek-reasoner'],
        selectedModel: 'deepseek-chat',
        isCustom: true,
      );

      final map = custom.toMap();
      final restored = AiProviderModel.fromMap(map);

      expect(restored.id, 'custom_123');
      expect(restored.name, 'DeepSeek');
      expect(restored.domain, 'https://api.deepseek.com/v1');
      expect(restored.apiKeys, ['sk-key1', 'sk-key2']);
      expect(restored.models, ['deepseek-chat', 'deepseek-reasoner']);
      expect(restored.selectedModel, 'deepseek-chat');
      expect(restored.isCustom, true);
    });
  });

  group('SettingsProvider Multi-Provider AI Tests', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider();
      await settings.init();
    });

    test('Initializes with default Google Gemini provider and all builtins', () {
      expect(settings.providers.length, equals(AiProviderModel.defaultBuiltinProviders.length));
      expect(settings.activeProvider.id, 'google-gemini');
      expect(settings.aiProvider, 'Google Gemini');
      expect(settings.currentProviderDomain, 'https://generativelanguage.googleapis.com');
    });

    test('Switching between built-in providers loads respective models and domains', () async {
      // Switch to OpenAI ChatGPT
      await settings.setActiveProviderById('openai');
      expect(settings.aiProvider, 'ChatGPT (OpenAI)');
      expect(settings.currentProviderDomain, 'https://api.openai.com/v1');
      expect(settings.currentProviderModels, contains('gpt-4o-mini'));

      // Switch to Claude Anthropic
      await settings.setActiveProviderById('anthropic');
      expect(settings.aiProvider, 'Claude (Anthropic)');
      expect(settings.currentProviderDomain, 'https://api.anthropic.com/v1');
      expect(settings.currentProviderModels, contains('claude-3-5-haiku-20241022'));

      // Switch to DeepSeek
      await settings.setActiveProviderById('deepseek');
      expect(settings.aiProvider, 'DeepSeek');
      expect(settings.currentProviderModels, contains('deepseek-chat'));

      // Switch to MiMo
      await settings.setActiveProviderById('mimo');
      expect(settings.aiProvider, 'MiMo AI');
      expect(settings.currentProviderModels, contains('mimo-v2'));
    });

    test('Add custom provider and switch active provider', () async {
      final initialCount = settings.providers.length;
      await settings.addCustomProvider(
        name: 'Custom Server',
        domain: 'http://localhost:8000/v1',
        defaultModel: 'llama-local',
      );

      expect(settings.providers.length, initialCount + 1);
      expect(settings.activeProvider.name, 'Custom Server');
      expect(settings.activeProvider.domain, 'http://localhost:8000/v1');
      expect(settings.selectedModel, 'llama-local');
      expect(settings.currentProviderModels, ['llama-local']);
    });

    test('Add API keys and models to specific active provider', () async {
      // 1. Thêm key cho Gemini
      await settings.setActiveProviderById('google-gemini');
      await settings.addApiKeyToActiveProvider('gemini-key-1');
      await settings.addApiKeyToActiveProvider('gemini-key-2');
      expect(settings.currentProviderApiKeys, ['gemini-key-1', 'gemini-key-2']);

      // 2. Chuyển sang Claude và thêm key riêng của Claude
      await settings.setActiveProviderById('anthropic');
      await settings.addApiKeyToActiveProvider('sk-ant-api-test');
      await settings.addModelToActiveProvider('claude-custom-finetuned');

      expect(settings.currentProviderApiKeys, ['sk-ant-api-test']);
      expect(settings.currentProviderModels, contains('claude-custom-finetuned'));

      // 3. Chuyển lại Gemini -> Key của Gemini phải giữ nguyên và độc lập
      await settings.setActiveProviderById('google-gemini');
      expect(settings.currentProviderApiKeys, ['gemini-key-1', 'gemini-key-2']);
      expect(settings.currentProviderModels, contains('gemini-2.5-flash-lite'));
      expect(settings.currentProviderModels, isNot(contains('claude-custom-finetuned')));

      // 4. Chuyển lại Claude -> Key của Claude được tải đúng
      await settings.setActiveProviderById('anthropic');
      expect(settings.currentProviderApiKeys, ['sk-ant-api-test']);
      expect(settings.currentProviderModels, contains('claude-custom-finetuned'));
    });

    test('Reset models for built-in provider', () async {
      await settings.setActiveProviderById('deepseek');
      await settings.addModelToActiveProvider('my-experimental-model');
      expect(settings.currentProviderModels, contains('my-experimental-model'));

      await settings.resetProviderModels('deepseek');
      expect(settings.currentProviderModels, isNot(contains('my-experimental-model')));
      expect(settings.currentProviderModels, contains('deepseek-chat'));
    });

    test('Update and Delete custom provider', () async {
      await settings.addCustomProvider(
        name: 'Ollama Test',
        domain: 'http://localhost:11434/v1',
        defaultModel: 'mistral',
      );

      final customId = settings.activeProviderId;
      expect(settings.aiProvider, 'Ollama Test');

      // Update provider
      await settings.updateCustomProvider(
        providerId: customId,
        name: 'Ollama Pro',
        domain: 'http://localhost:11434/v2',
      );
      expect(settings.aiProvider, 'Ollama Pro');
      expect(settings.currentProviderDomain, 'http://localhost:11434/v2');

      // Delete provider -> switches back to google-gemini
      await settings.deleteCustomProvider(customId);
      expect(settings.activeProviderId, 'google-gemini');
      expect(settings.aiProvider, 'Google Gemini');
      expect(settings.providers.any((p) => p.id == customId), isFalse);
    });
  });
}
