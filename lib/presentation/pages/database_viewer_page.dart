import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yanita_music/data/datasources/local/database_helper.dart';
import 'package:yanita_music/core/constants/db_constants.dart';
import 'package:yanita_music/core/utils/logger.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';

class DatabaseViewerPage extends StatefulWidget {
  const DatabaseViewerPage({super.key});

  @override
  State<DatabaseViewerPage> createState() => _DatabaseViewerPageState();
}

class _DatabaseViewerPageState extends State<DatabaseViewerPage> {
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;
  final AudioPlayer _player = AudioPlayer();
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper().database;
      final data = await db.query(DbConstants.scoresTable, orderBy: '${DbConstants.colCreatedAt} DESC');
      setState(() {
        _records = data;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Error cargando datos de DB: $e', tag: 'DatabaseViewer');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _playWav(String path, String id) async {
    try {
      if (_currentlyPlayingId == id && _player.playing) {
        await _player.stop();
        setState(() => _currentlyPlayingId = null);
        return;
      }

      await _player.setFilePath(path);
      setState(() => _currentlyPlayingId = id);
      await _player.play();
      setState(() => _currentlyPlayingId = null);
    } catch (e) {
      AppLogger.error('Error reproduciendo WAV: $e', tag: 'DatabaseViewer');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al reproducir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _shareFile(String path, String title) async {
    final file = File(path);
    if (!file.existsSync()) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El archivo físico no existe en el almacenamiento')),
        );
      }
      return;
    }
    await Share.shareXFiles([XFile(path)], text: 'Archivo de Yanita Music: $title');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Monitor de Datos y Archivos', style: GoogleFonts.inter(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)))
          : _records.isEmpty
              ? const Center(child: Text('No hay registros en la base de datos', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    return _buildRecordCard(record);
                  },
                ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final String? wavPath = record[DbConstants.colWavPath];
    final String? pdfPath = record[DbConstants.colPdfPath];
    final String id = record[DbConstants.colId];
    final String title = record[DbConstants.colTitle] ?? 'Sin título';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ExpansionTile(
        iconColor: const Color(0xFFFF9800),
        collapsedIconColor: Colors.white54,
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            if (_isProcessing(record[DbConstants.colTranscriptionSteps]))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber.shade700, width: 0.5),
                ),
                child: const Text(
                  'EN PROCESO',
                  style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'ID: $id',
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wavPath != null && wavPath.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(child: _buildInfoRow('Archivo WAV Persistido', wavPath)),
                      IconButton(
                        icon: Icon(
                          _currentlyPlayingId == id ? Icons.stop_circle : Icons.play_circle_filled, 
                          color: const Color(0xFFFF9800),
                          size: 32,
                        ),
                        onPressed: () => _playWav(wavPath, id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.blueAccent),
                        onPressed: () => _shareFile(wavPath, 'Audio WAV - $title'),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                ],
                if (pdfPath != null && pdfPath.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(child: _buildInfoRow('Informe PDF Espectrograma', pdfPath)),
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 32),
                        onPressed: () => _shareFile(pdfPath, 'Informe PDF - $title'),
                        tooltip: 'Exportar/Compartir PDF',
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                ],
                _buildInfoRow('Ruta Audio Original', record[DbConstants.colAudioPath]),
                _buildInfoRow('Datos Espectrograma', record[DbConstants.colSpectrogramData] != null ? 'Presente (${record[DbConstants.colSpectrogramData].toString().length} chars)' : 'Nulo'),
                _buildInfoRow('Duración', '${record[DbConstants.colDuration]}s'),
                _buildInfoRow('Notas', '${jsonDecode(record[DbConstants.colNoteEvents] ?? '[]').length} notas'),
                const SizedBox(height: 12),
                const Text('Pasos de Transcripción:', style: TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    _formatSteps(record[DbConstants.colTranscriptionSteps]),
                    style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFFF9800), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              value ?? 'N/A',
              style: GoogleFonts.firaCode(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isProcessing(String? stepsJson) {
    if (stepsJson == null) return false;
    try {
      final List<dynamic> steps = jsonDecode(stepsJson);
      // Si hay algún paso en estado 'processing' o alguno sigue en 'pending' (y no es el último), consideramos que está en proceso
      return steps.any((s) => s['status'] == 'processing' || s['status'] == 'pending');
    } catch (e) {
      return false;
    }
  }

  String _formatSteps(String? stepsJson) {
    if (stepsJson == null) return 'No hay pasos registrados';
    try {
      final List<dynamic> steps = jsonDecode(stepsJson);
      return steps.map((s) => '- ${s['title']}: ${s['status']}').join('\n');
    } catch (e) {
      return 'Error al decodificar pasos';
    }
  }
}
