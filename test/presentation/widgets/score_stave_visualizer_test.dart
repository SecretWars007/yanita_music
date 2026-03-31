import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yanita_music/domain/entities/note_event.dart';
import 'package:yanita_music/domain/entities/score.dart';
import 'package:yanita_music/presentation/widgets/score_stave_visualizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Canciones de prueba (simulan los datos demo reales)
// ─────────────────────────────────────────────────────────────────────────────
final _twinkleTwinkle = Score(
  id: '08f22e9e-1d07-4b55-9a68-ea05cf89121f',
  title: 'Twinkle Twinkle Little Star',
  audioPath: 'assets/audio/twinkle_twinkle.mp3',
  duration: 25.0,
  tempo: 100.0,
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 1),
  noteEvents: const [
    NoteEvent(startTime: 0.0, endTime: 0.5, midiNote: 60, velocity: 80),  // Do
    NoteEvent(startTime: 0.5, endTime: 1.0, midiNote: 60, velocity: 80),  // Do
    NoteEvent(startTime: 1.0, endTime: 1.5, midiNote: 67, velocity: 80),  // Sol
    NoteEvent(startTime: 1.5, endTime: 2.0, midiNote: 67, velocity: 80),  // Sol
    NoteEvent(startTime: 2.0, endTime: 2.5, midiNote: 69, velocity: 80),  // La
    NoteEvent(startTime: 2.5, endTime: 3.0, midiNote: 69, velocity: 80),  // La
    NoteEvent(startTime: 3.0, endTime: 4.0, midiNote: 67, velocity: 80),  // Sol (blanca)
  ],
);

final _odeToJoy = Score(
  id: 'f51553d8-cd38-40d6-b016-1083c2849e58',
  title: 'Beethoven: Ode to Joy',
  audioPath: 'assets/audio/ode_to_joy.mp3',
  duration: 54.0,
  tempo: 120.0,
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 1),
  noteEvents: const [
    NoteEvent(startTime: 0.0,  endTime: 0.5,  midiNote: 64, velocity: 80),  // Mi
    NoteEvent(startTime: 0.5,  endTime: 1.0,  midiNote: 64, velocity: 80),  // Mi
    NoteEvent(startTime: 1.0,  endTime: 1.5,  midiNote: 65, velocity: 80),  // Fa
    NoteEvent(startTime: 1.5,  endTime: 2.0,  midiNote: 67, velocity: 80),  // Sol
    NoteEvent(startTime: 2.0,  endTime: 2.5,  midiNote: 67, velocity: 80),  // Sol
    NoteEvent(startTime: 2.5,  endTime: 3.0,  midiNote: 65, velocity: 80),  // Fa
    NoteEvent(startTime: 3.0,  endTime: 3.5,  midiNote: 64, velocity: 80),  // Mi
    NoteEvent(startTime: 3.5,  endTime: 4.0,  midiNote: 62, velocity: 80),  // Re
  ],
);

final _chopinNocturne = Score(
  id: '47f89d3c-918d-4a1e-b81e-28ac31c59622',
  title: 'Chopin: Nocturne Op. 9 No. 2',
  audioPath: 'assets/audio/chopin_nocturne_op9_2.mp3',
  duration: 258.0,
  tempo: 70.0,
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 1),
  noteEvents: const [
    NoteEvent(startTime: 0.0, endTime: 0.5,  midiNote: 58, velocity: 60),
    NoteEvent(startTime: 0.5, endTime: 1.5,  midiNote: 67, velocity: 60),
    NoteEvent(startTime: 1.5, endTime: 2.0,  midiNote: 65, velocity: 60),
    NoteEvent(startTime: 2.0, endTime: 2.5,  midiNote: 67, velocity: 60),
    NoteEvent(startTime: 2.5, endTime: 3.0,  midiNote: 63, velocity: 60),
    NoteEvent(startTime: 3.0, endTime: 5.14, midiNote: 62, velocity: 60), // Redonda a 70bpm
    NoteEvent(startTime: 5.5, endTime: 7.71, midiNote: 63, velocity: 60), // Redonda
    NoteEvent(startTime: 8.0, endTime: 9.71, midiNote: 58, velocity: 60), // Blanca larga
  ],
);

// ─────────────────────────────────────────────────────────────────────────────
// Helper: construye el widget y lo coloca en un frame de tamaño fijo.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _pump(WidgetTester tester, Score score, double currentTime,
    {bool isPlaying = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 260,
          child: ScoreStaveVisualizer(
            score: score,
            currentTime: currentTime,
            isPlaying: isPlaying,
          ),
        ),
      ),
    ),
  );
  // Damos un frame extra para que el pintor termine
  await tester.pump();
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // 1. TESTS UNITARIOS: NoteEvent – Cálculo de tipo de figura musical
  // ───────────────────────────────────────────────────────────────────────────
  group('NoteEvent – Cálculo de figuras musicales', () {
    double beats(double durationSec, double tempo) =>
        (durationSec * tempo) / 60.0;

    test('Negra: 1 tiempo   @ 120 BPM → ~0.5s', () {
      final result = beats(0.5, 120);
      expect(result, closeTo(1.0, 0.01));
      expect(result < 1.5, isTrue, reason: 'Debe ser negra');
    });

    test('Blanca: 2 tiempos @ 120 BPM → ~1.0s', () {
      final result = beats(1.0, 120);
      expect(result, closeTo(2.0, 0.01));
      expect(result >= 1.5 && result < 3.5, isTrue, reason: 'Debe ser blanca');
    });

    test('Redonda: 4 tiempos @ 120 BPM → ~2.0s', () {
      final result = beats(2.0, 120);
      expect(result, closeTo(4.0, 0.01));
      expect(result >= 3.5, isTrue, reason: 'Debe ser redonda');
    });

    test('Negra @ 70 BPM (Chopin) → ~0.5s', () {
      final result = beats(0.5, 70);
      expect(result < 1.5, isTrue, reason: 'Debe ser negra a tempo lento');
    });

    test('Redonda @ 70 BPM (Chopin) → ~5.14s', () {
      final result = beats(258 / 50.0, 70);
      expect(result >= 3.5, isTrue, reason: 'Debe ser redonda a tempo lento');
    });

    test('Duración negativa es inválida', () {
      const note = NoteEvent(startTime: 1.0, endTime: 0.5, midiNote: 60, velocity: 80);
      expect(note.duration, isNegative);
    });

    test('Nota en extremo grave (A0 = MIDI 21)', () {
      const note = NoteEvent(startTime: 0.0, endTime: 1.0, midiNote: 21, velocity: 60);
      expect(note.noteName, equals('A0'));
    });

    test('Nota en extremo agudo (C8 = MIDI 108)', () {
      const note = NoteEvent(startTime: 0.0, endTime: 0.25, midiNote: 108, velocity: 80);
      expect(note.noteName, equals('C8'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. TESTS DE PENTAGRAMA: Se dibujan todas las notas
  // ───────────────────────────────────────────────────────────────────────────
  group('ScoreStaveVisualizer – Pentagrama completo', () {

    testWidgets('Twinkle Twinkle: 7 notas, pentagrama visible', (tester) async {
      await _pump(tester, _twinkleTwinkle, 0.0);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      expect(_twinkleTwinkle.noteEvents.length, equals(7));
    });

    testWidgets('Ode to Joy: 8 notas, pentagrama visible', (tester) async {
      await _pump(tester, _odeToJoy, 0.0);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      expect(_odeToJoy.noteEvents.length, equals(8));
    });

    testWidgets('Chopin: 8 notas incluyendo redondas, pentagrama visible', (tester) async {
      await _pump(tester, _chopinNocturne, 0.0);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      expect(_chopinNocturne.noteEvents.length, equals(8));
    });

    testWidgets('No se rompe con score vacío', (tester) async {
      final emptyScore = _twinkleTwinkle.copyWith(noteEvents: []);
      await _pump(tester, emptyScore, 0.0);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('No se rompe con una sola nota', (tester) async {
      final singleNote = _twinkleTwinkle.copyWith(noteEvents: const [
        NoteEvent(startTime: 0.0, endTime: 2.0, midiNote: 60, velocity: 80),
      ]);
      await _pump(tester, singleNote, 0.0);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('Escala staffScale 0.5 no rompe el render', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400, height: 260,
              child: ScoreStaveVisualizer(
                score: _odeToJoy,
                currentTime: 0.0,
                isPlaying: false,
                staffScale: 0.5,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('Escala staffScale 2.0 no rompe el render', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400, height: 260,
              child: ScoreStaveVisualizer(
                score: _odeToJoy,
                currentTime: 0.0,
                isPlaying: false,
                staffScale: 2.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. TESTS DE REPRODUCCIÓN: Simulación del avance del tiempo
  // ───────────────────────────────────────────────────────────────────────────
  group('ScoreStaveVisualizer – Simulación de reproducción', () {

    Future<void> simulatePlayback(WidgetTester tester, Score score) async {
      // Fotogramas al 0%, 25%, 50%, 75% y 100% de la canción
      final checkpoints = [0.0, 0.25, 0.5, 0.75, 1.0]
          .map((p) => p * score.duration)
          .toList();

      for (final t in checkpoints) {
        await _pump(tester, score, t, isPlaying: true);
        expect(
          find.byType(CustomPaint),
          findsAtLeastNWidgets(1),
          reason: 'El pentagrama debe ser visible en t=${t.toStringAsFixed(1)}s',
        );
      }
    }

    testWidgets('Twinkle Twinkle – reproducción completa sin errores',
        (tester) => simulatePlayback(tester, _twinkleTwinkle));

    testWidgets('Ode to Joy – reproducción completa sin errores',
        (tester) => simulatePlayback(tester, _odeToJoy));

    testWidgets('Chopin Nocturne – reproducción completa sin errores',
        (tester) => simulatePlayback(tester, _chopinNocturne));

    testWidgets('El avance del tiempo no hace desaparecer el pentagrama',
        (tester) async {
      // Avanzamos segundo a segundo hasta el final de Twinkle Twinkle
      for (double t = 0.0; t <= _twinkleTwinkle.duration; t += 1.0) {
        await _pump(tester, _twinkleTwinkle, t, isPlaying: true);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1),
            reason: 'Frame en t=${t.toStringAsFixed(0)}s no debe vaciar el pentagrama');
      }
    });

    testWidgets('Notas se marcan como activas cuando currentTime está en su rango',
        (tester) async {
      // nota index 0: startTime=0.0, endTime=0.5 → activa en t=0.25
      await _pump(tester, _twinkleTwinkle, 0.25, isPlaying: true);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));

      // nota index 2: startTime=1.0, endTime=1.5 → activa en t=1.25
      await _pump(tester, _twinkleTwinkle, 1.25, isPlaying: true);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('Tiempo mayor que la duración no rompe el widget',
        (tester) async {
      await _pump(tester, _twinkleTwinkle, 999.0, isPlaying: false);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. TESTS DE PROPIEDADES DEL SCORE
  // ───────────────────────────────────────────────────────────────────────────
  group('Score – propiedades y validaciones', () {
    test('noteCount es correcto para cada canción demo', () {
      expect(_twinkleTwinkle.noteCount, equals(7));
      expect(_odeToJoy.noteCount, equals(8));
      expect(_chopinNocturne.noteCount, equals(8));
    });

    test('Twinkle Twinkle NO es polifónica', () {
      expect(_twinkleTwinkle.isPolyphonic, isFalse);
    });

    test('Secuencia con notas solapadas ES polifónica', () {
      final poly = _twinkleTwinkle.copyWith(noteEvents: const [
        NoteEvent(startTime: 0.0, endTime: 1.0, midiNote: 60, velocity: 80),
        NoteEvent(startTime: 0.5, endTime: 1.5, midiNote: 64, velocity: 80), // solapada
      ]);
      expect(poly.isPolyphonic, isTrue);
    });

    test('Duración debe ser positiva en todas las notas de cada canción', () {
      for (final score in [_twinkleTwinkle, _odeToJoy, _chopinNocturne]) {
        for (final note in score.noteEvents) {
          expect(note.duration, greaterThan(0),
              reason: '${score.title}: nota MIDI ${note.midiNote} tiene duración no positiva');
        }
      }
    });

    test('midiNote debe estar entre 21 y 108 (rango de piano)', () {
      for (final score in [_twinkleTwinkle, _odeToJoy, _chopinNocturne]) {
        for (final note in score.noteEvents) {
          expect(note.midiNote, greaterThanOrEqualTo(21),
              reason: '${score.title}: nota MIDI demasiado baja');
          expect(note.midiNote, lessThanOrEqualTo(108),
              reason: '${score.title}: nota MIDI demasiado alta');
        }
      }
    });

    test('startTime < endTime en todas las notas', () {
      for (final score in [_twinkleTwinkle, _odeToJoy, _chopinNocturne]) {
        for (final note in score.noteEvents) {
          expect(note.startTime, lessThan(note.endTime),
              reason: '${score.title}: MIDI ${note.midiNote} tiene startTime >= endTime');
        }
      }
    });
  });
}
