import 'package:yanita_music/domain/entities/score.dart';
import 'package:yanita_music/domain/entities/note_event.dart';

/// Utility class to generate demo scores for testing and onboarding.
class DemoScoreGenerator {
  DemoScoreGenerator._();

  /// Genera la melodía completa de "Ode to Joy" (Himno a la Alegría) en Do Mayor.
  static Score generateOdeToJoy() {
    final now = DateTime.now();
    final List<NoteEvent> notes = [];

    // Melodía principal A (E E F G | G F E D | C C D E | E D D)
    void addA(double start) {
      notes.addAll([
        _note(start + 0.0, start + 0.5, 64),
        _note(start + 0.5, start + 1.0, 64),
        _note(start + 1.0, start + 1.5, 65),
        _note(start + 1.5, start + 2.0, 67),
        _note(start + 2.0, start + 2.5, 67),
        _note(start + 2.5, start + 3.0, 65),
        _note(start + 3.0, start + 3.5, 64),
        _note(start + 3.5, start + 4.0, 62),
        _note(start + 4.0, start + 4.5, 60),
        _note(start + 4.5, start + 5.0, 60),
        _note(start + 5.0, start + 5.5, 62),
        _note(start + 5.5, start + 6.0, 64),
        _note(start + 6.0, start + 6.75, 64),
        _note(start + 6.75, start + 7.0, 62),
        _note(start + 7.0, start + 8.0, 62),
      ]);
    }

    // Melodía principal A' (Variación final en Do)
    void addAPrime(double start) {
      notes.addAll([
        _note(start + 0.0, start + 0.5, 64),
        _note(start + 0.5, start + 1.0, 64),
        _note(start + 1.0, start + 1.5, 65),
        _note(start + 1.5, start + 2.0, 67),
        _note(start + 2.0, start + 2.5, 67),
        _note(start + 2.5, start + 3.0, 65),
        _note(start + 3.0, start + 3.5, 64),
        _note(start + 3.5, start + 4.0, 62),
        _note(start + 4.0, start + 4.5, 60),
        _note(start + 4.5, start + 5.0, 60),
        _note(start + 5.0, start + 5.5, 62),
        _note(start + 5.5, start + 6.0, 64),
        _note(start + 6.0, start + 6.75, 62),
        _note(start + 6.75, start + 7.0, 60),
        _note(start + 7.0, start + 8.0, 60),
      ]);
    }

    // Puente B (D D E C | D (E F) E C | D (E F) E D | C D G)
    void addB(double start) {
      notes.addAll([
        _note(start + 0.0, start + 0.5, 62),
        _note(start + 0.5, start + 1.0, 62),
        _note(start + 1.0, start + 1.5, 64),
        _note(start + 1.5, start + 2.0, 60),
        _note(start + 2.0, start + 2.5, 62),
        _note(start + 2.5, start + 2.75, 64),
        _note(start + 2.75, start + 3.0, 65),
        _note(start + 3.0, start + 3.5, 64),
        _note(start + 3.5, start + 4.0, 60),
        _note(start + 4.0, start + 4.5, 62),
        _note(start + 4.5, start + 4.75, 64),
        _note(start + 4.75, start + 5.0, 65),
        _note(start + 5.0, start + 5.5, 64),
        _note(start + 5.5, start + 6.0, 62),
        _note(start + 6.0, start + 6.5, 60),
        _note(start + 6.5, start + 7.0, 62),
        _note(start + 7.0, start + 8.0, 55),
      ]);
    }

    // Estructura: A - A - B - A'
    addA(0.0);
    addA(8.0);
    addB(16.0);
    addAPrime(24.0);

    return Score(
      id: 'demo-ode-to-joy',
      title: 'HIMNO A LA ALEGRÍA (Completo)',
      audioPath: 'assets/audio/ode_to_joy.mp3',
      noteEvents: notes,
      duration: 32.0,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Genera "Twinkle Twinkle Little Star" completo (A-B-A).
  static Score generateTwinkleTwinkle() {
    final now = DateTime.now();
    final List<NoteEvent> notes = [];

    // Frase A (C C G G A A G)
    void addA(double start) {
      notes.addAll([
        _note(start + 0.0, start + 0.5, 60),
        _note(start + 0.5, start + 1.0, 60),
        _note(start + 1.0, start + 1.5, 67),
        _note(start + 1.5, start + 2.0, 67),
        _note(start + 2.0, start + 2.5, 69),
        _note(start + 2.5, start + 3.0, 69),
        _note(start + 3.0, start + 4.0, 67),
      ]);
    }

    // Frase B (F F E E D D C)
    void addB(double start) {
      notes.addAll([
        _note(start + 0.0, start + 0.5, 65),
        _note(start + 0.5, start + 1.0, 65),
        _note(start + 1.0, start + 1.5, 64),
        _note(start + 1.5, start + 2.0, 64),
        _note(start + 2.0, start + 2.5, 62),
        _note(start + 2.5, start + 3.0, 62),
        _note(start + 3.0, start + 4.0, 60),
      ]);
    }

    // Frase C - Middle (G G F F E E D)
    void addC(double start) {
      notes.addAll([
        _note(start + 0.0, start + 0.5, 67),
        _note(start + 0.5, start + 1.0, 67),
        _note(start + 1.0, start + 1.5, 65),
        _note(start + 1.5, start + 2.0, 65),
        _note(start + 2.0, start + 2.5, 64),
        _note(start + 2.5, start + 3.0, 64),
        _note(start + 3.0, start + 4.0, 62),
      ]);
    }

    // Estructura: A B (Twinkle) - C C (Middle) - A B (Twinkle)
    addA(0.0);
    addB(4.0);
    addC(8.0);
    addC(12.0);
    addA(16.0);
    addB(20.0);

    return Score(
      id: 'demo-twinkle',
      title: 'TWINKLE TWINKLE LITTLE STAR',
      audioPath: 'assets/audio/twinkle_twinkle.mp3',
      noteEvents: notes,
      duration: 24.0,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Genera una parte realista del Nocturno Op.9 No.2 de Chopin.
  static Score generateChopinNocturne() {
    final now = DateTime.now();
    final List<NoteEvent> notes = [];

    // Tema Principal en Mi bemol Mayor (Eb)
    // Bb | G F Eb | D Eb F | Bb...
    // Mano Derecha (Melodía)
    notes.addAll([
      _note(0.0, 1.0, 58), // Bb
      _note(1.0, 2.0, 67), // G
      _note(2.0, 2.5, 65), // F
      _note(2.5, 3.0, 63), // Eb
      _note(3.0, 3.5, 62), // D
      _note(3.5, 4.0, 63), // Eb
      _note(4.0, 4.5, 65), // F
      _note(4.5, 6.0, 58), // Bb

      _note(6.0, 7.0, 67), // G
      _note(7.0, 7.5, 65), // F
      _note(7.5, 8.0, 63), // Eb
      _note(8.0, 9.0, 70), // Bb (octava arriba)
      _note(9.0, 10.0, 75), // Eb high
      _note(10.0, 11.0, 74), // D high
      _note(11.0, 12.0, 72), // C high
      _note(12.0, 14.0, 70), // Bb high
    ]);

    // Mano Izquierda (Acompañamiento - Bajos y Acordes)
    // Simplificado para el demo pero polifónico
    for (int i = 0; i < 4; i++) {
      final double offset = i * 4.0;
      notes.add(_note(offset + 0.0, offset + 1.0, 39)); // Eb bajo
      notes.add(_note(offset + 1.0, offset + 1.5, 51)); // Acorde
      notes.add(_note(offset + 1.0, offset + 1.5, 55));
      notes.add(_note(offset + 1.0, offset + 1.5, 58));

      notes.add(_note(offset + 2.0, offset + 3.0, 43)); // G bajo
      notes.add(_note(offset + 3.0, offset + 3.5, 55)); // Acorde
      notes.add(_note(offset + 3.0, offset + 3.5, 58));
      notes.add(_note(offset + 3.0, offset + 3.5, 62));
    }

    // Repetir un poco más para que dure
    final List<NoteEvent> fullNotes = [];
    fullNotes.addAll(notes);
    // Añadimos una sección final dramática
    const double s = 16.0;
    fullNotes.addAll([
      _note(s + 0.0, s + 1.0, 75),
      _note(s + 1.0, s + 2.0, 77),
      _note(s + 2.0, s + 4.0, 79), // Climax
    ]);

    return Score(
      id: 'demo-chopin',
      title: 'CHOPIN - NOCTURNE OP.9 NO.2',
      audioPath: 'assets/audio/chopin_nocturne_op9_2.mp3',
      noteEvents: fullNotes,
      duration: 20.0,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Genera scores genéricos si es necesario
  static Score generateGeneric(
    String id,
    String title, [
    String fakeAudioPath = '',
  ]) {
    return generateTwinkleTwinkle(); // Reusamos el de Twinkle como genérico de calidad
  }

  static NoteEvent _note(double start, double end, int pitch) {
    return NoteEvent(
      startTime: start,
      endTime: end,
      midiNote: pitch,
      velocity: 85,
    );
  }
}
