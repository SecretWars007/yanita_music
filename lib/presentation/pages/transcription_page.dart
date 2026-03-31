import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yanita_music/presentation/blocs/transcription/transcription_bloc.dart';
import 'package:yanita_music/presentation/blocs/songbook/songbook_bloc.dart';
import 'package:yanita_music/presentation/blocs/score_library/score_library_bloc.dart';
import 'package:yanita_music/presentation/pages/log_viewer_page.dart';
import 'package:yanita_music/presentation/pages/database_viewer_page.dart';
import 'package:yanita_music/core/utils/logger.dart';
import 'package:yanita_music/domain/entities/note_event.dart';
import 'package:uuid/uuid.dart';
import 'package:yanita_music/domain/entities/song.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

/// Página de transcripción musical.
///
/// Permite al usuario:
/// 1. Subir un archivo MP3 de piano
/// 2. Ver el progreso del pipeline DSP + TFLite
/// 3. Guardar la partitura resultante
///
/// Incluye alerta informativa de que solo se soporta piano,
/// no voces ni otros instrumentos.
class TranscriptionPage extends StatelessWidget {
  const TranscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcripción Musical'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showPianoOnlyAlert(context),
          ),
        ],
      ),
      body: BlocConsumer<TranscriptionBloc, TranscriptionState>(
        listener: (context, state) {
          if (state is TranscriptionSaved) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Partitura "${state.title}" guardada exitosamente',
                ),
                backgroundColor: Colors.green.shade700,
              ),
            );
            // Auto-agregar al cancionero
            final newSong = Song(
              id: const Uuid().v4(),
              title: state.title,
              artist: 'Transcripción',
              scoreId: state.scoreId,
              category: 'Piano',
              createdAt: DateTime.now(),
            );
            context.read<SongbookBloc>().add(AddSongEvent(song: newSong));

            // Refrescar la biblioteca de partituras (el cancionero se auto-refresca post addSong)
            context.read<ScoreLibraryBloc>().add(LoadScores());
            context.read<TranscriptionBloc>().add(ResetTranscription());
            // Ir a la pestaña de Biblioteca (índice 2) si se desea,
            // o simplemente mostrar el mensaje.
            // Navigator.of(context).pop(); // Eliminado para tabs
          }
          if (state is TranscriptionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Alerta informativa
                _buildInfoBanner(context),
                const SizedBox(height: 24),

                // Área de upload
                if (state is TranscriptionInitial) _buildUploadCard(context),

                if (state is TranscriptionError)
                  _buildErrorCard(context, state, state.steps),

                if (state is AudioFileSelected)
                  _buildFileSelectedCard(context, state),

                if (state is AudioProcessing)
                  _buildProcessingCard(context, state, state.steps),

                if (state is Transcribing)
                  _buildProcessingCard(context, state, state.steps),

                if (state is SavingTranscription)
                  _buildSavingCard(context, state),

                if (state is TranscriptionSuccess)
                  _buildSuccessCard(context, state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.piano, color: Colors.amber.shade300, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Solo se puede transcribir música de piano. '
              'Voces y otros instrumentos no son soportados.',
              style: TextStyle(color: Colors.amber.shade100, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () =>
            context.read<TranscriptionBloc>().add(const SelectAudioFile()),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 220,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 64,
                color: Color(0xFFFF9800),
              ),
              const SizedBox(height: 16),
              Text(
                'Seleccionar archivo de audio',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Formatos soportados: MP3, WAV, M4A, FLAC',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Tamaño máximo: 50 MB',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: Color(0xFFFF9800),
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'TIP: Si no ves tus archivos, usa el menú lateral en "Recientes".',
                      style: TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileSelectedCard(BuildContext context, AudioFileSelected state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.audio_file,
              size: 48,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 12),
            Text(
              state.fileName,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.read<TranscriptionBloc>().add(
                    ResetTranscription(),
                  ),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: () => context.read<TranscriptionBloc>().add(
                    StartTranscription(filePath: state.filePath),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Transcribir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingCard(
    BuildContext context,
    TranscriptionState state,
    List<TranscriptionStep> steps,
  ) {
    String title = 'Procesando...';
    String fileName = '';
    String? detail;

    if (state is AudioProcessing) {
      title = state.statusMessage;
      fileName = state.fileName;
      detail = state.detailMessage;
    } else if (state is Transcribing) {
      title = state.statusMessage;
      fileName = state.fileName;
      detail = state.detailMessage;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFF9800),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        fileName,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildStepsList(context, steps),
            if (detail != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  detail,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepsList(BuildContext context, List<TranscriptionStep> steps) {
    return Column(
      children: steps.map((step) => _buildStepRow(context, step)).toList(),
    );
  }

  Widget _buildStepRow(BuildContext context, TranscriptionStep step) {
    IconData icon;
    Color color;
    Widget trailing = const SizedBox.shrink();

    switch (step.status) {
      case TranscriptionStepStatus.pending:
        icon = Icons.radio_button_unchecked;
        color = Colors.white24;
        break;
      case TranscriptionStepStatus.processing:
        icon = Icons.sync;
        color = const Color(0xFFFF9800);
        trailing = const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFFFF9800),
          ),
        );
        break;
      case TranscriptionStepStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green.shade400;
        break;
      case TranscriptionStepStatus.error:
        icon = Icons.error;
        color = Colors.red.shade400;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              step.title,
              style: TextStyle(
                color: step.status == TranscriptionStepStatus.pending
                    ? Colors.white38
                    : Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildSavingCard(BuildContext context, SavingTranscription state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFFF9800),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Guardando "${state.title}"...',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Almacenando en la base de datos local',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard(BuildContext context, TranscriptionSuccess state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.check_circle, size: 48, color: Colors.green.shade400),
            const SizedBox(height: 16),
            Text(
              '¡Transcripción completada!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            _buildMetricRow('Notas detectadas', '${state.noteCount}'),
            _buildMetricRow(
              'Duración',
              '${state.duration.toStringAsFixed(1)}s',
            ),
            _buildMetricRow(
              'Tipo',
              state.isPolyphonic ? 'Polifónica' : 'Monofónica',
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),
            _buildInfoRow('Archivo WAV Persistido', state.filePath),
            if (state.pdfPath != null)
              _buildInfoRow('Informe PDF Generado', state.pdfPath!),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 12,
              runSpacing: 12,
              children: [
                _WavAudioPlayerButton(
                  audioPath: state.filePath,
                  isStyleOutlined: false,
                ),
                if (state.pdfPath != null && state.pdfPath!.isNotEmpty)
                  _buildActionButton(
                    icon: Icons.picture_as_pdf,
                    label: 'Exportar PDF',
                    onPressed: () async {
                      final file = File(state.pdfPath!);
                      if (file.existsSync()) {
                        await Share.shareXFiles([XFile(state.pdfPath!)], text: 'Espectrograma Yanita Music');
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('El archivo PDF no existe aún'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    color: Colors.blueAccent,
                  ),
                _buildActionButton(
                  icon: Icons.music_note,
                  label: 'Exportar MIDI',
                  onPressed: () async {
                    try {
                      final dir = await getTemporaryDirectory();
                      final midiPath = '${dir.path}/transcription_export.mid';
                      final file = File(midiPath);
                      // Generar un archivo MIDI básico (header + track)
                      final midiBytes = _generateBasicMidiBytes(state.noteEvents, state.duration);
                      await file.writeAsBytes(midiBytes);
                      await Share.shareXFiles([XFile(midiPath)], text: 'MIDI - Yanita Music');
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error exportando MIDI: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  color: Colors.purpleAccent,
                ),
                _buildActionButton(
                  icon: Icons.description,
                  label: 'MusicXML',
                  onPressed: () async {
                    try {
                      final dir = await getTemporaryDirectory();
                      final xmlPath = '${dir.path}/transcription_export.musicxml';
                      final file = File(xmlPath);
                      final xmlContent = _generateBasicMusicXml(state.noteEvents, state.duration);
                      await file.writeAsString(xmlContent);
                      await Share.shareXFiles([XFile(xmlPath)], text: 'MusicXML - Yanita Music');
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error exportando MusicXML: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  color: Colors.tealAccent,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9800),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DatabaseViewerPage(),
                    ),
                  );
                },
                child: const Text(
                  'Ver en Monitor de Datos',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final fileName = state.filePath.split('/').last.split('\\').last;
                  final title = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
                  context.read<TranscriptionBloc>().add(SaveTranscriptionResult(title: title));
                },
                icon: const Icon(Icons.check),
                label: const Text('Guardar y Continuar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9800),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    BuildContext context,
    TranscriptionError state,
    List<TranscriptionStep>? steps,
  ) {
    return Card(
      color: Colors.red.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Error en la transcripción',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.red),
                  ),
                ),
              ],
            ),
            if (steps != null) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              _buildStepsList(context, steps),
            ],
            const SizedBox(height: 16),
            Text(state.message, style: const TextStyle(color: Colors.white70)),

            // [RESULTADOS PARCIALES]: Permitir auditar WAV/PDF incluso en error
            if (state.lastFilePath != null || state.pdfPath != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Resultados parciales exitosos:',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (state.lastFilePath != null &&
                      state.lastFilePath!.endsWith('.wav'))
                    Expanded(
                      child: _WavAudioPlayerButton(
                        audioPath: state.lastFilePath!,
                        isStyleOutlined: true,
                      ),
                    ),
                  if (state.pdfPath != null) ...[
                    if (state.lastFilePath != null) const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Share.shareXFiles(
                          [XFile(state.pdfPath!)],
                          text:
                              'Espectrograma Yanita Music (Auditoría de Fallo)',
                        ),
                        icon: const Icon(
                          Icons.picture_as_pdf,
                          size: 16,
                          color: Colors.green,
                        ),
                        label: const Text(
                          'Exportar PDF',
                          style: TextStyle(fontSize: 11, color: Colors.green),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.green),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (state.lastFilePath != null) {
                    context.read<TranscriptionBloc>().add(
                      StartTranscription(filePath: state.lastFilePath!),
                    );
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar Transcripción'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.read<TranscriptionBloc>().add(ResetTranscription()),
                icon: const Icon(Icons.upload_file),
                label: const Text('Seleccionar Otra Canción'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DatabaseViewerPage(),
                      ),
                    ),
                    icon: const Icon(Icons.storage, size: 16),
                    label: const Text(
                      'Monitor',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LogViewerPage()),
                    ),
                    icon: const Icon(Icons.bug_report, size: 16),
                    label: const Text('Logs', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  void _showPianoOnlyAlert(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.piano, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 12),
            const Text('Solo Piano'),
          ],
        ),
        content: const Text(
          'Este sistema de transcripción automática (AMT) está diseñado '
          'exclusivamente para piano electrónico.\n\n'
          'No es posible transcribir:\n'
          '• Voces humanas\n'
          '• Guitarras u otros instrumentos\n'
          '• Mezclas de múltiples instrumentos\n\n'
          'Para mejores resultados, usa grabaciones de piano solo '
          'en formato MP3 o WAV.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DatabaseViewerPage()),
              );
            },
            child: const Text('Monitor Datos'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LogViewerPage()));
            },
            child: const Text('Diagnóstico'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Column(
      children: [
        IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.2),
            foregroundColor: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Reproductor WAV Controlado (Stateful)
// ════════════════════════════════════════════════════════════════
class _WavAudioPlayerButton extends StatefulWidget {
  final String audioPath;
  final bool isStyleOutlined;

  const _WavAudioPlayerButton({
    required this.audioPath,
    this.isStyleOutlined = false,
  });

  @override
  State<_WavAudioPlayerButton> createState() => _WavAudioPlayerButtonState();
}

class _WavAudioPlayerButtonState extends State<_WavAudioPlayerButton> {
  late AudioPlayer _player;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.playerStateStream.listen((state) {
      if (mounted && state.processingState == ProcessingState.completed) {
        setState(() => _isPlaying = false);
        _player.seek(Duration.zero);
        _player.stop();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.stop();
        setState(() => _isPlaying = false);
      } else {
        if (widget.audioPath.startsWith('assets/')) {
          await _player.setAsset(widget.audioPath);
        } else {
          await _player.setFilePath(widget.audioPath);
        }
        setState(() => _isPlaying = true);
        await _player.play();
      }
    } catch (e) {
      AppLogger.error('Error al reproducir WAV: $e');
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _isPlaying ? Colors.redAccent : Colors.green;
    final IconData icon = _isPlaying ? Icons.stop : Icons.play_arrow;
    final String label = _isPlaying ? 'Pausar WAV' : 'Oir WAV';

    if (widget.isStyleOutlined) {
      return OutlinedButton.icon(
        onPressed: _togglePlay,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(fontSize: 11, color: color)),
        style: OutlinedButton.styleFrom(side: BorderSide(color: color)),
      );
    }

    return Column(
      children: [
        IconButton.filled(
          onPressed: _togglePlay,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.2),
            foregroundColor: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Funciones auxiliares de exportación
// ════════════════════════════════════════════════════════════════

/// Genera bytes de un archivo MIDI básico (Format 0) a partir de NoteEvents.
List<int> _generateBasicMidiBytes(List<NoteEvent> notes, double duration) {
  final List<int> trackData = [];

  // Tempo meta-event: 500000 microseconds per beat (120 BPM)
  trackData.addAll([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]);

  // Track name
  const trackName = 'Yanita Music Export';
  trackData.addAll([0x00, 0xFF, 0x03, trackName.length]);
  trackData.addAll(trackName.codeUnits);

  const int ticksPerBeat = 480;
  const double bpm = 120.0;
  const double ticksPerSecond = ticksPerBeat * (bpm / 60.0);

  int lastTick = 0;

  // Sort notes by start time
  final sortedNotes = List<NoteEvent>.from(notes)
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  for (final note in sortedNotes) {
    final int startTick = (note.startTime * ticksPerSecond).round();
    final int endTick = (note.endTime * ticksPerSecond).round();
    final int velocity = note.velocity.clamp(1, 127).toInt();
    final int midiNote = note.midiNote.clamp(0, 127).toInt();

    // Note On
    final int deltaOn = startTick - lastTick;
    trackData.addAll(_writeVariableLength(deltaOn));
    trackData.addAll([0x90, midiNote, velocity]);

    // Note Off
    final int noteDuration = endTick - startTick;
    trackData.addAll(_writeVariableLength(noteDuration > 0 ? noteDuration : 1));
    trackData.addAll([0x80, midiNote, 0x00]);

    lastTick = endTick;
  }

  // End of Track
  trackData.addAll([0x00, 0xFF, 0x2F, 0x00]);

  // Build complete MIDI file
  final List<int> midi = [];
  // Header: MThd
  midi.addAll([0x4D, 0x54, 0x68, 0x64]); // "MThd"
  midi.addAll([0x00, 0x00, 0x00, 0x06]); // Header length
  midi.addAll([0x00, 0x00]); // Format 0
  midi.addAll([0x00, 0x01]); // 1 track
  midi.addAll([(ticksPerBeat >> 8) & 0xFF, ticksPerBeat & 0xFF]); // Ticks per beat

  // Track header: MTrk
  midi.addAll([0x4D, 0x54, 0x72, 0x6B]); // "MTrk"
  final int trackLen = trackData.length;
  midi.addAll([
    (trackLen >> 24) & 0xFF,
    (trackLen >> 16) & 0xFF,
    (trackLen >> 8) & 0xFF,
    trackLen & 0xFF,
  ]);
  midi.addAll(trackData);

  return midi;
}

/// Escribe un valor en formato variable-length MIDI.
List<int> _writeVariableLength(int value) {
  if (value < 0) value = 0;
  if (value < 0x80) return [value];
  final List<int> bytes = [];
  bytes.add(value & 0x7F);
  value >>= 7;
  while (value > 0) {
    bytes.add((value & 0x7F) | 0x80);
    value >>= 7;
  }
  return bytes.reversed.toList();
}

/// Genera un string MusicXML básico a partir de NoteEvents.
String _generateBasicMusicXml(List<NoteEvent> notes, double duration) {
  const pitchNames = ['C', 'C', 'D', 'D', 'E', 'F', 'F', 'G', 'G', 'A', 'A', 'B'];
  const pitchAlter = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0];

  final sortedNotes = List<NoteEvent>.from(notes)
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  sb.writeln('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">');
  sb.writeln('<score-partwise version="3.1">');
  sb.writeln('  <work><work-title>Yanita Music - Transcripción</work-title></work>');
  sb.writeln('  <part-list>');
  sb.writeln('    <score-part id="P1"><part-name>Piano</part-name></score-part>');
  sb.writeln('  </part-list>');
  sb.writeln('  <part id="P1">');

  // Agrupar notas por compás (4 beats = 2 segundos a 120 BPM)
  const double beatsPerMeasure = 4.0;
  const double secondsPerBeat = 0.5; // 120 BPM
  const double secondsPerMeasure = beatsPerMeasure * secondsPerBeat;
  final int totalMeasures = ((duration / secondsPerMeasure).ceil()).clamp(1, 100);

  for (int m = 0; m < totalMeasures; m++) {
    final double measureStart = m * secondsPerMeasure;
    final double measureEnd = measureStart + secondsPerMeasure;

    sb.writeln('    <measure number="${m + 1}">');
    if (m == 0) {
      sb.writeln('      <attributes>');
      sb.writeln('        <divisions>1</divisions>');
      sb.writeln('        <time><beats>4</beats><beat-type>4</beat-type></time>');
      sb.writeln('        <clef><sign>G</sign><line>2</line></clef>');
      sb.writeln('      </attributes>');
    }

    final measureNotes = sortedNotes.where((n) => n.startTime >= measureStart && n.startTime < measureEnd).toList();

    if (measureNotes.isEmpty) {
      sb.writeln('      <note><rest/><duration>4</duration><type>whole</type></note>');
    } else {
      for (final note in measureNotes) {
        final int midi = note.midiNote.clamp(21, 108).toInt();
        final int noteInOctave = (midi - 12) % 12;
        final int octave = ((midi - 12) ~/ 12);
        final String step = pitchNames[noteInOctave];
        final int alter = pitchAlter[noteInOctave];

        sb.writeln('      <note>');
        sb.writeln('        <pitch>');
        sb.writeln('          <step>$step</step>');
        if (alter != 0) sb.writeln('          <alter>$alter</alter>');
        sb.writeln('          <octave>$octave</octave>');
        sb.writeln('        </pitch>');
        sb.writeln('        <duration>1</duration>');
        sb.writeln('        <type>quarter</type>');
        sb.writeln('      </note>');
      }
    }
    sb.writeln('    </measure>');
  }

  sb.writeln('  </part>');
  sb.writeln('</score-partwise>');
  return sb.toString();
}
