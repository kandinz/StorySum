import 'dart:async';
import '../models/tts_synthesis_result.dart';
import '../models/voice_model.dart';
import 'onnx_tts_service.dart';
import 'edge_tts_service.dart';
import 'tiktok_tts_service.dart';

class UnifiedTtsService {
  final OnnxTtsService onnxTtsService;
  final EdgeTtsService edgeTtsService;
  final TikTokTtsService tikTokTtsService;

  UnifiedTtsService({
    OnnxTtsService? onnxTts,
    EdgeTtsService? edgeTts,
    TikTokTtsService? tikTokTts,
  })  : onnxTtsService = onnxTts ?? OnnxTtsService(),
        edgeTtsService = edgeTts ?? EdgeTtsService(),
        tikTokTtsService = tikTokTts ?? TikTokTtsService();

  static String getAudioExtension(VoiceModel voice) {
    switch (voice.engine) {
      case VoiceEngineType.localOnnx:
        return 'wav';
      case VoiceEngineType.edgeTts:
      case VoiceEngineType.tiktokTts:
        return 'mp3';
    }
  }

  Future<TtsSynthesisResult> synthesize({
    required String text,
    required VoiceModel voice,
    required String storyTitle,
    required int chapterNumber,
    String audioType = 'summary',
    String? outputFilePath,
    double speed = 1.0,
    Function(double progress)? onProgress,
  }) async {
    switch (voice.engine) {
      case VoiceEngineType.localOnnx:
        return await onnxTtsService.synthesizeOffline(
          text: text,
          voice: voice,
          storyTitle: storyTitle,
          chapterNumber: chapterNumber,
          audioType: audioType,
          outputFilePath: outputFilePath,
          speed: speed,
          onProgress: onProgress,
        );

      case VoiceEngineType.edgeTts:
        return await edgeTtsService.synthesize(
          text: text,
          voice: voice,
          storyTitle: storyTitle,
          chapterNumber: chapterNumber,
          audioType: audioType,
          outputFilePath: outputFilePath,
          speed: speed,
          onProgress: onProgress,
        );

      case VoiceEngineType.tiktokTts:
        return await tikTokTtsService.synthesize(
          text: text,
          voice: voice,
          storyTitle: storyTitle,
          chapterNumber: chapterNumber,
          audioType: audioType,
          outputFilePath: outputFilePath,
          speed: speed,
          onProgress: onProgress,
        );
    }
  }
}
