enum VoiceEngineType {
  localOnnx,
  edgeTts,
  tiktokTts,
}

class VoiceModel {
  final String id;
  final String name;
  final String shortDescription;
  final String locale;
  final String gender;
  final VoiceEngineType engine;
  final String? localModelPath;
  final String? localConfigPath;
  final String? speakerId;
  final bool isDownloaded;

  const VoiceModel({
    required this.id,
    required this.name,
    required this.shortDescription,
    this.locale = 'vi-VN',
    this.gender = 'Female',
    this.engine = VoiceEngineType.localOnnx,
    this.localModelPath,
    this.localConfigPath,
    this.speakerId,
    this.isDownloaded = true,
  });

  bool get isOnline => engine != VoiceEngineType.localOnnx;

  String get engineDisplayName {
    switch (engine) {
      case VoiceEngineType.localOnnx:
        return 'ONNX Offline';
      case VoiceEngineType.edgeTts:
        return 'Edge TTS';
      case VoiceEngineType.tiktokTts:
        return 'TikTok TTS';
    }
  }

  static List<VoiceModel> get defaultVoices => [
    // 1. Nguồn: ONNX Offline (Sherpa ONNX)
    const VoiceModel(
      id: 'onnx-ngoc-huyen',
      name: 'Ngọc Huyền',
      shortDescription: 'Giọng Nữ Offline (Sherpa ONNX)',
      gender: 'Nữ',
      locale: 'vi-VN',
      engine: VoiceEngineType.localOnnx,
      localModelPath: 'assets/onnx/Ngọc Huyền.onnx',
      localConfigPath: 'assets/onnx/tokens.txt',
    ),
    const VoiceModel(
      id: 'onnx-bong-cuc',
      name: 'Bông Cúc',
      shortDescription: 'Giọng Nữ Offline (Sherpa ONNX)',
      gender: 'Nữ',
      locale: 'vi-VN',
      engine: VoiceEngineType.localOnnx,
      localModelPath: 'assets/onnx/Bông Cúc.onnx',
      localConfigPath: 'assets/onnx/tokens.txt',
    ),

    // 2. Nguồn: Edge TTS (Online)
    const VoiceModel(
      id: 'edge-vi-VN-HoaiMyNeural',
      name: 'Hoài My',
      shortDescription: 'Edge TTS - Giọng Nữ Truyền Cảm',
      gender: 'Nữ',
      locale: 'vi-VN',
      engine: VoiceEngineType.edgeTts,
      speakerId: 'vi-VN-HoaiMyNeural',
      isDownloaded: true,
    ),
    const VoiceModel(
      id: 'edge-vi-VN-NamMinhNeural',
      name: 'Nam Minh',
      shortDescription: 'Edge TTS - Giọng Nam Trầm Ấm',
      gender: 'Nam',
      locale: 'vi-VN',
      engine: VoiceEngineType.edgeTts,
      speakerId: 'vi-VN-NamMinhNeural',
      isDownloaded: true,
    ),

    // 3. Nguồn: TikTok TTS (Online WebSocket)
    const VoiceModel(
      id: 'tiktok-BV074_streaming',
      name: 'Cô gái hoạt ngôn',
      shortDescription: 'TikTok - Giọng Nữ Hoạt Bát',
      gender: 'Nữ',
      locale: 'vi-VN',
      engine: VoiceEngineType.tiktokTts,
      speakerId: 'BV074_streaming',
      isDownloaded: true,
    ),
    const VoiceModel(
      id: 'tiktok-BV421_vivn_streaming',
      name: 'Cô gái ngọt ngào',
      shortDescription: 'TikTok - Giọng Nữ Ngọt Ngào',
      gender: 'Nữ',
      locale: 'vi-VN',
      engine: VoiceEngineType.tiktokTts,
      speakerId: 'BV421_vivn_streaming',
      isDownloaded: true,
    ),
    const VoiceModel(
      id: 'tiktok-BV075_streaming',
      name: 'Thanh niên tự tin',
      shortDescription: 'TikTok - Giọng Nam Tự Tin',
      gender: 'Nam',
      locale: 'vi-VN',
      engine: VoiceEngineType.tiktokTts,
      speakerId: 'BV075_streaming',
      isDownloaded: true,
    ),
    const VoiceModel(
      id: 'tiktok-vi_female_huong',
      name: 'Giọng nữ phổ thông',
      shortDescription: 'TikTok - Giọng Nữ Chuẩn Phổ Thông',
      gender: 'Nữ',
      locale: 'vi-VN',
      engine: VoiceEngineType.tiktokTts,
      speakerId: 'vi_female_huong',
      isDownloaded: true,
    ),
  ];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'shortDescription': shortDescription,
      'locale': locale,
      'gender': gender,
      'engine': engine.index,
      'localModelPath': localModelPath,
      'localConfigPath': localConfigPath,
      'speakerId': speakerId,
      'isDownloaded': isDownloaded,
    };
  }

  factory VoiceModel.fromMap(Map<String, dynamic> map) {
    final engineIndex = map['engine'] is int ? map['engine'] as int : VoiceEngineType.localOnnx.index;
    final engine = engineIndex >= 0 && engineIndex < VoiceEngineType.values.length
        ? VoiceEngineType.values[engineIndex]
        : VoiceEngineType.localOnnx;

    return VoiceModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      shortDescription: map['shortDescription'] ?? '',
      locale: map['locale'] ?? 'vi-VN',
      gender: map['gender'] ?? 'Female',
      engine: engine,
      localModelPath: map['localModelPath'],
      localConfigPath: map['localConfigPath'],
      speakerId: map['speakerId'],
      isDownloaded: map['isDownloaded'] ?? true,
    );
  }
}
