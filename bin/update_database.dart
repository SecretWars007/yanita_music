// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:yanita_music/core/utils/music_xml_parser.dart';
import 'package:yanita_music/domain/entities/note_event.dart';

void main() async {
  print('--- Saneador de Base de Datos Profundo (Twinkle Full + Chopin) ---');
  
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = p.join(Directory.current.path, 'assets', 'database', 'yanitadb.db');
  if (!File(dbPath).existsSync()) {
    print('Error: No se encontró la base de datos en $dbPath');
    return;
  }

  final db = await openDatabase(dbPath);

  try {
    print('Recreando esquema de tablas (scores, songs)...');
    
    await db.execute('DROP TABLE IF EXISTS scores');
    await db.execute('DROP TABLE IF EXISTS songs');

    await db.execute('''
      CREATE TABLE scores (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        audio_path TEXT NOT NULL,
        midi_data TEXT,
        music_xml TEXT,
        note_events TEXT NOT NULL DEFAULT '[]',
        duration REAL,
        tempo REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        checksum TEXT,
        spectrogram_data TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE songs (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        artist TEXT,
        score_path TEXT,
        cover_path TEXT,
        is_demo INTEGER DEFAULT 0,
        category TEXT,
        difficulty INTEGER,
        is_favorite INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    final demos = [
      {
        'id': '08f22e9e-1d07-4b55-9a68-ea05cf89121f',
        'title': 'Bach: Minuet in G',
        'artist': 'J.S. Bach',
        'score_mxl': 'bach_minuet_g.mxl',
        'audio': 'assets/audio/bach_minuet_g.mp3',
        'category': 'Clásica',
        'difficulty': 1,
      },
      {
        'id': 'f51553d8-cd38-40d6-b016-1083c2849e58',
        'title': 'Twinkle Twinkle Little Star (Full)',
        'artist': 'Traditional',
        'score_mxl': 'twinkle_twinkle.mxl', 
        'audio': 'assets/audio/twinkle_twinkle.mp3', // Este pesa 24MB y está completo
        'category': 'Infantil',
        'difficulty': 1,
      },
      {
        'id': '47f89d3c-918d-4a1e-b81e-28ac31c59622',
        'title': 'Chopin: Nocturne (Completo)',
        'artist': 'F. Chopin',
        'score_mxl': 'chopin_nocturne_op9_2.mxl',
        'audio': 'assets/audio/chopin_nocturne_op9_2.mp3', // Este pesa 5MB y está completo
        'category': 'Clásica',
        'difficulty': 3,
      }
    ];

    for (var demo in demos) {
      print('Procesando ${demo['title']}...');
      final mxlPath = p.join('assets', 'scores', demo['score_mxl'] as String);
      final mxlFile = File(mxlPath);
      
      String noteEventsJson = '[]';
      double duration = 60.0;

      if (mxlFile.existsSync()) {
        final bytes = mxlFile.readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);
        for (var file in archive) {
          if (file.name.toLowerCase().endsWith('.xml') && !file.name.contains('container.xml')) {
            final xml = utf8.decode(file.content as List<int>);
            const parser = MusicXmlParser();
            final List<NoteEvent> notes = parser.parse(xml);
            if (notes.isNotEmpty) {
              noteEventsJson = jsonEncode(notes.map((n) => {
                'start_time': n.startTime,
                'end_time': n.endTime,
                'midi_note': n.midiNote,
                'velocity': 80,
              }).toList());
              // Ajustar duración a la última nota + 2s de margen
              duration = notes.last.endTime + 2.0;
              print('   -> ${notes.length} notas extraídas. Duración estimada: ${duration.toStringAsFixed(1)}s');
            }
          }
        }
      }

      // IMPORTANTE: Si es el Bach MP3 de 132KB, forzar duración real para evitar "Source error"
      if (demo['audio'] == 'assets/audio/bach_minuet_g.mp3') {
        duration = 8.2; // 132KB @ 128kbps approx
        print('   -> Sincronizando Bach a duración real del archivo: 8.2s');
      }

      final now = DateTime.now().toIso8601String();
      
      await db.insert('scores', {
        'id': demo['id'],
        'title': demo['title'],
        'audio_path': demo['audio'],
        'note_events': noteEventsJson,
        'duration': duration,
        'tempo': 120.0,
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('songs', {
        'id': demo['id'],
        'title': demo['title'],
        'artist': demo['artist'],
        'score_path': '',
        'cover_path': '',
        'is_demo': 1,
        'category': demo['category'],
        'difficulty': demo['difficulty'],
        'is_favorite': 0,
        'created_at': now,
      });
    }

    print('\n¡ÉXITO TOTAL! Base de datos de assets regenerada.');
  } catch (e) {
    print('Error fatal: $e');
  } finally {
    await db.close();
  }
}
