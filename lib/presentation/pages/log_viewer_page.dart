import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:yanita_music/domain/entities/log_entry.dart';
import 'package:yanita_music/domain/repositories/log_repository.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  final LogRepository _logRepository = GetIt.I<LogRepository>();
  List<LogEntry> _logs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final logs = await _logRepository.getLogs(limit: 500);
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Colors.red;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.debug:
        return Colors.grey;
    }
  }

  void _copyToClipboard() {
    final logText = _logs.map((l) {
      final time = DateFormat('HH:mm:ss').format(l.createdAt);
      return '[$time] [${l.level.name.toUpperCase()}] [${l.tag}] ${l.message}';
    }).join('\n');
    
    Clipboard.setData(ClipboardData(text: logText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copiados al portapapeles')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visor de Logs (Diagnóstico)'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _logs.isEmpty ? null : _copyToClipboard,
            tooltip: 'Copiar todo',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: 'Refrescar',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              await _logRepository.clearLogs();
              _loadLogs();
            },
            tooltip: 'Limpiar logs',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _logs.isEmpty
                  ? const Center(child: Text('No hay logs registrados.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (ctx, idx) {
                        final log = _logs[idx];
                        final time = DateFormat('HH:mm:ss').format(log.createdAt);
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getLevelColor(log.level),
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            log.message,
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                          ),
                          subtitle: Text(
                            '[$time] [${log.tag}]',
                            style: const TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: log.message));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Mensaje copiado')),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
