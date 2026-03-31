import 'package:path/path.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:yanita_music/core/constants/app_constants.dart';
import 'package:yanita_music/core/constants/db_constants.dart';
import 'package:yanita_music/core/utils/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper singleton para gestión de la base de datos SQLite.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  static Future<Database>? _dbFuture;
  static const String _tag = 'DatabaseHelper';

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _dbFuture ??= _initDatabase();
    _database = await _dbFuture;
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Inicializar FFI solo en plataformas de escritorio para evitar MissingPluginException en móviles
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, AppConstants.dbName);

    // LÓGICA DE RESET FORZADO (V16)
    // Borra la base de datos local si la última versión registrada es menor a 16.
    // NO copiamos desde assets para evitar restaurar canciones demo preempaquetadas.
    final prefs = await SharedPreferences.getInstance();
    final int lastVersion = prefs.getInt('last_db_version') ?? 0;
    bool didForceReset = false;

    if (lastVersion < 17) {
      AppLogger.info(
        'Detectada migración crítica a v17. Reseteando base de datos local para limpiar canciones demo...',
        tag: _tag,
      );
      if (File(path).existsSync()) {
        await File(path).delete();
        AppLogger.info('Base de datos antigua eliminada.', tag: _tag);
      }
      await prefs.setInt('last_db_version', 17);
      didForceReset = true;
    }

    // Verificar existencia usando File de dart:io (más seguro que databaseExists)
    final exists = File(path).existsSync();

    if (!exists && !didForceReset) {
      // Solo copiar desde assets si NO acabamos de hacer un reset forzado.
      // Si hicimos reset, dejamos que _onCreate cree una BD vacía y limpia.
      AppLogger.info(
        'Copiando base de datos preempaquetada desde assets...',
        tag: _tag,
      );
      try {
        // Crear el directorio si no existe
        await Directory(dirname(path)).create(recursive: true);

        // Copiar desde assets
        final ByteData data = await rootBundle.load(
          join('assets', 'database', AppConstants.dbName),
        );
        final List<int> bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );

        // Escribir el archivo
        await File(path).writeAsBytes(bytes, flush: true);
        AppLogger.info(
          'Base de datos copiada exitosamente a: $path',
          tag: _tag,
        );
      } catch (e) {
        AppLogger.error(
          'Error al copiar la base de datos desde assets: $e',
          tag: _tag,
        );
        // Si falla la copia, dejar que _onCreate cree una BD nueva
        AppLogger.info('Se creará una BD vacía desde cero.', tag: _tag);
      }
    } else if (!exists && didForceReset) {
      // Crear el directorio para que openDatabase pueda crear el archivo
      await Directory(dirname(path)).create(recursive: true);
      AppLogger.info(
        'Reset forzado: se creará BD vacía sin canciones demo.',
        tag: _tag,
      );
    } else {
      AppLogger.info('Base de datos ya existe en: $path', tag: _tag);
    }

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    AppLogger.info('Creando tablas iniciales (v$version)...', tag: _tag);
    await _createTables(db);
    await _seedDemoData(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    AppLogger.info(
      'Actualizando base de datos de $oldVersion a $newVersion...',
      tag: _tag,
    );
    if (oldVersion < 10) {
      // Limpieza total definitiva para eliminar 5ta Sinfonía y Bella Ciao (corruptas)
      await db.execute('DROP TABLE IF EXISTS ${DbConstants.scoresTable}');
      await db.execute('DROP TABLE IF EXISTS ${DbConstants.songsTable}');
      await _createTables(db);
      await _seedDemoData(db);
    }

    if (oldVersion < 12) {
      try {
        await db.execute(
          'ALTER TABLE ${DbConstants.scoresTable} ADD COLUMN ${DbConstants.colWavPath} TEXT',
        );
        await db.execute(
          'ALTER TABLE ${DbConstants.scoresTable} ADD COLUMN ${DbConstants.colPdfPath} TEXT',
        );
        await db.execute(
          'ALTER TABLE ${DbConstants.scoresTable} ADD COLUMN ${DbConstants.colTranscriptionSteps} TEXT',
        );
        AppLogger.info('Migración v12 completada en base de datos.', tag: _tag);
      } catch (e) {
        AppLogger.warning('Error en alter table v12: $e', tag: _tag);
      }
    }

    if (oldVersion < 13) {
      try {
        await db.execute(
          'ALTER TABLE ${DbConstants.scoresTable} ADD COLUMN ${DbConstants.colMusicXml} TEXT',
        );
        AppLogger.info('Migración v13 completada en base de datos.', tag: _tag);
      } catch (e) {
        AppLogger.warning('Error en alter table v13: $e', tag: _tag);
      }
    }
    if (oldVersion < 17) {
      AppLogger.info(
        'Forzando limpieza total de BD para v17 (eliminar canciones demo preempaquetadas)',
        tag: _tag,
      );
      await db.execute('DROP TABLE IF EXISTS ${DbConstants.scoresTable}');
      await db.execute('DROP TABLE IF EXISTS ${DbConstants.songsTable}');
      await _createTables(db);
    }
  }

  Future<void> _onOpen(Database db) async {
    // Sanity check de esquemas críticos para evitar errores con DBs heredadas
    final columns = [
      DbConstants.colWavPath,
      DbConstants.colMusicXml,
      DbConstants.colTranscriptionSteps,
      DbConstants.colDuration,
      DbConstants.colTempo,
    ];
    for (final col in columns) {
      try {
        await db.execute(
          'ALTER TABLE ${DbConstants.scoresTable} ADD COLUMN $col TEXT',
        );
      } catch (_) {} // Column ya existe o error irrelevante
    }

    // Sanity check: Asegurar que las tablas existan siempre
    await _createTables(db);
    AppLogger.info('Base de datos abierta correctamente.', tag: _tag);
  }

  /// Método de siembra de datos demo — DESACTIVADO.
  /// Las canciones solo aparecen después de transcribirlas manualmente.
  Future<void> _seedDemoData(Database db) async {
    // No-op: eliminado para evitar insertar canciones demo
    return;
  }

  Future<void> _createTables(Database db) async {
    // Transacción para creación de tablas
    await db.transaction((txn) async {
      // Tabla de Partituras
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.scoresTable} (
          ${DbConstants.colId} TEXT PRIMARY KEY NOT NULL,
          ${DbConstants.colTitle} TEXT NOT NULL,
          ${DbConstants.colAudioPath} TEXT NOT NULL,
          ${DbConstants.colMidiData} TEXT,
          ${DbConstants.colMusicXml} TEXT,
          ${DbConstants.colNoteEvents} TEXT NOT NULL DEFAULT '[]',
          ${DbConstants.colDuration} REAL,
          ${DbConstants.colTempo} REAL,
          ${DbConstants.colCreatedAt} TEXT NOT NULL,
          ${DbConstants.colUpdatedAt} TEXT NOT NULL,
          ${DbConstants.colChecksum} TEXT,
          ${DbConstants.colSpectrogramData} TEXT,
          ${DbConstants.colWavPath} TEXT,
          ${DbConstants.colPdfPath} TEXT,
          ${DbConstants.colTranscriptionSteps} TEXT
        )
      ''');

      // Tabla de Canciones (Songbook)
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.songsTable} (
          ${DbConstants.colSongId} TEXT PRIMARY KEY NOT NULL,
          ${DbConstants.colSongTitle} TEXT NOT NULL,
          ${DbConstants.colArtist} TEXT,
          ${DbConstants.colScorePath} TEXT,
          ${DbConstants.colCoverPath} TEXT,
          ${DbConstants.colIsDemo} INTEGER DEFAULT 0,
          ${DbConstants.colCategory} TEXT,
          ${DbConstants.colDifficulty} INTEGER,
          ${DbConstants.colIsFavorite} INTEGER DEFAULT 0,
          ${DbConstants.colSongCreatedAt} TEXT NOT NULL
        )
      ''');

      // Tabla de Métricas
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.metricsTable} (
          ${DbConstants.colMetricId} TEXT PRIMARY KEY NOT NULL,
          ${DbConstants.colMetricScoreId} TEXT NOT NULL,
          ${DbConstants.colPrecision} REAL,
          ${DbConstants.colRecall} REAL,
          ${DbConstants.colFMeasure} REAL,
          ${DbConstants.colIsPolyphonic} INTEGER,
          ${DbConstants.colMetricCreatedAt} TEXT NOT NULL,
          FOREIGN KEY (${DbConstants.colMetricScoreId}) 
            REFERENCES ${DbConstants.scoresTable} (${DbConstants.colId}) 
            ON DELETE CASCADE
        )
      ''');

      // Tabla de Logs
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.logsTable} (
          ${DbConstants.colLogId} INTEGER PRIMARY KEY AUTOINCREMENT,
          ${DbConstants.colLogLevel} TEXT NOT NULL,
          ${DbConstants.colLogMessage} TEXT NOT NULL,
          ${DbConstants.colLogTag} TEXT,
          ${DbConstants.colLogStackTrace} TEXT,
          ${DbConstants.colLogCreatedAt} TEXT NOT NULL
        )
      ''');
    });
  }

  Future<void> _onConfigure(Database db) async {
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute('PRAGMA synchronous=NORMAL');
    await db.execute('PRAGMA cache_size=10000');
    await db.execute('PRAGMA temp_store=MEMORY');
  }

  // --- MÉTODOS DE LOGS ---

  Future<int> insertLog(Map<String, dynamic> logData) async {
    try {
      final db = await database;
      return await db.insert(DbConstants.logsTable, logData);
    } catch (e) {
      // ignore: avoid_print
      print('CRITICAL ERROR: Failed to persist log to DB: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getLogs({int limit = 100}) async {
    final db = await database;
    return await db.query(
      DbConstants.logsTable,
      orderBy: '${DbConstants.colLogCreatedAt} DESC',
      limit: limit,
    );
  }

  Future<void> clearLogs() async {
    final db = await database;
    await db.delete(DbConstants.logsTable);
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
