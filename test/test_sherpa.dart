import 'dart:ffi';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

typedef SetDllDirectoryC = Int32 Function(Pointer<Utf16> lpPathName);
typedef SetDllDirectoryDart = int Function(Pointer<Utf16> lpPathName);

void main() async {
  if (Platform.isWindows) {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final setDllDirectory = kernel32
          .lookupFunction<SetDllDirectoryC, SetDllDirectoryDart>('SetDllDirectoryW');
      
      final windowsPluginDir = r'C:\Users\Gum\AppData\Local\Pub\Cache\hosted\pub.dev\sherpa_onnx_windows-1.13.6\windows'.toNativeUtf16();
      setDllDirectory(windowsPluginDir);
      calloc.free(windowsPluginDir);
    } catch (e) {
      print('Failed to set DLL directory: $e');
    }
  }

  sherpa.initBindings();

  final models = [
    'assets/onnx/Ngọc Huyền.onnx',
    'docs/Onnx/Bông Cúc.onnx',
    'docs/Onnx/adam.onnx',
    'docs/Onnx/Yan .onnx',
  ];

  final espeakDir = Directory('assets/onnx/espeak-ng-data');
  if (!File('${espeakDir.path}/phontab').existsSync()) {
    print('Extracting espeak-ng-data.zip...');
    final zipFile = File('assets/onnx/espeak-ng-data.zip');
    if (zipFile.existsSync()) {
      final bytes = zipFile.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final filePath = '${espeakDir.path}/${file.name}';
        if (file.isFile) {
          final outFile = File(filePath);
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        } else {
          Directory(filePath).createSync(recursive: true);
        }
      }
      print('Extracted espeak-ng-data.');
    }
  }

  for (final modelPath in models) {
    print('\n--- Testing model: $modelPath ---');
    final vitsConfig = sherpa.OfflineTtsVitsModelConfig(
      model: modelPath,
      tokens: 'assets/onnx/tokens.txt',
      dataDir: espeakDir.path,
      noiseScale: 0.667,
      noiseScaleW: 0.8,
      lengthScale: 1.0,
    );

    final modelConfig = sherpa.OfflineTtsModelConfig(
      vits: vitsConfig,
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );

    final ttsConfig = sherpa.OfflineTtsConfig(
      model: modelConfig,
      ruleFsts: '',
      ruleFars: '',
    );

    final tts = sherpa.OfflineTts(ttsConfig);
    print('sampleRate: ${tts.sampleRate}, numSpeakers: ${tts.numSpeakers}');

    final audio = tts.generate(
      text: 'Đêm nay trăng sáng quá, em có nghe thấy tiếng gió thổi không?',
      sid: 0,
      speed: 1.0,
    );
    print('Generated: sampleRate=${audio.sampleRate}, samples count=${audio.samples.length}');
  }
}
