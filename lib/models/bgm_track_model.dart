class BgmTrack {
  final String id;
  final String name;
  final String url;
  final bool isLocal;

  const BgmTrack({
    required this.id,
    required this.name,
    required this.url,
    this.isLocal = false,
  });

  static List<BgmTrack> get defaultTracks => const [
    BgmTrack(
      id: 'bgm1',
      name: 'Nhạc Trung 1',
      url: 'https://archive.org/download/background-chinese/Background%20Chinese%201.mp3',
    ),
    BgmTrack(
      id: 'bgm2',
      name: 'Nhạc Trung 2',
      url: 'https://archive.org/download/background-chinese/Background%20Chinese%202.mp3',
    ),
    BgmTrack(
      id: 'bgm3',
      name: 'Nhạc Trung 3',
      url: 'https://archive.org/download/background-chinese/Background%20Chinese%203.mp3',
    ),
    BgmTrack(
      id: 'bgm4',
      name: 'Mưa và piano 1',
      url: 'https://archive.org/download/no-ads-rain-and-soft-piano-for-healing-sleep-relaxing-music-to-calm-the-mind-and-soothe-the-soul/Rain%20and%20Piano.mp3',
    ),
    BgmTrack(
      id: 'bgm5',
      name: 'Mưa và piano 2',
      url: 'https://archive.org/download/pianoinstrumentrain/Piano%20Instrument%20Rain.mp3',
    ),
    BgmTrack(
      id: 'bgm7',
      name: 'Mưa rơi',
      url: 'https://ia600603.us.archive.org/33/items/rain-on-roof/Rain%20On%20Roof.mp3',
    ),
    BgmTrack(
      id: 'bgm6',
      name: 'Piano',
      url: 'https://archive.org/download/beautifulpianomusicvol1/Beautiful%20Piano%20Music%2C%20Vol%20%201.mp3',
    ),
  ];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'isLocal': isLocal,
    };
  }

  factory BgmTrack.fromMap(Map<String, dynamic> map) {
    return BgmTrack(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      url: map['url'] ?? '',
      isLocal: map['isLocal'] ?? false,
    );
  }
}
