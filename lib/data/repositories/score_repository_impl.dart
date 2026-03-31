import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yanita_music/core/error/exceptions.dart';
import 'package:yanita_music/core/error/failures.dart';
import 'package:yanita_music/core/utils/midi_utils.dart';
import 'package:yanita_music/core/utils/music_xml_generator.dart';
import 'package:yanita_music/data/datasources/local/score_local_datasource.dart';
import 'package:yanita_music/data/models/score_model.dart';
import 'package:yanita_music/domain/entities/score.dart';
import 'package:yanita_music/domain/repositories/score_repository.dart';

class ScoreRepositoryImpl implements ScoreRepository {
  final ScoreLocalDataSource _localDataSource;
  final MidiUtils _midiUtils;
  final MusicXmlGenerator _musicXmlGenerator;

  ScoreRepositoryImpl({
    required ScoreLocalDataSource localDataSource,
    required MidiUtils midiUtils,
    required MusicXmlGenerator musicXmlGenerator,
  }) : _localDataSource = localDataSource,
       _midiUtils = midiUtils,
       _musicXmlGenerator = musicXmlGenerator;

  @override
  Future<Either<Failure, Score>> saveScore(Score score) async {
    try {
      final model = ScoreModel.fromEntity(score);
      final result = await _localDataSource.insertScore(model);
      return Right(result);
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, List<Score>>> getAllScores() async {
    try {
      final scores = await _localDataSource.getAllScores();
      return Right(scores);
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Score>> getScoreById(String id) async {
    try {
      final score = await _localDataSource.getScoreById(id);
      return Right(score);
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> deleteScore(String id) async {
    try {
      await _localDataSource.deleteScore(id);
      return const Right(null);
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Score>> updateScore(Score score) async {
    try {
      final model = ScoreModel.fromEntity(score);
      final result = await _localDataSource.updateScore(model);
      return Right(result);
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, String>> exportMidi(String scoreId) async {
    try {
      final score = await _localDataSource.getScoreById(scoreId);
      final midiPath = await _midiUtils.generateMidiFile(
        score.noteEvents,
        score.tempo ?? 120.0,
      );
      return Right(midiPath);
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message));
    } on Exception catch (e) {
      return Left(ExportFailure(message: 'Error exportando MIDI: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> exportMusicXml(String scoreId) async {
    try {
      final score = await _localDataSource.getScoreById(scoreId);
      
      // [v53-FIX]: Generar ruta de archivo real en lugar de devolver el XML crudo
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = p.join(directory.path, 'exports', 'score_$timestamp.mxl');
      
      // Asegurar que el directorio existe
      final exportDir = Directory(p.dirname(filePath));
      if (!exportDir.existsSync()) {
        exportDir.createSync(recursive: true);
      }

      final xmlPath = await _musicXmlGenerator.generateAndSave(
        notes: score.noteEvents,
        title: score.title,
        outputPath: filePath,
      );
      
      return Right(xmlPath);
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message));
    } on Exception catch (e) {
      return Left(ExportFailure(message: 'Error exportando MusicXML: $e'));
    }
  }
}
