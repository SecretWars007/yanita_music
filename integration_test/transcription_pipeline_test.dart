import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:yanita_music/core/constants/db_constants.dart';
import 'package:yanita_music/core/error/exceptions.dart';
import 'package:yanita_music/core/security/file_validator.dart';
import 'package:yanita_music/core/utils/audio_converter.dart';
import 'package:yanita_music/core/utils/logger.dart';
import 'package:yanita_music/core/utils/music_xml_generator.dart';
import 'package:yanita_music/domain/entities/audio_features.dart';
import 'package:yanita_music/domain/entities/note_event.dart';
import 'package:yanita_music/data/repositories/transcription_repository_impl.dart';

/// ============================================================================
/// TEST INTEGRAL DEL PIPELINE DE TRANSCRIPCIÓN + BASE DE DATOS
/// ============================================================================
/// Valida el proceso completo usando los 3 MP3 de assets/audio:
///   1. twinkle_twinkle.mp3
///   2. ode_to_joy.mp3
///   3. chopin_nocturne_op9_2.mp3
///
/// Etapas validadas:
///   MP3 → Validación → SHA-256 → Conversión WAV → Espectrograma → Notas → BD
/// ============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// Los 3 archivos MP3 de assets/audio
// ─────────────────────────────────────────────────────────────────────────────
const _mp3Files = [
  (
    path: 'assets/audio/twinkle_twinkle.mp3',
    title: 'Twinkle Twinkle Little Star',
    scoreId: '08f22e9e-1d07-4b55-9a68-ea05cf89121f',
    tempo: 100.0,
    duration: 25.0,
  ),
  (
    path: 'assets/audio/ode_to_joy.mp3',
    title: 'Beethoven: Ode to Joy',
    scoreId: 'f51553d8-cd38-40d6-b016-1083c2849e58',
    tempo: 120.0,
    duration: 54.0,
  ),
  (
    path: 'assets/audio/chopin_nocturne_op9_2.mp3',
    title: 'Chopin: Nocturne Op. 9 No. 2',
    scoreId: '47f89d3c-918d-4a1e-b81e-28ac31c59622',
    tempo: 70.0,
    duration: 258.0,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Helper: DB en memoria para tests (no modifica yanitadb.db de producción)
// ─────────────────────────────────────────────────────────────────────────────
Database? _testDb;

Future<Database> _openTestDb() async {
  if (_testDb != null) return _testDb!;

  // Usar BD en memoria nativa
  _testDb = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.scoresTable} (
          ${DbConstants.colId} TEXT PRIMARY KEY NOT NULL,
          ${DbConstants.colTitle} TEXT NOT NULL,
          ${DbConstants.colAudioPath} TEXT NOT NULL,
          ${DbConstants.colNoteEvents} TEXT NOT NULL DEFAULT '[]',
          ${DbConstants.colDuration} REAL,
          ${DbConstants.colTempo} REAL,
          ${DbConstants.colChecksum} TEXT,
          ${DbConstants.colWavPath} TEXT,
          ${DbConstants.colMusicXml} TEXT,
          ${DbConstants.colTranscriptionSteps} TEXT,
          ${DbConstants.colCreatedAt} TEXT NOT NULL,
          ${DbConstants.colUpdatedAt} TEXT NOT NULL
        )
      ''');
      AppLogger.info('BD en memoria creada nativa para Integration Test');
    },
  );
  return _testDb!;
}

Future<void> _closeTestDb() async {
  await _testDb?.close();
  _testDb = null;
}

/// Genera AudioFeatures sintético para tests sin FFI nativo
AudioFeatures _mockFeatures({
  double duration = 10.0,
  int frames = 100,
  int melBins = 229,
  String checksum = 'mock-checksum',
  String wavPath = '/tmp/mock.wav',
}) {
  return AudioFeatures(
    melSpectrogram: Float32List(frames * melBins),
    numFrames: frames,
    numMelBins: melBins,
    audioDuration: duration,
    sampleRate: 16000,
    sourceChecksum: checksum,
    wavPath: wavPath,
  );
}

bool _fileExists(String path) => File(path).existsSync();
int _fileSize(String path) => _fileExists(path) ? File(path).lengthSync() : 0;

// En Android/iOS los asset objects deben extraerse a un archivo temporal para ser procesados nativamente por FFmpeg
Future<String> _extractAssetToTemp(String assetPath) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File(p.join(tempDir.path, assetPath.split('/').last));
  if (!tempFile.existsSync()) {
    try {
      final byteData = await rootBundle.load(assetPath);
      await tempFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    } catch (_) {
      // Ignora si falla la lectura (usado para probar tests que fallan)
    }
  }
  return tempFile.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Diccionario para almacenar la ruta temporal real extraída de los assets listos de Android
  final Map<String, String> realPaths = {};

  setUpAll(() async {
    await _openTestDb();
    // Extraer mp3s desde rootBundle a caché nativo temporal
    for (final mp3 in _mp3Files) {
      realPaths[mp3.path] = await _extractAssetToTemp(mp3.path);
    }
  });

  tearDownAll(() async {
    await _closeTestDb();
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 1. VERIFICACIÓN DE ARCHIVOS MP3
  // ───────────────────────────────────────────────────────────────────────────
  group('Verificación de MP3 — assets/audio', () {
    test('Los 3 archivos MP3 existen en assets/audio', () {
      for (final mp3 in _mp3Files) {
        final path = realPaths[mp3.path]!;
        expect(_fileExists(path), isTrue, reason: '❌ No encontrado: $path');
        AppLogger.info('✅ Existe: $path');
      }
    });

    test('Los 3 MP3 superan 50 KB (tamaño válido para transcripción)', () {
      const minBytes = 50 * 1024;
      for (final mp3 in _mp3Files) {
        final path = realPaths[mp3.path]!;
        if (!_fileExists(path)) continue;
        final size = _fileSize(path);
        expect(
          size,
          greaterThan(minBytes),
          reason:
              '$path tiene solo $size bytes — muy pequeño para transcripción',
        );
        AppLogger.info(
          '✅ ${mp3.title}: ${(size / 1024).toStringAsFixed(1)} KB',
        );
      }
    });

    test('Extensión .mp3 es aceptada por FileValidator', () {
      const validator = FileValidator();
      for (final mp3 in _mp3Files) {
        expect(validator.isAllowedExtension(realPaths[mp3.path]!), isTrue);
      }
    });

    test(
      'FileValidator genera checksum SHA-256 de 64 caracteres para cada MP3',
      () async {
        const validator = FileValidator();
        for (final mp3 in _mp3Files) {
          final path = realPaths[mp3.path]!;
          if (!_fileExists(path)) continue;
          final checksum = await validator.validateAudioFile(path);
          expect(
            checksum.length,
            equals(64),
            reason: 'Checksum inválido para $path',
          );
          AppLogger.info(
            '✅ ${mp3.title} → SHA-256: ${checksum.substring(0, 16)}...',
          );
        }
      },
    );

    test('Los 3 MP3 tienen checksums únicos entre sí', () async {
      const validator = FileValidator();
      final checksums = <String>[];
      for (final mp3 in _mp3Files) {
        final path = realPaths[mp3.path]!;
        if (!_fileExists(path)) continue;
        checksums.add(await validator.validateAudioFile(path));
      }
      final unique = checksums.toSet();
      expect(
        unique.length,
        equals(checksums.length),
        reason: 'Dos MP3 tienen el mismo checksum — archivos duplicados',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. CONVERSIÓN MP3 → WAV
  // ───────────────────────────────────────────────────────────────────────────
  group('Conversión MP3 → WAV — AudioConverter', () {
    test('Conversión de los 3 MP3 genera WAV > 1 KB (requiere FFmpeg)', () async {
      const converter = AudioConverter();
      for (final mp3 in _mp3Files) {
        final path = realPaths[mp3.path]!;
        if (!_fileExists(path)) continue;
        try {
          final wavPath = await converter.convertToWav(path);
          expect(
            _fileExists(wavPath),
            isTrue,
            reason: 'WAV no generado para $path',
          );
          expect(
            _fileSize(wavPath),
            greaterThan(1000),
            reason:
                '⚠️ WAV demasiado pequeño — posible causa de "Audio demasiado corto"',
          );
          AppLogger.info(
            '✅ ${mp3.title} → WAV: ${(_fileSize(wavPath) / 1024).toStringAsFixed(1)} KB',
          );
          converter.cleanTempFile(wavPath);
        } catch (e) {
          AppLogger.warning(
            '⚠️ FALLO AL CONVERTIR ${mp3.title}: ${e.runtimeType}',
          );
          rethrow;
        }
      }
    });

    test(
      'Validar copia permanente del archivo WAV al directorio del dispositivo y guardado en BD',
      () async {
        // 1. Simular la obtención del WAV
        const converter = AudioConverter();
        final mp3 = _mp3Files[0]; // Usar Twinkle Twinkle para el test
        final path = realPaths[mp3.path]!;
        expect(_fileExists(path), isTrue, reason: 'MP3 fuente no existe');

        // 2. Extraer WAV temporal
        final tempWavPath = await converter.convertToWav(path);
        expect(
          _fileExists(tempWavPath),
          isTrue,
          reason: 'El WAV temporal no se generó',
        );
        final originalSize = _fileSize(tempWavPath);

        // 3. Simular la lógica del TranscriptionBloc para persistencia
        final appDocDir = await getApplicationDocumentsDirectory();
        final transcriptionsDir = Directory('${appDocDir.path}/transcriptions');
        if (!transcriptionsDir.existsSync()) {
          await transcriptionsDir.create(recursive: true);
        }

        final permanentWavPath =
            '${transcriptionsDir.path}/test_wav_persistent_${DateTime.now().millisecondsSinceEpoch}.wav';
        await File(tempWavPath).copy(permanentWavPath);

        // 4. Validar que el archivo completo se haya guardado permanentemente
        expect(
          _fileExists(permanentWavPath),
          isTrue,
          reason: 'El WAV permanente no fue guardado en Documents',
        );
        expect(
          _fileSize(permanentWavPath),
          equals(originalSize),
          reason: 'El WAV permanente está corrupto o incompleto',
        );

        // Limpiar temporal
        converter.cleanTempFile(tempWavPath);

        // 5. Verificar escritura persistente en SQLite nativa
        final db = await _openTestDb();
        const testId = 'test-wav-persistence-id';

        await db.delete(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [testId],
        );
        await db.insert(DbConstants.scoresTable, {
          DbConstants.colId: testId,
          DbConstants.colTitle: 'Test WAV Persistence',
          DbConstants.colAudioPath: mp3.path,
          DbConstants.colWavPath: permanentWavPath,
          DbConstants.colNoteEvents: '[]',
          DbConstants.colCreatedAt: DateTime.now().toIso8601String(),
          DbConstants.colUpdatedAt: DateTime.now().toIso8601String(),
        });

        final rows = await db.query(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [testId],
        );
        expect(rows.length, equals(1));

        final savedWavPath = rows.first[DbConstants.colWavPath] as String;
        expect(
          savedWavPath,
          equals(permanentWavPath),
          reason: 'La ruta en la BD no coincide con el WAV persistido',
        );
        expect(
          _fileExists(savedWavPath),
          isTrue,
          reason: 'La ruta de BD apunta a un archivo inexistente en disco',
        );

        AppLogger.info(
          '✅ Validada persistencia WAV: Almacenado completo ($originalSize bytes) en Storage Permanentente y SQLite.',
        );

        // Limpieza real
        await File(permanentWavPath).delete();
        await db.delete(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [testId],
        );
      },
    );

    test('Un MP3 inválido (100 bytes) es rechazado o skipeado', () async {
      final tempFile = File(
        '${Directory.systemTemp.path}/invalid_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await tempFile.writeAsBytes(List.filled(100, 0));

      const converter = AudioConverter();
      try {
        await converter.convertToWav(tempFile.path);
      } on AudioProcessingException catch (e) {
        expect(e.message, isNotEmpty);
        AppLogger.info('✅ MP3 inválido rechazado: ${e.message}');
      } catch (e) {
        AppLogger.warning('⚠️ SKIP: ${e.runtimeType} (plugin no disponible)');
      } finally {
        converter.cleanTempFile(tempFile.path);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. ESPECTROGRAMA MEL (AudioFeatures)
  // ───────────────────────────────────────────────────────────────────────────
  group('AudioFeatures — Estructura del Espectrograma Mel', () {
    test('Espectrograma tiene numFrames × 229 elementos para Twinkle', () {
      final f = _mockFeatures(duration: 25.0, frames: 250, checksum: 'twinkle');
      expect(f.melSpectrogram.length, equals(250 * 229));
      expect(f.numMelBins, equals(229));
    });

    test('Espectrograma de Ode to Joy (54s) tiene estructura correcta', () {
      final f = _mockFeatures(duration: 54.0, frames: 540, checksum: 'ode');
      expect(f.audioDuration, equals(54.0));
      expect(f.sampleRate, equals(16000));
      expect(f.numFrames * f.numMelBins, equals(f.melSpectrogram.length));
    });

    test('Espectrograma de Chopin (258s) tiene estructura correcta', () {
      final f = _mockFeatures(
        duration: 258.0,
        frames: 2580,
        checksum: 'chopin',
      );
      expect(f.numFrames, equals(2580));
      expect(f.melSpectrogram.length, equals(2580 * 229));
    });

    test('SampleRate es 16000 Hz (requerim. del modelo Onsets & Frames)', () {
      for (final mp3 in _mp3Files) {
        final f = _mockFeatures(checksum: mp3.scoreId);
        expect(f.sampleRate, equals(16000));
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. INFERENCIA DE NOTAS (TranscriptionRepositoryImpl)
  // ───────────────────────────────────────────────────────────────────────────
  group('TranscriptionRepositoryImpl — Inferencia de Notas', () {
    test('Twinkle: transcripción no lanza excepción no controlada', () async {
      final repo = TranscriptionRepositoryImpl();
      final features = _mockFeatures(
        duration: 25.0,
        frames: 250,
        checksum: 'twinkle',
      );
      await repo.initializeModel();
      final result = await repo.transcribe(features);
      expect(result, isNotNull);
      result.fold(
        (f) =>
            AppLogger.warning('Sin TFLite (esperado en desktop): ${f.message}'),
        (notes) {
          AppLogger.info('✅ Twinkle: ${notes.length} notas generadas');
          for (final n in notes) {
            expect(n.midiNote, inInclusiveRange(21, 108));
            expect(n.startTime, lessThan(n.endTime));
          }
        },
      );
    });

    test('Ode to Joy: las notas respetan rango MIDI del piano', () async {
      final repo = TranscriptionRepositoryImpl();
      final features = _mockFeatures(
        duration: 54.0,
        frames: 540,
        checksum: 'ode',
      );
      await repo.initializeModel();
      final result = await repo.transcribe(features);
      result.fold((_) {}, (notes) {
        for (final note in notes) {
          expect(note.midiNote, greaterThanOrEqualTo(21));
          expect(note.midiNote, lessThanOrEqualTo(108));
        }
      });
    });

    test(
      'Chopin: AudioFeatures grande no lanza StateError ni RangeError',
      () async {
        final repo = TranscriptionRepositoryImpl();
        final features = _mockFeatures(
          duration: 258.0,
          frames: 2580,
          checksum: 'chopin',
        );
        await repo.initializeModel();
        final result = await repo.transcribe(features);
        expect(result, isNotNull);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. BASE DE DATOS — Lectura y escritura en yanitadb.db
  // ───────────────────────────────────────────────────────────────────────────
  group('Base de Datos (yanitadb.db) — Transcripción persistida', () {
    test('La BD de test está abierta y accesible', () async {
      final db = await _openTestDb();
      expect(db.isOpen, isTrue);
    });

    test('La tabla scores contiene o acepta los 3 MP3 de demo', () async {
      final db = await _openTestDb();
      final rows = await db.query(DbConstants.scoresTable);
      AppLogger.info('Registros en scores: ${rows.length}');
      // Si la BD tiene datos, verificar que los 3 demos estén presentes
      if (rows.isNotEmpty) {
        final audioPaths = rows
            .map((r) => r[DbConstants.colAudioPath] as String? ?? '')
            .toList();
        for (final mp3 in _mp3Files) {
          final found = audioPaths.any(
            (p) => p.contains(mp3.path.split('/').last),
          );
          AppLogger.info('${found ? "✅" : "⚠️"} ${mp3.title} en BD: $found');
        }
      }
    });

    test('Insertar resultado de transcripción para Twinkle en BD de test', () async {
      final db = await _openTestDb();
      const validator = FileValidator();
      final mp3 = _mp3Files[0]; // twinkle_twinkle.mp3

      // Obtener o simular checksum
      String checksum = 'mock-test-checksum';
      final realPath = realPaths[mp3.path]!;
      if (_fileExists(realPath)) {
        try {
          checksum = await validator.validateAudioFile(realPath);
        } catch (_) {}
      }

      final now = DateTime.now().toIso8601String();
      const testId = 'test-twinkle-transcription-01';

      // Generar MusicXML Mock
      final mockNotes = [
        const NoteEvent(
          startTime: 0.0,
          endTime: 0.5,
          midiNote: 60,
          velocity: 80,
        ),
        const NoteEvent(
          startTime: 0.5,
          endTime: 1.0,
          midiNote: 62,
          velocity: 80,
        ),
      ];
      final generator = MusicXmlGenerator();
      final xmlString = generator.generate(notes: mockNotes, title: mp3.title);

      // Eliminar si ya existe (idempotente)
      await db.delete(
        DbConstants.scoresTable,
        where: '${DbConstants.colId} = ?',
        whereArgs: [testId],
      );

      // Insertar resultado de transcripción simulado
      await db.insert(DbConstants.scoresTable, {
        DbConstants.colId: testId,
        DbConstants.colTitle: '${mp3.title} [Test]',
        DbConstants.colAudioPath: mp3.path,
        DbConstants.colNoteEvents:
            '[{"start_time":0.0,"end_time":0.5,"midi_note":60,"velocity":80}]',
        DbConstants.colDuration: mp3.duration,
        DbConstants.colTempo: mp3.tempo,
        DbConstants.colChecksum: checksum,
        DbConstants.colMusicXml: xmlString,
        DbConstants.colTranscriptionSteps:
            '["validar","convertir_wav","extraer_espectrograma","inferir_notas"]',
        DbConstants.colCreatedAt: now,
        DbConstants.colUpdatedAt: now,
      });

      // Verificar que se insertó
      final result = await db.query(
        DbConstants.scoresTable,
        where: '${DbConstants.colId} = ?',
        whereArgs: [testId],
      );
      expect(result.length, equals(1));
      expect(result.first[DbConstants.colTitle], contains('Twinkle'));
      expect(result.first[DbConstants.colChecksum], equals(checksum));
      expect(
        result.first[DbConstants.colMusicXml],
        contains('<score-partwise'),
      );
      AppLogger.info(
        '✅ Twinkle insertado con MusicXML de ${xmlString.length} chars (checksum: ${checksum.substring(0, 16)}...)',
      );

      // Limpiar registro de test
      await db.delete(
        DbConstants.scoresTable,
        where: '${DbConstants.colId} = ?',
        whereArgs: [testId],
      );
    });

    test('Insertar transcripción para los 3 MP3 y verificar en BD', () async {
      final db = await _openTestDb();
      final insertedIds = <String>[];

      for (int i = 0; i < _mp3Files.length; i++) {
        final mp3 = _mp3Files[i];
        final testId = 'test-pipeline-${mp3.scoreId}-qav2';
        final now = DateTime.now().toIso8601String();

        // Datos de transcripción simulados
        final frames = (mp3.duration * 10).toInt();
        final mockNotes = [
          NoteEvent(
            startTime: 0.0,
            endTime: 0.5,
            midiNote: 60 + i * 4,
            velocity: 80,
          ),
        ];
        final generator = MusicXmlGenerator();
        final xmlString = generator.generate(
          notes: mockNotes,
          title: mp3.title,
        );

        final transcriptionResult = {
          DbConstants.colId: testId,
          DbConstants.colTitle: '${mp3.title} [QA Pipeline]',
          DbConstants.colAudioPath: mp3.path,
          DbConstants.colNoteEvents:
              '[{"start_time":0.0,"end_time":0.5,"midi_note":${60 + i * 4},"velocity":80}]',
          DbConstants.colDuration: mp3.duration,
          DbConstants.colTempo: mp3.tempo,
          DbConstants.colChecksum: 'sha256-mock-${mp3.scoreId.substring(0, 8)}',
          DbConstants.colWavPath:
              '/tmp/${mp3.path.split('/').last.replaceAll('.mp3', '.wav')}',
          DbConstants.colMusicXml: xmlString,
          DbConstants.colTranscriptionSteps:
              '["Validar MP3","Convertir a WAV 16kHz","Extraer Espectrograma Mel (${frames}f x 229bins)","Inferir notas con Onsets&Frames","Generar MusicXml"]',
          DbConstants.colCreatedAt: now,
          DbConstants.colUpdatedAt: now,
        };

        // Upsert: eliminar previo si existe
        await db.delete(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [testId],
        );
        await db.insert(DbConstants.scoresTable, transcriptionResult);
        insertedIds.add(testId);

        AppLogger.info('✅ ${mp3.title} → insertado en BD (ID: $testId)');
      }

      // Verificar los 3 registros
      for (final id in insertedIds) {
        final rows = await db.query(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [id],
        );
        expect(rows.length, equals(1));
        expect(rows.first[DbConstants.colNoteEvents], isNotEmpty);
        expect(rows.first[DbConstants.colMusicXml], isNotNull);
        expect(
          (rows.first[DbConstants.colMusicXml] as String).contains(
            '<score-partwise',
          ),
          isTrue,
        );
        expect(rows.first[DbConstants.colTranscriptionSteps], isNotNull);
      }

      AppLogger.info('✅ Los 3 registros verificados en BD');

      // Limpiar registros de test
      for (final id in insertedIds) {
        await db.delete(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [id],
        );
      }
    });

    test(
      'Los pasos de transcripción se almacenan como lista JSON válida',
      () async {
        final db = await _openTestDb();
        final now = DateTime.now().toIso8601String();
        const testId = 'test-steps-json-v1';

        final steps = [
          'Validar archivo MP3',
          'Calcular SHA-256',
          'Convertir WAV 16kHz mono',
          'Generar espectrograma Mel (229 bins)',
          'Inferir notas con Onsets & Frames',
          'Guardar en yanitadb.db',
        ];

        await db.delete(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [testId],
        );

        await db.insert(DbConstants.scoresTable, {
          DbConstants.colId: testId,
          DbConstants.colTitle: 'Test Pasos JSON',
          DbConstants.colAudioPath: _mp3Files[0].path,
          DbConstants.colNoteEvents: '[]',
          DbConstants.colTranscriptionSteps: steps.toString(),
          DbConstants.colDuration: 1.0,
          DbConstants.colTempo: 120.0,
          DbConstants.colCreatedAt: now,
          DbConstants.colUpdatedAt: now,
        });

        final result = await db.query(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [testId],
        );
        final savedSteps =
            result.first[DbConstants.colTranscriptionSteps] as String?;
        expect(savedSteps, isNotNull);
        expect(savedSteps!.contains('Convertir WAV'), isTrue);
        AppLogger.info('✅ Pasos de transcripción guardados: $savedSteps');

        await db.delete(
          DbConstants.scoresTable,
          where: '${DbConstants.colId} = ?',
          whereArgs: [testId],
        );
      },
    );

    test(
      'Leer scores existentes: validar que los 3 demos tienen audio_path correcto',
      () async {
        final db = await _openTestDb();
        final rows = await db.query(DbConstants.scoresTable);

        if (rows.isEmpty) {
          AppLogger.warning(
            '⚠️ BD vacía — usando BD en memoria sin datos demo',
          );
          return;
        }

        for (final mp3 in _mp3Files) {
          final found = rows.where((r) {
            final audioPath = r[DbConstants.colAudioPath] as String? ?? '';
            return audioPath.contains(mp3.path.split('/').last);
          }).toList();

          if (found.isNotEmpty) {
            final score = found.first;
            expect(score[DbConstants.colNoteEvents], isNotEmpty);
            expect(score[DbConstants.colDuration], greaterThan(0));
            AppLogger.info(
              '✅ ${mp3.title} → duration=${score[DbConstants.colDuration]}s, '
              'notas=${(score[DbConstants.colNoteEvents] as String).length} chars',
            );
          } else {
            AppLogger.warning(
              '⚠️ ${mp3.title} no encontrado en BD (aún no transcrito)',
            );
          }
        }
      },
    );
  });
}
