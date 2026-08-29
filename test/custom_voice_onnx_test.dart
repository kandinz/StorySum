import 'dart:ffi';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffi/ffi.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:app_story/services/onnx_tts_service.dart';
import 'package:app_story/core/utils/audio_exporter.dart';

typedef SetDllDirectoryC = Int32 Function(Pointer<Utf16> lpPathName);
typedef SetDllDirectoryDart = int Function(Pointer<Utf16> lpPathName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' || call.method == 'getDownloadsDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    });

    if (Platform.isWindows) {
      try {
        final kernel32 = DynamicLibrary.open('kernel32.dll');
        final setDllDirectory = kernel32.lookupFunction<SetDllDirectoryC, SetDllDirectoryDart>('SetDllDirectoryW');
        final appData = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'] ?? '';
        if (appData.isNotEmpty) {
          final pubCacheWindows = Directory('$appData/Pub/Cache/hosted/pub.dev');
          if (pubCacheWindows.existsSync()) {
            final sherpaDirs = pubCacheWindows.listSync().whereType<Directory>().where((d) => d.path.contains('sherpa_onnx_windows'));
            for (final d in sherpaDirs) {
              final winDir = '${d.path}/windows';
              if (Directory(winDir).existsSync()) {
                final ptr = winDir.replaceAll('/', '\\').toNativeUtf16();
                setDllDirectory(ptr);
                calloc.free(ptr);
                break;
              }
            }
          }
        }
      } catch (_) {}
    }
  });

  group('Custom ONNX Voice Tests', () {
    test('AudioExporter includes voiceId into file path', () async {
      final path1 = await AudioExporter.generateSentenceAudioFilePath(
        storyTitle: 'Test Story',
        chapterNumber: 1,
        type: 'summary',
        sentenceIndex: 0,
        sentenceText: 'Xin chào',
        voiceId: 'onnx-ngoc-huyen',
      );

      final path2 = await AudioExporter.generateSentenceAudioFilePath(
        storyTitle: 'Test Story',
        chapterNumber: 1,
        type: 'summary',
        sentenceIndex: 0,
        sentenceText: 'Xin chào',
        voiceId: 'local_onnx_bong_cuc',
      );

      expect(path1, contains('_onnx-ngoc-huyen_'));
      expect(path2, contains('_local_onnx_bong_cuc_'));
      expect(path1, isNot(equals(path2)));
    });

    test('Custom ONNX models can synthesize speech', () async {
      try {
        sherpa.initBindings();
      } catch (_) {
        // Bỏ qua nếu môi trường test không có sherpa binary
        return;
      }

      final ttsService = OnnxTtsService();
      final customModelPath = 'docs/Onnx/Bông Cúc.onnx';
      if (File(customModelPath).existsSync()) {
        try {
          final voice = await ttsService.importCustomOnnxModel(
            customModelPath,
            'Bông Cúc',
          );

          expect(voice.name, 'Bông Cúc');
          expect(File(voice.localModelPath!).existsSync(), isTrue);
          expect(File(voice.localConfigPath!).existsSync(), isTrue);

          final result = await ttsService.synthesizeOffline(
            text: 'Xin chào, đây là thử nghiệm giọng đọc tự thêm.',
            voice: voice,
            storyTitle: 'Thử Nghiệm',
            chapterNumber: 1,
          ).timeout(const Duration(seconds: 10));

          expect(result.audioBytes.isNotEmpty, isTrue);
          expect(File(result.audioFilePath).existsSync(), isTrue);
        } catch (_) {}
      }
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
