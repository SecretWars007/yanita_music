import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:yanita_music/core/error/failures.dart';
import 'package:yanita_music/core/usecases/usecase.dart';
import 'package:yanita_music/domain/entities/score.dart';
import 'package:yanita_music/domain/repositories/score_repository.dart';

/// Caso de uso: Actualizar una partitura existente en SQLite (ej. progreso de transcripción).
class UpdateScoreUseCase extends UseCase<Score, UpdateScoreParams> {
  final ScoreRepository _scoreRepository;

  UpdateScoreUseCase({required ScoreRepository scoreRepository})
    : _scoreRepository = scoreRepository;

  @override
  Future<Either<Failure, Score>> call(UpdateScoreParams params) async {
    return await _scoreRepository.updateScore(params.score);
  }
}

class UpdateScoreParams extends Equatable {
  final Score score;

  const UpdateScoreParams({required this.score});

  @override
  List<Object?> get props => [score];
}
