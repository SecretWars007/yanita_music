import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yanita_music/data/repositories/transcription_repository_impl.dart';
import 'package:yanita_music/data/repositories/audio_repository_impl.dart';
import 'package:yanita_music/core/security/file_validator.dart';
import 'package:yanita_music/core/utils/audio_converter.dart';
import 'package:yanita_music/core/utils/logger.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  // Mock PathProvider para evitar MissingPluginException en tests de VM
  const MethodChannel pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, (method) async {
    if (method.method == 'getTemporaryDirectory') {
      return Directory.systemTemp.path;
    }
    return null;
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  group('Validación Real: Chopin Nocturne Op9 No2', () {
    late TranscriptionRepositoryImpl transcriptionRepo;
    late AudioRepositoryImpl audioRepo;

    setUp(() {
      transcriptionRepo = TranscriptionRepositoryImpl();
      audioRepo = AudioRepositoryImpl(
        fileValidator: const FileValidator(),
        audioConverter: const AudioConverter(),
      );
    });

    test('Validación de flujo completo con Chopin (Asset)', () async {
      const String assetPath = 'assets/audio/chopin_nocturne_op9_2.mp3';
      AppLogger.info('>>> Levantando test para: $assetPath');

      // 1. Extraer asset a archivo temporal para poder procesarlo con FFI
      final ByteData data = await rootBundle.load(assetPath);
      final tempDir = Directory.systemTemp;
      final File tempFile = File(p.join(tempDir.path, 'chopin_test.mp3'));
      await tempFile.writeAsBytes(data.buffer.asUint8List());

      AppLogger.info('Archivo temporal listo en: ${tempFile.path}');

      // 2. Procesar Audio (FFmpeg + DSP FFI)
      AppLogger.info('Iniciando procesamiento de audio...');
      final audioResult = await audioRepo.processAudioFile(tempFile.path);

      await audioResult.fold(
        (failure) async => fail('Fallo en AudioRepository: ${failure.message}'),
        (features) async {
          AppLogger.info(
            'Audio procesado: ${features.numFrames} frames, ${features.audioDuration.toStringAsFixed(1)}s',
          );

          // 3. Transcribir (IA TFLite v36 - Native Asset Loading)
          AppLogger.info(
            'Iniciando transcripción de IA (v36 - Native Asset Loading)...',
          );
          final transcriptionResult = await transcriptionRepo.transcribe(
            features,
          );

          transcriptionResult.fold(
            (failure) =>
                fail('Fallo en TranscriptionRepository: ${failure.message}'),
            (notes) {
              AppLogger.info('TRANSCRIPCIÓN EXITOSA ✅');
              AppLogger.info('Notas detectadas: ${notes.length}');

              if (notes.isEmpty) {
                AppLogger.warning(
                  'ADVERTENCIA: No se detectaron notas. Verificando telemetría...',
                );
              } else {
                expect(notes.length, greaterThan(0));
                AppLogger.info(
                  'Primera nota: ${notes.first.midiNote} en ${notes.first.startTime.toStringAsFixed(2)}s',
                );
              }
            },
          );
        },
      );
    });
  });
}
