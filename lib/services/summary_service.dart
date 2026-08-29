import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/summary_model.dart';
import '../core/constants/app_constants.dart';

class SummaryService {
  /// Gọi API Tóm tắt nội dung văn bản với cơ chế tự động xoay vòng Key theo từng Provider
  Future<SummaryModel> summarizeText({
    required String chapterId,
    required String text,
    List<String>? apiKeys,
    String? apiKey,
    String? modelName,
    String? domain,
    String? providerName,
    String? providerId,
    String? customPrompt,
    void Function(String failedKey)? onKeyFailed,
  }) async {
    final stopwatch = Stopwatch()..start();
    final prompt = (customPrompt != null && customPrompt.isNotEmpty)
        ? customPrompt
        : AppConstants.defaultSummaryPrompt;
    final model = (modelName != null && modelName.trim().isNotEmpty)
        ? modelName.trim()
        : AppConstants.defaultGeminiModel;
    final pName = (providerName != null && providerName.trim().isNotEmpty)
        ? providerName.trim()
        : 'AI';

    // Chuẩn bị danh sách keys
    final keys = <String>[];
    if (apiKeys != null && apiKeys.isNotEmpty) {
      keys.addAll(apiKeys.where((k) => k.trim().isNotEmpty));
    } else if (apiKey != null && apiKey.trim().isNotEmpty) {
      keys.add(apiKey.trim());
    }

    if (keys.isEmpty) {
      throw Exception('Chưa có API Key cho $pName. Vui lòng thêm Key trong Cài đặt > Cấu hình AI.');
    }

    String lastError = '';

    for (int i = 0; i < keys.length; i++) {
      final currentKey = keys[i];
      try {
        final summaryResult = await _callAiDirect(
          apiKey: currentKey,
          model: model,
          domain: domain,
          providerId: providerId,
          providerName: pName,
          prompt: prompt,
          content: text,
        );

        stopwatch.stop();

        final bullets = _extractBulletPoints(summaryResult);
        return SummaryModel(
          id: 'sum_$chapterId',
          chapterId: chapterId,
          summaryText: summaryResult.trim(),
          bulletPoints: bullets,
          modelUsed: '$model ($pName)',
          processingTimeMs: stopwatch.elapsedMilliseconds,
        );
      } catch (e) {
        lastError = e.toString();
        print('Lỗi $pName API với key ...${currentKey.length > 6 ? currentKey.substring(currentKey.length - 4) : ""}: $e');
        onKeyFailed?.call(currentKey);
        // Tiếp tục thử key kế tiếp trong danh sách
      }
    }

    stopwatch.stop();
    throw Exception('Tất cả API Key $pName đều bị lỗi hoặc hết hạn mức/quota: $lastError');
  }

  /// Gọi API Dịch nội dung chương sang tiếng Việt với cơ chế tự động xoay vòng Key
  Future<String> translateText({
    required String text,
    List<String>? apiKeys,
    String? apiKey,
    String? modelName,
    String? domain,
    String? providerName,
    String? providerId,
    String? customPrompt,
    void Function(String failedKey)? onKeyFailed,
  }) async {
    final prompt = (customPrompt != null && customPrompt.isNotEmpty)
        ? customPrompt
        : AppConstants.defaultTranslatePrompt;
    final model = (modelName != null && modelName.trim().isNotEmpty)
        ? modelName.trim()
        : AppConstants.defaultGeminiModel;
    final pName = (providerName != null && providerName.trim().isNotEmpty)
        ? providerName.trim()
        : 'AI';

    final keys = <String>[];
    if (apiKeys != null && apiKeys.isNotEmpty) {
      keys.addAll(apiKeys.where((k) => k.trim().isNotEmpty));
    } else if (apiKey != null && apiKey.trim().isNotEmpty) {
      keys.add(apiKey.trim());
    }

    if (keys.isEmpty) {
      print('Chưa cấu hình API Key cho $pName để dịch thuật.');
      return text;
    }

    for (int i = 0; i < keys.length; i++) {
      final currentKey = keys[i];
      try {
        final translated = await _callAiDirect(
          apiKey: currentKey,
          model: model,
          domain: domain,
          providerId: providerId,
          providerName: pName,
          prompt: prompt,
          content: text,
          timeout: const Duration(seconds: 90),
        );

        if (translated.trim().isNotEmpty) {
          return translated.trim();
        }
      } catch (e) {
        print('Lỗi $pName Dịch thuật với key ...${currentKey.length > 6 ? currentKey.substring(currentKey.length - 4) : ""}: $e');
        onKeyFailed?.call(currentKey);
      }
    }

    return text; // Giữ nguyên nội dung nếu tất cả key lỗi
  }

  /// Điều phối gọi API phù hợp dựa theo Domain & Provider
  Future<String> _callAiDirect({
    required String apiKey,
    required String model,
    String? domain,
    String? providerId,
    String? providerName,
    required String prompt,
    required String content,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final cleanDomain = domain?.trim() ?? '';
    final pId = providerId?.toLowerCase() ?? '';
    final pName = providerName?.toLowerCase() ?? '';

    // 1. Google Gemini
    final isGemini = pId == 'google-gemini' ||
        cleanDomain.contains('generativelanguage.googleapis.com') ||
        (cleanDomain.isEmpty && pName.contains('gemini'));

    if (isGemini) {
      return _callGeminiDirect(
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        content: content,
        domain: cleanDomain.isNotEmpty ? cleanDomain : 'https://generativelanguage.googleapis.com',
        timeout: timeout,
      );
    }

    // 2. Anthropic Claude
    final isClaude = pId == 'anthropic' ||
        pId == 'claude' ||
        cleanDomain.contains('api.anthropic.com') ||
        pName.contains('claude');

    if (isClaude) {
      return _callAnthropicDirect(
        domain: cleanDomain.isNotEmpty ? cleanDomain : 'https://api.anthropic.com/v1',
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        content: content,
        timeout: timeout,
      );
    }

    // 3. Chuẩn OpenAI-compatible (ChatGPT, DeepSeek, MiMo, OpenRouter, Groq, Custom...)
    return _callOpenAiCompatibleDirect(
      domain: cleanDomain.isNotEmpty ? cleanDomain : 'https://api.openai.com/v1',
      apiKey: apiKey,
      model: model,
      prompt: prompt,
      content: content,
      timeout: timeout,
    );
  }

  /// Gọi trực tiếp endpoint Google Gemini REST API
  Future<String> _callGeminiDirect({
    required String apiKey,
    required String model,
    required String prompt,
    required String content,
    String domain = 'https://generativelanguage.googleapis.com',
    Duration timeout = const Duration(seconds: 60),
  }) async {
    var base = domain.trim();
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    final url = Uri.parse(
      '$base/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final payload = {
      'system_instruction': {
        'parts': [
          {'text': prompt}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': content}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.3,
      },
    };

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: utf8.encode(jsonEncode(payload)),
        )
        .timeout(timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('candidates') &&
            decoded['candidates'] is List &&
            decoded['candidates'].isNotEmpty) {
          final candidate = decoded['candidates'][0];
          final parts = candidate['content']?['parts'];
          if (parts is List && parts.isNotEmpty) {
            final resultText = parts[0]['text']?.toString() ?? '';
            if (resultText.trim().isNotEmpty) {
              return resultText.trim();
            }
          }
        }
      }
      throw Exception('Gemini API không trả về nội dung text hợp lệ.');
    } else {
      String errorMsg = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['error'] != null) {
          errorMsg = '${decoded['error']['message'] ?? errorMsg} (Code: ${decoded['error']['code'] ?? response.statusCode})';
        }
      } catch (_) {
        errorMsg = '$errorMsg: ${response.body}';
      }
      throw Exception('Gemini API Error: $errorMsg');
    }
  }

  /// Gọi endpoint Claude (Anthropic) Messages API
  Future<String> _callAnthropicDirect({
    required String domain,
    required String apiKey,
    required String model,
    required String prompt,
    required String content,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    var rawDomain = domain.trim();
    if (!rawDomain.startsWith('http://') && !rawDomain.startsWith('https://')) {
      rawDomain = 'https://$rawDomain';
    }
    while (rawDomain.endsWith('/')) {
      rawDomain = rawDomain.substring(0, rawDomain.length - 1);
    }

    String endpointUrl;
    if (rawDomain.endsWith('/v1/messages') || rawDomain.endsWith('/messages')) {
      endpointUrl = rawDomain;
    } else if (rawDomain.endsWith('/v1')) {
      endpointUrl = '$rawDomain/messages';
    } else {
      endpointUrl = '$rawDomain/v1/messages';
    }

    final url = Uri.parse(endpointUrl);

    final payload = {
      'model': model,
      'max_tokens': 4096,
      'system': prompt,
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'temperature': 0.3,
    };

    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    };

    final response = await http
        .post(
          url,
          headers: headers,
          body: utf8.encode(jsonEncode(payload)),
        )
        .timeout(timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('content') && decoded['content'] is List) {
          final contentList = decoded['content'] as List;
          final textParts = <String>[];
          for (final item in contentList) {
            if (item is Map && item['type'] == 'text') {
              textParts.add(item['text']?.toString() ?? '');
            }
          }
          final fullText = textParts.join('\n').trim();
          if (fullText.isNotEmpty) {
            return fullText;
          }
        }
      }
      throw Exception('Claude API không trả về nội dung text hợp lệ.');
    } else {
      String errorMsg = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['error'] != null) {
          final err = decoded['error'];
          if (err is Map) {
            errorMsg = '${err['message'] ?? errorMsg}';
          } else {
            errorMsg = '$err';
          }
        }
      } catch (_) {
        errorMsg = '$errorMsg: ${response.body}';
      }
      throw Exception('Claude API Error: $errorMsg');
    }
  }

  /// Gọi endpoint chuẩn OpenAI-compatible REST API (/chat/completions)
  Future<String> _callOpenAiCompatibleDirect({
    required String domain,
    required String apiKey,
    required String model,
    required String prompt,
    required String content,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    var rawDomain = domain.trim();
    if (!rawDomain.startsWith('http://') && !rawDomain.startsWith('https://')) {
      rawDomain = 'https://$rawDomain';
    }
    while (rawDomain.endsWith('/')) {
      rawDomain = rawDomain.substring(0, rawDomain.length - 1);
    }

    String endpointUrl;
    if (rawDomain.endsWith('/chat/completions')) {
      endpointUrl = rawDomain;
    } else {
      endpointUrl = '$rawDomain/chat/completions';
    }

    final url = Uri.parse(endpointUrl);

    final payload = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': prompt},
        {'role': 'user', 'content': content},
      ],
      'temperature': 0.3,
    };

    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer $apiKey',
      'HTTP-Referer': 'https://summarystory.app',
      'X-Title': 'SummaryStory',
    };

    final response = await http
        .post(
          url,
          headers: headers,
          body: utf8.encode(jsonEncode(payload)),
        )
        .timeout(timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('choices') &&
            decoded['choices'] is List &&
            decoded['choices'].isNotEmpty) {
          final choice = decoded['choices'][0];
          final msg = choice['message']?['content'] ?? choice['text'] ?? '';
          if (msg.toString().trim().isNotEmpty) {
            return msg.toString().trim();
          }
        }
        if (decoded.containsKey('candidates') &&
            decoded['candidates'] is List &&
            decoded['candidates'].isNotEmpty) {
          final candidate = decoded['candidates'][0];
          final parts = candidate['content']?['parts'];
          if (parts is List && parts.isNotEmpty) {
            final resultText = parts[0]['text']?.toString() ?? '';
            if (resultText.trim().isNotEmpty) {
              return resultText.trim();
            }
          }
        }
      }
      throw Exception('AI API không trả về nội dung text hợp lệ.');
    } else {
      String errorMsg = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['error'] != null) {
          final err = decoded['error'];
          if (err is Map) {
            errorMsg = '${err['message'] ?? errorMsg}';
          } else {
            errorMsg = '$err';
          }
        }
      } catch (_) {
        errorMsg = '$errorMsg: ${response.body}';
      }
      throw Exception('AI API Error: $errorMsg');
    }
  }

  List<String> _extractBulletPoints(String text) {
    List<String> bullets = [];
    final lines = text.split('\n');
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- ') ||
          trimmed.startsWith('• ') ||
          trimmed.startsWith('* ') ||
          RegExp(r'^\d+\.').hasMatch(trimmed)) {
        bullets.add(trimmed.replaceFirst(RegExp(r'^[-•*]|\d+\.'), '').trim());
      }
    }
    return bullets;
  }
}
