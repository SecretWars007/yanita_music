import 'dart:isolate';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dartz/dartz.dart';
import 'package:yanita_music/core/error/exceptions.dart';
import 'package:yanita_music/core/error/failures.dart';
import 'package:yanita_music/core/security/file_validator.dart';
import 'package:yanita_music/core/utils/audio_converter.dart';
import 'package:yanita_music/data/datasources/native/audio_processor_ffi.dart';
import 'package:yanita_music/core/utils/logger.dart';

import 'package:yanita_music/domain/entities/audio_features.dart';
import 'package:yanita_music/domain/repositories/audio_repository.dart';

import 'package:yanita_music/core/mixins/status_stream_mixin.dart';

/// Implementación del repositorio de audio.
class AudioRepositoryImpl with StatusStreamMixin implements AudioRepository {
  final FileValidator _fileValidator;
  final AudioConverter _audioConverter;

  AudioRepositoryImpl({
    required FileValidator fileValidator,
    AudioConverter audioConverter = const AudioConverter(),
  })  : _fileValidator = fileValidator,
        _audioConverter = audioConverter;

  static const String _tag = 'AudioRepository';


  @override
  Future<Either<Failure, AudioFeatures>> processAudioFile(
    String filePath,
  ) async {
    try {
      AppLogger.info('Procesando archivo: $filePath', tag: _tag);
      
      // 1. Validar archivo
      sendStatus('Validando archivo de audio...');
      final checksum = await _fileValidator.validateAudioFile(filePath);
      AppLogger.debug('Archivo validado. Checksum: $checksum', tag: _tag);

      // 2. Crear copia local segura en el sandbox (Evita errores de permisos/URIs en Android)
      sendStatus('Preparando copia local de audio...');
      final tempDir = await getTemporaryDirectory();
      final localInputPath = p.join(tempDir.path, 'input_${DateTime.now().millisecondsSinceEpoch}_${p.basename(filePath)}');
      await File(filePath).copy(localInputPath);
      AppLogger.debug('Copia local creada: $localInputPath', tag: _tag);

      // 3. Convertir a WAV (16kHz, mono) usando FFmpeg
      sendStatus('Convirtiendo audio a WAV profesional (FFmpeg)...');
      String wavPath;
      try {
        wavPath = await _audioConverter.convertToWav(localInputPath);
        AppLogger.debug('Conversión FFmpeg exitosa: $wavPath', tag: _tag);
      } finally {
        // Eliminar la copia del input original una vez convertido
        _audioConverter.cleanTempFile(localInputPath);
      }

      try {
        // 3. Procesar WAV con módulo C++ FFI
        sendStatus('Analizando espectro Mel (C++ FFI)...');
        
        final result = await Isolate.run(() {
          final processor = AudioProcessorFFI();
          processor.initialize();
          return processor.processFile(wavPath);
        });
        
        // [v53-FIX]: Validación de contenido de audio (Solo Piano Solista)
        if (result.pianoConfidence < 0.3) {
          AppLogger.warning(
            'Audio rechazado por baja confianza de piano: ${result.pianoConfidence.toStringAsFixed(2)}',
            tag: _tag,
          );
          throw const AudioProcessingException(
            message: 'No se puede procesar este archivo. Solo se permite música de piano solo.',
          );
        }

        AppLogger.info('Procesamiento C++ FFI completado: ${result.duration.toStringAsFixed(1)}s (Confianza: ${result.pianoConfidence.toStringAsFixed(2)})', tag: _tag);

        // 4. Convertir record nativo a entidad de dominio
        final features = AudioFeatures(
          melSpectrogram: result.spectrogram,
          numFrames: result.numFrames,
          numMelBins: result.numMelBins,
          audioDuration: result.duration,
          sampleRate: 16000,
          sourceChecksum: checksum,
          wavPath: wavPath, // Retornamos la ruta del WAV persistido
        );

        return Right(features);
      } catch (e) {
        // Si hay error en el procesamiento nativo, sí limpiamos el WAV temporal
        _audioConverter.cleanTempFile(wavPath);
        rethrow;
      }


    } on FileValidationException catch (e, stackTrace) {
      AppLogger.error('Fallo en validación de archivo: ${e.message}', tag: _tag, error: e, stackTrace: stackTrace);
      return Left(FileValidationFailure(message: e.message));
    } on AudioProcessingException catch (e, stackTrace) {
      AppLogger.error('Fallo en procesamiento de audio: ${e.message}', tag: _tag, error: e, stackTrace: stackTrace);
      return Left(AudioProcessingFailure(message: e.message));
    } on Exception catch (e, stackTrace) {
      AppLogger.error('Error inesperado en AudioRepository', tag: _tag, error: e, stackTrace: stackTrace);
      return Left(AudioProcessingFailure(
        message: 'Error inesperado al procesar audio: $e',
      ));
    }
  }

  @override
  Future<Either<Failure, AudioFeatures>> processAudioBuffer(
    List<int> audioBytes,
  ) async {
    // Pendiente: Implementar procesamiento desde buffer de bytes
    // cuando se integre la captura en vivo de audio.
    return const Left(AudioProcessingFailure(
      message: 'Procesamiento desde buffer aún no implementado',
    ));
  }
}
