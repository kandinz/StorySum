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
    bool isPriority = false,
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
        try {
          return await tikTokTtsService.synthesize(
            text: text,
            voice: voice,
            storyTitle: storyTitle,
            chapterNumber: chapterNumber,
            audioType: audioType,
            outputFilePath: outputFilePath,
            speed: speed,
            isPriority: isPriority,
            onProgress: onProgress,
          );
        } catch (e) {
          final fallbackVoice = voice.gender == 'Nam'
              ? const VoiceModel(
                  id: 'edge-vi-VN-NamMinhNeural',
                  name: 'Nam Minh (Edge)',
                  shortDescription: 'Edge TTS Nam',
                  engine: VoiceEngineType.edgeTts,
                  locale: 'vi-VN',
                  gender: 'Nam',
                  speakerId: 'vi-VN-NamMinhNeural',
                )
              : const VoiceModel(
                  id: 'edge-vi-VN-HoaiMyNeural',
                  name: 'Hoài My (Edge)',
                  shortDescription: 'Edge TTS Nữ',
                  engine: VoiceEngineType.edgeTts,
                  locale: 'vi-VN',
                  gender: 'Nữ',
                  speakerId: 'vi-VN-HoaiMyNeural',
                );
          return await edgeTtsService.synthesize(
            text: text,
            voice: fallbackVoice,
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
}
