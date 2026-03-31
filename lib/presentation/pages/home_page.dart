import 'dart:io';
import 'package:yanita_music/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yanita_music/domain/entities/score.dart';
import 'package:yanita_music/presentation/blocs/score_library/score_library_bloc.dart';
import 'package:yanita_music/presentation/blocs/transcription/transcription_bloc.dart';
import 'package:yanita_music/presentation/pages/transcription_page.dart';
import 'package:yanita_music/presentation/pages/score_library_page.dart';
import 'package:yanita_music/presentation/pages/songbook_page.dart';
import 'package:yanita_music/presentation/pages/login_page.dart';
import 'package:yanita_music/presentation/widgets/score_stave_visualizer.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:yanita_music/core/utils/logger.dart';
import 'package:yanita_music/presentation/pages/log_viewer_page.dart';
import 'package:yanita_music/presentation/pages/database_viewer_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const _DashboardView(),
    const TranscriptionPage(),
    const ScoreLibraryPage(),
    const SongbookPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF121212),
        selectedItemColor: const Color(0xFFFF9800),
        unselectedItemColor: const Color(0xFF666666),
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.piano),
            label: 'Transcribir',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Biblioteca',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Cancionero'),
        ],
      ),
    );
  }
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView>
    with SingleTickerProviderStateMixin {
  Score? _selectedScore;
  bool _isPlaying = false;
  bool _isAudioLoading = false;
  double _currentTime = 0.0;
  double _lastReportedPos = 0.0;
  DateTime _lastReportedTime = DateTime.now();
  late AnimationController _playbackController;
  late AudioPlayer _audioPlayer;
  late Ticker _ticker160fps;

  @override
  void initState() {
    super.initState();
    _playbackController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() {
            setState(() {});
          });

    _audioPlayer = AudioPlayer();

    _audioPlayer.positionStream.listen((position) {
      if (_selectedScore != null && _selectedScore!.duration > 0 && mounted) {
        final double progress =
            position.inMilliseconds / (_selectedScore!.duration * 1000);
        if (!_isPlaying) {
          setState(() {
            _playbackController.value = progress.clamp(0.0, 1.0);
            _currentTime = position.inMilliseconds / 1000.0;
          });
        } else {
          _playbackController.value = progress.clamp(0.0, 1.0);
        }
      }
    });

    _ticker160fps = createTicker((_) {
      final now = DateTime.now();
      if (_isPlaying && _selectedScore != null && mounted) {
        final double platformPos =
            _audioPlayer.position.inMilliseconds / 1000.0;

        if (platformPos != _lastReportedPos) {
          _lastReportedPos = platformPos;
          _lastReportedTime = now;
        }

        final double elapsedSinceReport =
            now.difference(_lastReportedTime).inMilliseconds / 1000.0;
        final double interpolatedPos = _lastReportedPos + elapsedSinceReport;

        if ((interpolatedPos - _currentTime).abs() > 0.005) {
          setState(() {
            _currentTime = interpolatedPos;
          });
        }
      } else if (!_isPlaying && _selectedScore != null && mounted) {
        final double platformPos =
            _audioPlayer.position.inMilliseconds / 1000.0;
        if (platformPos != _currentTime) {
          setState(() => _currentTime = platformPos);
        }
      }
    });
    _ticker160fps.start();

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
          _playbackController.stop();
          _playbackController.value = 1.0;
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.pause();
        });
      }
    });

    context.read<ScoreLibraryBloc>().add(LoadScores());
  }

  @override
  void dispose() {
    _playbackController.dispose();
    _ticker160fps.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadScore(Score score) async {
    _stopPlayback();
    setState(() {
      _selectedScore = score;
      _isAudioLoading = true;
    });

    try {
      String audioPathToLoad = score.audioPath;
      if (score.wavPath != null && score.wavPath!.isNotEmpty) {
        final wavFile = File(score.wavPath!);
        if (wavFile.existsSync()) {
          audioPathToLoad = score.wavPath!;
          AppLogger.info(
            'Cargando WAV interno: $audioPathToLoad',
            tag: 'HomePage',
          );
        }
      }

      if (audioPathToLoad.isNotEmpty) {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());

        if (audioPathToLoad.startsWith('http')) {
          await _audioPlayer.setUrl(audioPathToLoad);
        } else if (audioPathToLoad.startsWith('assets/')) {
          try {
            await _audioPlayer.setAsset(audioPathToLoad);
          } catch (e) {
            await _audioPlayer.setAudioSource(
              AudioSource.uri(Uri.parse('asset:///$audioPathToLoad')),
            );
          }
        } else {
          await _audioPlayer.setFilePath(audioPathToLoad);
        }
        await _audioPlayer.load();
      }

      if (mounted) {
        setState(() {
          _isAudioLoading = false;
          _playbackController.duration = Duration(
            milliseconds: (score.duration * 1000).toInt(),
          );
          _currentTime = 0.0;
          _isPlaying = true;
        });
        _audioPlayer.play();
      }
    } catch (e) {
      AppLogger.error('Error loading audio: $e', tag: 'HomePage');
      if (mounted) {
        setState(() {
          _isAudioLoading = false;
          _isPlaying = false;
        });
      }
    }
  }

  void _togglePlayback() {
    if (_selectedScore == null || _isAudioLoading) return;
    setState(() {
      if (_isPlaying) {
        _audioPlayer.pause();
        _playbackController.stop();
      } else {
        if (_playbackController.isCompleted) {
          _playbackController.reset();
          _audioPlayer.seek(Duration.zero);
        }
        _audioPlayer.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  void _stopPlayback() {
    setState(() {
      _isPlaying = false;
      _audioPlayer.pause();
      _audioPlayer.seek(Duration.zero);
      _playbackController.stop();
      _playbackController.value = 0.0;
      _currentTime = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TranscriptionBloc, TranscriptionState>(
      listener: (context, state) {
        if (state is TranscriptionSaved) {
          context.read<ScoreLibraryBloc>().add(LoadScores());
          _stopPlayback();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFFF8F9FA),
          ),
          title: Column(
            children: [
              Text(
                'REPRODUCIENDO PARTITURA',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: const Color(0xFFCCCCCC),
                ),
              ),
              Text(
                _selectedScore?.title ?? 'Selecciona una partitura',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.storage, color: Colors.blueAccent),
              tooltip: 'Monitor de Datos',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DatabaseViewerPage()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bug_report, color: Colors.redAccent),
              tooltip: 'Visor de Logs',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogViewerPage()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Color(0xFFFF9800)),
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
              tooltip: 'Cerrar Sesión',
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: _selectedScore != null
                      ? ScoreStaveVisualizer(
                          score: _selectedScore!,
                          currentTime: _currentTime,
                          isPlaying: _isPlaying,
                        )
                      : Container(
                          height: 320,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: const DecorationImage(
                              image: AssetImage('assets/images/logo.png'),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 32),
                if (_selectedScore != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedScore!.title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'Piano - Transcripción Automática',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.favorite_border,
                        color: Color(0xFFFF9800),
                        size: 28,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          activeTrackColor: const Color(0xFFFF9800),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: _playbackController.value.clamp(0.0, 1.0),
                          onChanged: (value) {
                            final seekMs =
                                (value * (_selectedScore?.duration ?? 0) * 1000)
                                    .toInt();
                            _audioPlayer.seek(Duration(milliseconds: seekMs));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'BUILD v${AppConstants.appVersion}+${AppConstants.buildNumber} - MODO TELEMETRÍA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              _formatTime(_selectedScore?.duration ?? 0),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.stop,
                          color: Color(0xFFE65100),
                          size: 32,
                        ),
                        onPressed: _stopPlayback,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.skip_previous,
                          color: Colors.white,
                          size: 42,
                        ),
                        onPressed: () => _audioPlayer.seek(Duration.zero),
                      ),
                      GestureDetector(
                        onTap: _togglePlayback,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: _isAudioLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF121212),
                                    strokeWidth: 3,
                                  ),
                                )
                              : Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: const Color(0xFF121212),
                                  size: 40,
                                ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.skip_next,
                          color: Colors.white,
                          size: 42,
                        ),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.repeat,
                          color: Color(0xFFFF9800),
                          size: 24,
                        ),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 48),
                Text(
                  'Tus Últimas Partituras',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                BlocBuilder<ScoreLibraryBloc, ScoreLibraryState>(
                  builder: (context, state) {
                    if (state is ScoreLibraryLoaded) {
                      final recentScores = state.scores.take(5).toList();
                      if (recentScores.isEmpty) {
                        return const Text(
                          'Aún no tienes partituras.',
                          style: TextStyle(color: Colors.white54),
                        );
                      }
                      return Column(
                        children: recentScores
                            .map((score) => _buildScoreItem(score))
                            .toList(),
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreItem(Score score) {
    final bool isSelected = _selectedScore?.id == score.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white12 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.piano, color: Color(0xFFFF9800)),
        ),
        title: Text(
          score.title,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFF9800) : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: const Text(
          'Piano - Transcripción Automática',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        onTap: () => _loadScore(score),
      ),
    );
  }

  String _formatTime(double seconds) {
    final int minutes = (seconds / 60).floor();
    final int remainingSeconds = (seconds % 60).floor();
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
