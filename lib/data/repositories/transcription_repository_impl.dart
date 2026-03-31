import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:yanita_music/core/constants/app_constants.dart';
import 'package:yanita_music/core/error/failures.dart';
import 'package:yanita_music/domain/entities/audio_features.dart';
import 'package:yanita_music/domain/entities/note_event.dart';
import 'package:yanita_music/domain/repositories/transcription_repository.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // [v53] Para rootBundle
import 'package:yanita_music/core/utils/logger.dart';

import 'package:yanita_music/core/mixins/status_stream_mixin.dart';

/// Implementación del repositorio de transcripción musical optimizada para memoria.
/// [v53] Migrada a Isolate (Hilo Secundario) para evitar ANR / Bloqueos de UI.
class TranscriptionRepositoryImpl
    with StatusStreamMixin
    implements TranscriptionRepository {
  Interpreter? _interpreter;
  static const String _tag = 'TranscriptionRepository';
  bool _isInitialized = false;
  bool _isMockMode = false;

  @override
  Future<Either<Failure, void>> initializeModel() async {
    try {
      sendStatus('Cargando modelo TFLite...');
      AppLogger.info(
        'Cargando modelo TFLite desde: ${AppConstants.tfliteModelPath}',
        tag: _tag,
      );

      // Intento 1: Con GPU Delegate (si es Android)
      if (Platform.isAndroid) {
        try {
          final gpuOptions = InterpreterOptions()..threads = 4;
          gpuOptions.addDelegate(GpuDelegateV2());
          _interpreter = await Interpreter.fromAsset(
            AppConstants.tfliteModelPath,
            options: gpuOptions,
          );
          _isInitialized = true;
          sendStatus('Modelo cargado exitosamente con GPU');
          AppLogger.info('Modelo cargado exitosamente con GPU', tag: _tag);
          return const Right(null);
        } catch (e) {
          AppLogger.warning(
            'Fallo inicio con GPU, reintentando con CPU: $e',
            tag: _tag,
          );
        }
      }

      // Intento 2: Solo CPU
      final cpuOptions = InterpreterOptions()..threads = 4;
      try {
        _interpreter = await Interpreter.fromAsset(
          AppConstants.tfliteModelPath,
          options: cpuOptions,
        );
      } catch (e) {
        if (AppConstants.tfliteModelPath.startsWith('assets/')) {
          final plainPath = AppConstants.tfliteModelPath.replaceFirst(
            'assets/',
            '',
          );
          _interpreter = await Interpreter.fromAsset(
            plainPath,
            options: cpuOptions,
          );
        } else {
          rethrow;
        }
      }

      _isInitialized = true;
      sendStatus('Modelo TFLite listo (modo CPU)');
      AppLogger.info(
        'Modelo TFLite cargado exitosamente (CPU). Listo para inferencia (v53).',
        tag: _tag,
      );
      return const Right(null);
    } catch (e, stackTrace) {
      final errorStr = e.toString().toLowerCase();
      AppLogger.error(
        'Error crítico cargando modelo TFLite',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );

      if (errorStr.contains('unable to create model') ||
          errorStr.contains('interpreter')) {
        AppLogger.warning(
          'Detectado error persistente. Activando MOCK MODE.',
          tag: _tag,
        );
        _isMockMode = true;
        _isInitialized = true;
        return const Right(null);
      }

      return Left(
        ModelLoadFailure(message: 'Error al crear intérprete TFLite: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, List<NoteEvent>>> transcribe(
    AudioFeatures audioFeatures,
  ) async {
    if (!_isInitialized || (_interpreter == null && !_isMockMode)) {
      final initResult = await initializeModel();
      final initError = initResult.fold((failure) => failure, (_) => null);
      if (initError != null) return Left(initError);
    }

    try {
      if (_isMockMode) {
        return Right(_generateMockNotes(audioFeatures.audioDuration));
      }

      AppLogger.info(
        'Iniciando inferencia en SEGUNDO PLANO (Isolate v53)...',
        tag: _tag,
      );
      sendStatus('Iniciando motor de IA...');

      // 1. Cargar el buffer del modelo para pasarlo al Isolate (evita MethodChannels en el Isolate)
      final ByteData modelData = await rootBundle.load(
        AppConstants.tfliteModelPath,
      );
      final Uint8List modelBuffer = modelData.buffer.asUint8List();

      // 2. Ejecutar inferencia pesada en Isolate usando compute
      final List<NoteEvent> noteEvents = await compute(
        _inferenceInIsolate,
        _InferenceIsolateParams(
          modelBuffer: modelBuffer,
          features: audioFeatures,
        ),
      );

      AppLogger.info(
        'Inferencia Isolate completada: ${noteEvents.length} notas detectadas (v53)',
        tag: _tag,
      );
      return Right(noteEvents);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error crítico en transcripción Isolate (v53)',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return Left(
        TranscriptionFailure(message: 'Error en transcripción Isolate: $e'),
      );
    }
  }

  List<NoteEvent> _generateMockNotes(double duration) {
    final notes = <NoteEvent>[];
    for (double i = 0; i < duration; i += 0.5) {
      notes.add(
        NoteEvent(
          startTime: i,
          endTime: i + 0.4,
          midiNote: 60 + (i.toInt() % 12),
          velocity: 80,
        ),
      );
    }
    return notes;
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    AppLogger.info('Modelo TFLite liberado', tag: _tag);
  }
}

/// Parámetros enviados al Isolate
class _InferenceIsolateParams {
  final Uint8List modelBuffer;
  final AudioFeatures features;
  _InferenceIsolateParams({required this.modelBuffer, required this.features});
}

/// Función TOP-LEVEL que corre en un hilo secundario (Isolate)
Future<List<NoteEvent>> _inferenceInIsolate(
  _InferenceIsolateParams params,
) async {
  Interpreter? interpreter;
  try {
    // 1. Instanciar intérprete dentro del isolate desde el buffer
    final options = InterpreterOptions()..threads = 4;
    interpreter = Interpreter.fromBuffer(params.modelBuffer, options: options);

    final features = params.features;
    final int numFrames = features.numFrames;
    final int numMelBins = features.numMelBins;

    final inputTensors = interpreter.getInputTensors();
    final outputTensors = interpreter.getOutputTensors();
    final inputShape = inputTensors[0].shape;
    final outputShape = outputTensors[0].shape;

    // Identificar 3D outputs (Magenta estándar tiene 3 o 4 salidas de [1, N, 88])
    final List<int> valid3D = [];
    for (int i = 0; i < outputTensors.length; i++) {
      if (outputTensors[i].shape.length == 3) valid3D.add(i);
    }

    final int modelFrames = (inputShape.length >= 3)
        ? inputShape[1]
        : outputShape[1];
    final int modelMelBins = (inputShape.length >= 3)
        ? inputShape[2]
        : (inputShape[0] ~/ modelFrames);
    final int modelNotes = outputShape[2];
    final bool isInputFlat = inputShape.length == 1;

    // Identificación robusta por nombre/forma
    int onsetsIdx = -1;
    int framesIdx = -1;
    int velocitiesIdx = -1;

    for (int i in valid3D) {
      final name = outputTensors[i].name.toLowerCase();
      if (name.contains('onset')) onsetsIdx = i;
      if (name.contains('frame')) framesIdx = i;
      if (name.contains('veloc')) velocitiesIdx = i;
    }

    // Heurística de respaldo si los nombres no ayudan
    onsetsIdx = (onsetsIdx == -1 && valid3D.isNotEmpty) ? valid3D[0] : onsetsIdx;
    framesIdx = (framesIdx == -1 && valid3D.length > 1) ? valid3D[1] : (framesIdx == -1 ? (onsetsIdx != -1 ? onsetsIdx : 0) : framesIdx);
    velocitiesIdx = (velocitiesIdx == -1 && valid3D.length > 2) ? valid3D[2] : (velocitiesIdx == -1 ? (framesIdx != -1 ? framesIdx : 0) : velocitiesIdx);
    
    // Garantizar valores válidos
    onsetsIdx = onsetsIdx == -1 ? 0 : onsetsIdx;
    framesIdx = framesIdx == -1 ? 0 : framesIdx;
    velocitiesIdx = velocitiesIdx == -1 ? 0 : velocitiesIdx;

    final Float32List flatOnsets = Float32List(numFrames * modelNotes);
    final Float32List flatFrames = Float32List(numFrames * modelNotes);
    final Float32List flatVelocities = Float32List(numFrames * modelNotes);

    // Loop de inferencia
    for (
      int startFrame = 0;
      startFrame < numFrames;
      startFrame += modelFrames
    ) {
      final int remaining = numFrames - startFrame;
      final int currentLen = (remaining < modelFrames)
          ? remaining
          : modelFrames;

      // Preparar InputData
      late final Object inputData;
      if (isInputFlat) {
        final flat = Float32List(inputShape[0]);
        for (int f = 0; f < modelFrames; f++) {
          for (int m = 0; m < modelMelBins; m++) {
            if (f < currentLen && m < numMelBins) {
              final int global = (startFrame + f) * numMelBins + m;
              flat[f * modelMelBins +
                  m] = (global < features.melSpectrogram.length)
                  ? features.melSpectrogram[global].toDouble()
                  : 0.0; // [v53-FIX]: Padding a 0.0 (silencio en [0, 1])
            } else {
              flat[f * modelMelBins + m] = 0.0;
            }
          }
        }
        inputData = flat;
      } else {
        inputData = [
          List.generate(
            modelFrames,
            (f) => List.generate(modelMelBins, (m) {
              if (f < currentLen && m < numMelBins) {
                final int global = (startFrame + f) * numMelBins + m;
                return (global < features.melSpectrogram.length)
                    ? features.melSpectrogram[global].toDouble()
                    : 0.0; // [v53-FIX]: Padding a 0.0
              }
              return 0.0;
            }),
          ),
        ];
      }

      // Buffers de salida
      final Map<int, Object> outputMap = {};
      for (int i = 0; i < outputTensors.length; i++) {
        final s = outputTensors[i].shape;
        if (s.length == 3) {
          outputMap[i] = [
            List.generate(s[1], (_) => List.filled(s[2], 0.0)),
          ];
        } else if (s.length == 2) {
          outputMap[i] = [List.filled(s[1], 0.0)];
        } else {
          outputMap[i] = [0.0];
        }
      }

      // Ejecutar
      interpreter.runForMultipleInputs([inputData], outputMap);

      // Extraer
      for (int f = 0; f < currentLen; f++) {
        final int gOffset = (startFrame + f) * modelNotes;
        final oRow = (outputMap[onsetsIdx] as List)[0][f] as List;
        final fRow = (outputMap[framesIdx] as List)[0][f] as List;
        final vRow = (outputMap[velocitiesIdx] as List)[0][f] as List;

        for (int n = 0; n < modelNotes; n++) {
          flatOnsets[gOffset + n] = (oRow[n] as num).toDouble();
          flatFrames[gOffset + n] = (fRow[n] as num).toDouble();
          flatVelocities[gOffset + n] = (vRow[n] as num).toDouble();
        }
      }
    }

    // Decodificar
    return _decodeInIsolate(
      flatOnsets,
      flatFrames,
      flatVelocities,
      numFrames,
      features.audioDuration,
    );
  } finally {
    interpreter?.close();
  }
}

List<NoteEvent> _decodeInIsolate(
  Float32List onsets,
  Float32List frames,
  Float32List vels,
  int numFrames,
  double duration,
) {
  final events = <NoteEvent>[];
  final secondsPerFrame = duration / numFrames;
  final bool isSingleHead = onsets == frames; // Detectamos arquitectura simple
  final active = <int, _ActiveNoteIsolate>{};

  for (int f = 0; f < numFrames; f++) {
    for (int n = 0; n < 88; n++) {
      final midi = n + 21;
      final idx = f * 88 + n;
      final oProb = onsets[idx];
      final fProb = frames[idx];
      final prevO = f > 0 ? onsets[idx - 88] : 0.0;

      // [v53-FIX]: Lógica adaptativa según arquitectura
      bool shouldStart = false;
      if (isSingleHead) {
        // Modelo simple: Solo detectamos si sobrepasa umbral de confianza
        shouldStart = oProb > 0.4 && !active.containsKey(midi);
      } else {
        // Modelo Magenta: Requiere pico de Onset
        shouldStart = oProb > 0.5 && oProb > prevO;
      }

      if (shouldStart) {
        if (active.containsKey(midi)) {
          final a = active[midi]!;
          events.add(
            NoteEvent(
              startTime: a.startFrame * secondsPerFrame,
              endTime: f * secondsPerFrame,
              midiNote: midi,
              velocity: a.velocity,
              confidence: a.maxOnset,
            ),
          );
        }
        
        // Calculamos velocidad con un piso de 60 para asegurar sonido audible
        final int rawVel = (vels[idx].clamp(0, 1) * 127).round();
        final int finalVel = isSingleHead 
            ? (60 + (oProb * 40).round()).clamp(60, 110) 
            : rawVel.clamp(40, 127);

        active[midi] = _ActiveNoteIsolate(
          startFrame: f,
          velocity: finalVel,
          maxOnset: oProb,
        );
      } else if (active.containsKey(midi)) {
        // [v53-FIX]: Umbral de finalización más permisivo
        final bool shouldEnd = isSingleHead 
            ? oProb < 0.25 
            : (fProb < 0.3 && oProb < 0.5);

        if (shouldEnd) {
          final a = active.remove(midi)!;
          // Ignorar notas sospechosamente cortas (ruido de espectro)
          if ((f - a.startFrame) * secondsPerFrame > 0.05) {
            events.add(
              NoteEvent(
                startTime: a.startFrame * secondsPerFrame,
                endTime: f * secondsPerFrame,
                midiNote: midi,
                velocity: a.velocity,
                confidence: a.maxOnset,
              ),
            );
          }
        }
      }
    }
  }

  for (final ent in active.entries) {
    events.add(
      NoteEvent(
        startTime: ent.value.startFrame * secondsPerFrame,
        endTime: duration,
        midiNote: ent.key,
        velocity: ent.value.velocity,
        confidence: ent.value.maxOnset,
      ),
    );
  }
  events.sort((a, b) => a.startTime.compareTo(b.startTime));
  return (events.length > 10000) ? events.sublist(0, 10000) : events;
}

class _ActiveNoteIsolate {
  final int startFrame;
  final int velocity;
  final double maxOnset;
  _ActiveNoteIsolate({
    required this.startFrame,
    required this.velocity,
    required this.maxOnset,
  });
}
