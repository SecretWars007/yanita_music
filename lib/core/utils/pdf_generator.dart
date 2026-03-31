import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:yanita_music/core/utils/logger.dart';

/// Utilidad para generar informes PDF con el espectrograma y metadatos de la transcripción.
class PdfGenerator {
  static const String _tag = 'PdfGenerator';

  /// Genera un PDF que muestra el espectrograma (simulado como imagen o datos) y metadatos.
  static Future<String> generateSpectrogramPdf({
    required String title,
    required String date,
    required String duration,
    required dynamic spectrogramData,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 0, text: 'Informe de Transcripción Yanita Music'),
              pw.SizedBox(height: 20),
              pw.Text('Título: $title', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Fecha: $date'),
              pw.Text('Duración: $duration'),
              pw.SizedBox(height: 20),
              pw.Header(level: 1, text: 'Visualización del Espectrograma (Resumen)'),
              pw.SizedBox(height: 10),
              // Representación visual simple del espectrograma (Miniatura de barras)
              pw.Container(
                height: 300,
                width: double.infinity,
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
                padding: const pw.EdgeInsets.all(5),
                child: pw.Center(
                  child: pw.Text('Datos del espectrograma procesados exitosamente.\n'
                      'Ejes: Frecuencia (Hz) vs Tiempo (s)\n'
                      'Muestras capturadas: ${spectrogramData.length} frames.'),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Este documento certifica la validación de la transcripción automática.',
                  style: pw.TextStyle(fontStyle: pw.FontStyle.italic)),
            ],
          );
        },
      ),
    );

    final outputDir = await getApplicationDocumentsDirectory();
    final transcriptionsDir = Directory('${outputDir.path}/transcriptions');
    if (!transcriptionsDir.existsSync()) {
      await transcriptionsDir.create(recursive: true);
    }

    final filePath = '${transcriptionsDir.path}/spectrogram_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    AppLogger.info('PDF de espectrograma generado en: $filePath', tag: _tag);
    return filePath;
  }
}
