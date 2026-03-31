import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yanita_music/domain/entities/score.dart';
import 'package:yanita_music/presentation/widgets/score_stave_visualizer.dart';
import 'package:yanita_music/core/utils/logger.dart';
import 'package:yanita_music/core/constants/db_constants.dart';
import 'package:yanita_music/data/datasources/local/database_helper.dart';




/// Página de detalle de una partitura transcrita con controles de reproducción.
class ScoreDetailPage extends StatefulWidget {
  final Score score;

  const ScoreDetailPage({super.key, required this.score});

  @override
  State<ScoreDetailPage> createState() => _ScoreDetailPageState();
}

class _ScoreDetailPageState extends State<ScoreDetailPage> with SingleTickerProviderStateMixin {
  late AudioPlayer _audioPlayer;
  late Ticker _ticker160fps;
  bool _isPlaying = false;
  bool _isLoading = false;
  double _currentTime = 0.0;
  double _staffScale = 1.0;

  // Throttle a 160 FPS: intervalo mínimo entre frames (~6.25 ms)
  static const int _frameIntervalMs = 1000 ~/ 160;
  int _lastFrameMs = 0;


  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    // Ticker a 160 FPS: lee la posición real del audio en cada frame
    _ticker160fps = createTicker((_) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastFrameMs < _frameIntervalMs) return;
      _lastFrameMs = nowMs;
      if (_isPlaying && mounted) {
        final pos = _audioPlayer.position.inMilliseconds / 1000.0;
        if (pos != _currentTime) {
          setState(() => _currentTime = pos);
        }
      }
    });
    _ticker160fps.start();

    _initAudio();
  }

  Future<void> _initAudio() async {
    if (widget.score.audioPath.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // Configurar sesión de audio para Android
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      AppLogger.info('Inicializando audio: ${widget.score.audioPath}', tag: 'ScoreDetailPage');

      
      // Verificar que el archivo realmente existe
      bool fileExists = false;
      if (widget.score.audioPath.startsWith('assets/')) {
        // Para assets no podemos usar File().existsSync() directamente,
        // pero confiamos en que si está en la semilla está en pubspec.
        fileExists = true;
      } else if (widget.score.audioPath.startsWith('http')) {
        fileExists = true;
      } else {
        fileExists = File(widget.score.audioPath).existsSync();
      }

      if (!fileExists) {
        throw Exception('El archivo de audio no existe: ${widget.score.audioPath}');
      }

      if (widget.score.audioPath.startsWith('http')) {
        await _audioPlayer.setUrl(widget.score.audioPath);
      } else if (widget.score.audioPath.startsWith('assets/')) {
        // En Android/Release, setAsset es el método correcto para archivos en assets/
        await _audioPlayer.setAsset(widget.score.audioPath);
      } else {
        await _audioPlayer.setFilePath(widget.score.audioPath);
      }

      _audioPlayer.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _audioPlayer.seek(Duration.zero);
            _audioPlayer.pause();
            setState(() => _currentTime = 0.0);
          }
        });
      });
      // positionStream: solo para seek externo (p.ej. drag del slider)
      _audioPlayer.positionStream.listen((position) {
        if (mounted && !_isPlaying) {
          setState(() => _currentTime = position.inMilliseconds / 1000.0);
        }
      });
      
      // Pre-cargar para obtener duración real si es posible
      final duration = await _audioPlayer.load();
      if (duration != null) {
        AppLogger.info('Audio cargado. Duración: ${duration.inSeconds}s', tag: 'ScoreDetailPage');
      }

    } catch (e, stack) {
      AppLogger.error('Error inicializando audio', tag: 'ScoreDetailPage', error: e, stackTrace: stack);
      if (mounted) {
        String errorMsg = e.toString().split('\n').first;
        if (errorMsg.contains('Exception:')) {
          errorMsg = errorMsg.replaceAll('Exception:', '').trim();
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Error de audio: $errorMsg')),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'REINTENTAR',
              textColor: Colors.white,
              onPressed: _initAudio,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _ticker160fps.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }


  void _showDiagnostics() async {
    final logs = await DatabaseHelper().getLogs(limit: 50);
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logs de Sistema'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: logs.isEmpty 
            ? const Center(child: Text('No hay logs registrados.'))
            : ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, i) {
                  final log = logs[i];
                  final level = log[DbConstants.colLogLevel] ?? 'INFO';
                  final color = level == 'error' ? Colors.red : (level == 'warning' ? Colors.orange : Colors.blue);
                  
                  return ListTile(
                    leading: Icon(Icons.circle, color: color, size: 12),
                    title: Text(log[DbConstants.colLogMessage] ?? '', style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${log[DbConstants.colLogTag]} | ${log[DbConstants.colLogCreatedAt]}', 
                      style: const TextStyle(fontSize: 11)),
                    isThreeLine: false,
                  );
                },
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _togglePlayback() {

    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.score.title, style: GoogleFonts.inter(fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Ver Logs de Sistema',
            onPressed: _showDiagnostics,
          ),

          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Visualización de Notas (Pentagrama)
            ScoreStaveVisualizer(
              score: widget.score,
              currentTime: _currentTime,
              isPlaying: _isPlaying,
              staffScale: _staffScale,
            ),

            const SizedBox(height: 24),

            // Controles de Reproducción
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _isLoading
                            ? const SizedBox(
                                width: 48,
                                height: 48,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  _isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: _togglePlayback,
                              ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  activeTrackColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  inactiveTrackColor: Colors.white10,
                                ),
                                child: Slider(
                                  value: (_currentTime / widget.score.duration)
                                      .clamp(0.0, 1.0),
                                  onChanged: (value) {
                                    final position = Duration(
                                      milliseconds:
                                          (value * widget.score.duration * 1000)
                                              .toInt(),
                                    );
                                    _audioPlayer.seek(position);
                                    setState(() {
                                      _currentTime = value * widget.score.duration;
                                    });
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatTime(_currentTime),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white54,
                                      ),
                                    ),
                                    Text(
                                      _formatTime(widget.score.duration),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Control de Zoom del Pentagrama
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildSlider(
                  label: 'Tamaño del Pentagrama',
                  icon: Icons.zoom_in,
                  value: _staffScale,
                  min: 0.5,
                  max: 2.0,
                  onChanged: (val) => setState(() => _staffScale = val),
                  secondaryLabel: '${(_staffScale * 100).toInt()}%',
                ),
              ),
            ),
            const SizedBox(height: 16),


            // Información general con iconos para mayor "uniformidad"
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Detalles de la Transcripción',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    _buildDetailRow(
                      context,
                      Icons.music_note,
                      'Notas detectadas',
                      '${widget.score.noteCount}',
                    ),
                    _buildDetailRow(
                      context,
                      Icons.speed,
                      'Tempo',
                      widget.score.tempo != null
                          ? '${widget.score.tempo!.toStringAsFixed(0)} BPM'
                          : 'No detectado',
                    ),
                    _buildDetailRow(
                      context,
                      Icons.layers,
                      'Tipo',
                      widget.score.isPolyphonic ? 'Polifónica' : 'Monofónica',
                    ),
                    _buildDetailRow(
                      context,
                      Icons.calendar_today,
                      'Fecha',
                      _formatDate(widget.score.createdAt),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white70)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(double seconds) {
    final int minutes = (seconds / 60).floor();
    final int remainingSeconds = (seconds % 60).floor();
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildSlider({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required String secondaryLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(
                secondaryLabel,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

