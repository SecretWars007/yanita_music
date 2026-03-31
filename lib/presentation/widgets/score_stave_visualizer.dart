import 'package:flutter/material.dart';
import 'package:yanita_music/domain/entities/note_event.dart';
import 'package:yanita_music/domain/entities/score.dart';

/// Un visualizador de partituras que dibuja un pentagrama musical
/// y resalta las notas en tiempo real durante la reproducción.
class ScoreStaveVisualizer extends StatelessWidget {
  final Score score;
  final double currentTime;
  final bool isPlaying;
  final double staffScale;

  const ScoreStaveVisualizer({
    super.key,
    required this.score,
    required this.currentTime,
    this.isPlaying = false,
    this.staffScale = 1.0,
  });


  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260, // Aumentado de 200 a 260 para mejor visibilidad
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFD), // Blanco roto más premium
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: _StavePainter(
            noteEvents: score.noteEvents,
            currentTime: currentTime,
            accentColor: Theme.of(context).colorScheme.primary,
            staffScale: staffScale,
            tempo: score.tempo ?? 120.0,
          ),

          size: Size.infinite,
        ),
      ),
    );
  }
}

class _StavePainter extends CustomPainter {
  final List<NoteEvent> noteEvents;
  final double currentTime;
  final Color accentColor;
  final double staffScale;
  final double tempo;

  _StavePainter({
    required this.noteEvents,
    required this.currentTime,
    required this.accentColor,
    required this.tempo,
    this.staffScale = 1.0,
  });


  @override
  @override
  void paint(Canvas canvas, Size size) {
    // Pentagrama ocupa un poco más de alto
    // Pentagrama ocupa un poco más de alto, afectado por staffScale
    final double baseLineSpacing = (size.height * 0.55) / 4;
    final double lineSpacing = baseLineSpacing * staffScale;
    final double staveHeight = lineSpacing * 4;
    final double startY = (size.height - staveHeight) / 2;



    // Constantes de diseño para sincronización horizontal
    // [SENIOR ADJUST]: Reducimos timeWindow de 4.0 a 3.0 para dar MÁXIMO espacio 
    // horizontal a las notas (Zoom x2 respecto al original).
    const double timeWindow = 3.0;
    final double pixelsPerSecond = (size.width - 60) / timeWindow;
    final double playheadX = size.width * 0.2; // Playhead más a la izquierda para ver más futuro

    // 1. Dibujar clave de sol usando TextPainter (ANCLADA AL TIEMPO 0)
    final TextPainter clefPainter = TextPainter(
      text: TextSpan(
        text: '𝄞',
        style: TextStyle(
          fontSize: lineSpacing * 4.0, // Más pequeña como pidió el usuario
          color: Colors.black.withValues(alpha: 0.8),
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    clefPainter.layout();
    
    // Posicionar la clave relativa al tiempo 0 para que se desplace con las notas
    final double clefX = playheadX + (0 - currentTime) * pixelsPerSecond - (clefPainter.width + 20);
    final double clefY = startY - lineSpacing * 0.7; 
    
    // Solo dibujamos la clave si es visible en el área actual
    if (clefX + clefPainter.width > 0 && clefX < size.width) {
      clefPainter.paint(canvas, Offset(clefX, clefY));
    }

    final Paint linePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = 1.5; // Líneas un poco más gruesas

    // 2. Dibujar las 5 líneas del pentagrama
    for (int i = 0; i < 5; i++) {
      final y = startY + (i * lineSpacing);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    if (noteEvents.isEmpty) {
      return;
    }

    // 4. Dibujar notas (OPTIMIZADO: Solo las visibles)

    // Buscar el rango de notas visibles usando búsqueda binaria simple
    // Esto es vital para partituras de miles de notas.
    final int startIndex = _findFirstVisibleNote(currentTime - 2.0); // 2s de margen atrás
    final int endIndex = _findFirstVisibleNote(currentTime + timeWindow + 1.0);

    for (int i = startIndex; i < endIndex && i < noteEvents.length; i++) {
      final note = noteEvents[i];
      final double x = playheadX + (note.startTime - currentTime) * pixelsPerSecond;

      if (x < -50 || x > size.width + 50) continue;

      // Mapeo MIDI a Posición Y (y detección de accidental)
      final int midi = note.midiNote;
      final int octave = (midi ~/ 12) - 1;
      final int noteInOctave = midi % 12;
      
      bool isSharp = false;
      int step = octave * 7;
      
      // Mapeo exacto de los 12 semitonos a grados del pentagrama
      switch (noteInOctave) {
        case 0: step += 0; break; // C
        case 1: step += 0; isSharp = true; break; // C#
        case 2: step += 1; break; // D
        case 3: step += 1; isSharp = true; break; // D#
        case 4: step += 2; break; // E
        case 5: step += 3; break; // F
        case 6: step += 3; isSharp = true; break; // F#
        case 7: step += 4; break; // G
        case 8: step += 4; isSharp = true; break; // G#
        case 9: step += 5; break; // A
        case 10: step += 5; isSharp = true; break; // A#
        case 11: step += 6; break; // B
      }

      // Ref: E4 (64) es el paso 30. Línea inferior = startY + 4 * lineSpacing
      final double y = (startY + 4 * lineSpacing) - (step - 30) * (lineSpacing / 2);

      final bool isActive = currentTime >= note.startTime && currentTime <= note.endTime;
      final bool isPast = currentTime > note.endTime;
      final Color noteColor = isActive 
          ? accentColor 
          : (isPast ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.9));

      // Dibujar Sostenido (#) si aplica
      if (isSharp) {
        final TextPainter sharpPainter = TextPainter(
          text: TextSpan(
            text: '♯',
            style: TextStyle(
              fontSize: lineSpacing * 1.8,
              color: noteColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        sharpPainter.layout();
        sharpPainter.paint(canvas, Offset(x - 32, y - lineSpacing * 0.9));
      }

      // Dibujar líneas adicionales (Ledger Lines)
      final Paint ledgerPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..strokeWidth = 1.5;
      
      if (step <= 28) {
        for (int s = 28; s >= step; s -= 2) {
          final double ly = (startY + 4 * lineSpacing) - (s - 30) * (lineSpacing / 2);
          canvas.drawLine(Offset(x - 18, ly), Offset(x + 18, ly), ledgerPaint);
        }
      }
      if (step >= 40) {
        for (int s = 40; s <= step; s += 2) {
          final double ly = (startY + 4 * lineSpacing) - (s - 30) * (lineSpacing / 2);
          canvas.drawLine(Offset(x - 18, ly), Offset(x + 18, ly), ledgerPaint);
        }
      }

      final double duration = note.endTime - note.startTime;
      final double durationInBeats = (duration * tempo) / 60.0;

      // Determinar el tipo de nota (musical figure)
      final bool isWhole = durationInBeats >= 3.5; // Redonda
      final bool isHalf = !isWhole && durationInBeats >= 1.5; // Blanca
      final bool isQuarter = !isWhole && !isHalf; // Negra

      final Paint notePaint = Paint()
        ..color = noteColor
        ..strokeWidth = 2.5
        ..style = isQuarter ? PaintingStyle.fill : PaintingStyle.stroke;

      // El alto de la nota debe encajar exactamente entre las líneas del pentagrama.
      // radio vertical = lineSpacing / 2
      final double radiusY = (lineSpacing / 2) * 0.92; 
      final double radiusX = isWhole ? radiusY * 1.5 : radiusY * 1.35;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-0.25); 

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radiusX * 2,
          height: radiusY * 2,
        ),
        notePaint,
      );

      if (isActive && !isQuarter) {
        // Relleno sutil para nota activa hueca
        final Paint activeFill = Paint()
          ..color = accentColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: radiusX * 2,
            height: radiusY * 2,
          ),
          activeFill,
        );
      }
      canvas.restore();

      // Dibujar PLICA (Stem) - Las redondas NO tienen plica
      if (!isWhole) {
        final bool stemUp = step < 34; // Plica hacia arriba para notas bajas (debajo de la 3ra línea)
        final double stemHeight = lineSpacing * 3.2; // Altura estándar de la plica
        // El stem de la plica va desde el lado derecho si es hacia arriba, y desde el izquierdo si es hacia abajo
        final double stemX = stemUp ? x + radiusX * 0.9 : x - radiusX * 0.9;
        final double stemStartY = stemUp ? y : y;
        final double stemEndY = stemUp ? y - stemHeight : y + stemHeight;

        canvas.drawLine(
          Offset(stemX, stemStartY),
          Offset(stemX, stemEndY),
          Paint()
            ..color = noteColor
            ..strokeWidth = 1.5,
        );
      }
    }
    
    // (Resto del código del playhead...)
    // 4. Dibujar línea de tiempo (Playhead) - Más visible y elegante
    final Paint playheadPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.8)
      ..strokeWidth = 2.5;
    
    // Línea principal
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
    
    // Triángulo arriba del playhead
    final Path arrowPath = Path()
      ..moveTo(playheadX - 8, 0)
      ..lineTo(playheadX + 8, 0)
      ..lineTo(playheadX, 12)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = accentColor);
  }

  /// Búsqueda binaria para encontrar la primera nota que podría ser visible.
  int _findFirstVisibleNote(double targetTime) {
    if (noteEvents.isEmpty) return 0;
    
    int low = 0;
    int high = noteEvents.length - 1;
    
    while (low <= high) {
      final int mid = low + (high - low) ~/ 2;
      if (noteEvents[mid].startTime < targetTime) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  @override
  bool shouldRepaint(covariant _StavePainter oldDelegate) {
    return oldDelegate.currentTime != currentTime ||
        oldDelegate.noteEvents != noteEvents ||
        oldDelegate.staffScale != staffScale;

  }
}
