enum VoiceEngineType {
  localOnnx,
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

  static List<VoiceModel> get defaultVoices => [
    // Nguồn: ONNX Offline (Sherpa ONNX)
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
    return VoiceModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      shortDescription: map['shortDescription'] ?? '',
      locale: map['locale'] ?? 'vi-VN',
      gender: map['gender'] ?? 'Female',
      engine: VoiceEngineType.values[map['engine'] is int ? map['engine'] : VoiceEngineType.localOnnx.index],
      localModelPath: map['localModelPath'],
      localConfigPath: map['localConfigPath'],
      speakerId: map['speakerId'],
      isDownloaded: map['isDownloaded'] ?? true,
    );
  }
}
