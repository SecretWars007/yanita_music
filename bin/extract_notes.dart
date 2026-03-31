// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:yanita_music/core/utils/music_xml_parser.dart';
import 'package:yanita_music/domain/entities/note_event.dart';

void main() async {
  print('--- Extractor de Notas de MusicXML ---');
  
  final files = [
    'bach_minuet_g.mxl', 
    'chopin_nocturne_op9_2.mxl',
    'beethoven_5th_symphony.mxl'
  ];
  
  for (var fileName in files) {
    final path = 'assets/scores/$fileName';
    final file = File(path);
    if (!file.existsSync()) {
      print('Archivo no encontrado: $path');
      continue;
    }
    
    try {
      final bytes = file.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (var zipFile in archive) {
        if (zipFile.name.toLowerCase().endsWith('.xml') && !zipFile.name.contains('container.xml')) {
          final xmlString = utf8.decode(zipFile.content as List<int>);
          const parser = MusicXmlParser();
          final List<NoteEvent> notes = parser.parse(xmlString);
          
          if (notes.isNotEmpty) {
            print('--- $fileName (${notes.length} notas) ---');
            final jsonList = notes.map((n) => {
              'start_time': double.parse(n.startTime.toStringAsFixed(3)),
              'end_time': double.parse(n.endTime.toStringAsFixed(3)),
              'midi_note': n.midiNote,
              'velocity': n.velocity,
            }).toList();
            
            // Imprimir solo los primeros 2000 caracteres para no saturar si es muy largo
            // pero el usuario necesita el JSON completo.
            print(jsonEncode(jsonList));
          }
        }
      }
    } catch (e) {
      print('Error procesando $fileName: $e');
    }
  }
}
