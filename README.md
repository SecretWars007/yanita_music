# 🎵 Yanita Music

**Transcriptor inteligente de música para piano** — Aplicación móvil Flutter que convierte archivos de audio (MP3/WAV) en partituras digitales utilizando inteligencia artificial completamente offline.

---

## 📋 Tabla de Contenidos

- [Descripción General](#-descripción-general)
- [Arquitectura de la Aplicación](#-arquitectura-de-la-aplicación)
- [Pipeline de Transcripción Musical](#-pipeline-de-transcripción-musical)
- [Estructura del Proyecto](#-estructura-del-proyecto)
- [Entidades de Dominio](#-entidades-de-dominio)
- [Gestión de Estado (BLoC)](#-gestión-de-estado-bloc)
- [Dependencias Principales](#-dependencias-principales)
- [Exportación de Formatos](#-exportación-de-formatos)
- [Base de Datos](#-base-de-datos)
- [Configuración y Ejecución](#-configuración-y-ejecución)

---

## 🎯 Descripción General

Yanita Music es una aplicación Flutter diseñada para transcribir música de piano a partir de archivos de audio. Utiliza un modelo de **TensorFlow Lite (TFLite)** basado en la arquitectura **Onsets and Frames** para realizar inferencia de IA directamente en el dispositivo, sin necesidad de conexión a internet.

### Características principales:
- 🎹 **Transcripción automática** — Convierte audio de piano a notas musicales
- 🧠 **IA Offline** — Modelo TFLite embebido para inferencia local en CPU
- 📊 **Espectrograma Mel** — Generación y visualización del espectrograma
- 📄 **Exportación múltiple** — PDF (espectrograma), MIDI, MusicXML
- 🎵 **Reproducción WAV** — Reproduce el audio convertido directamente
- 📚 **Biblioteca de partituras** — Almacenamiento local con SQLite
- 🔒 **Seguridad** — Almacenamiento seguro y encriptación de datos sensibles
- 📱 **Multi-plataforma** — Android (principal), con soporte puntual para Windows/Linux

---

## 🏗️ Arquitectura de la Aplicación

La aplicación sigue el patrón de **Clean Architecture** con tres capas bien definidas:

```
┌─────────────────────────────────────────────────────────┐
│                   PRESENTATION                          │
│  ┌─────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  Pages  │  │   BLoCs     │  │  Widgets / Theme    │ │
│  │ (9 pgs) │  │ (3 blocs)   │  │                     │ │
│  └────┬────┘  └──────┬──────┘  └─────────────────────┘ │
│       │              │                                  │
├───────┼──────────────┼──────────────────────────────────┤
│       │      DOMAIN  │                                  │
│  ┌────▼────┐  ┌──────▼──────┐  ┌─────────────────────┐ │
│  │Entities │  │  Use Cases  │  │  Repositories       │ │
│  │(6 ents) │  │ (11 cases)  │  │  (5 interfaces)     │ │
│  └─────────┘  └──────┬──────┘  └──────┬──────────────┘ │
│                      │                │                 │
├──────────────────────┼────────────────┼─────────────────┤
│                DATA  │                │                 │
│  ┌───────────────────▼────────────────▼───────────────┐ │
│  │              Repository Implementations            │ │
│  ├─────────────────┬──────────────────────────────────┤ │
│  │   Datasources   │         Native Bridge            │ │
│  │  ┌───────────┐  │  ┌──────────────────────────┐    │ │
│  │  │  SQLite   │  │  │  FFmpeg (audio)           │    │ │
│  │  │ (local)   │  │  │  TFLite (inferencia IA)   │    │ │
│  │  └───────────┘  │  │  C++ FFI (espectrograma)  │    │ │
│  │                 │  └──────────────────────────────┘  │ │
│  └─────────────────┴──────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Principios de diseño:
- **Separación de responsabilidades** — Cada capa tiene una función clara
- **Inversión de dependencias** — Domain define interfaces, Data las implementa
- **Inyección de dependencias** — Via `get_it` + `injectable`
- **Gestión reactiva de estado** — BLoC + `flutter_bloc`
- **Entidades inmutables** — Via `equatable` y `copyWith()`

---

## 🔬 Pipeline de Transcripción Musical

El proceso de transcripción sigue un pipeline de **4 etapas secuenciales**, cada una verificable e independiente:

```
┌──────────────┐    ┌──────────────────┐    ┌────────────────┐    ┌──────────────────┐
│  1. AUDIO    │───▶│ 2. ESPECTROGRAMA │───▶│ 3. INFERENCIA  │───▶│ 4. PARTITURA     │
│  MP3 → WAV   │    │  WAV → Mel Spec   │    │  TFLite Model  │    │  Notes → Score   │
└──────┬───────┘    └──────┬───────────┘    └──────┬─────────┘    └──────┬───────────┘
       │                   │                       │                     │
   FFmpeg Kit          C++ FFI /              TFLite GPU/CPU        NoteEvent → 
   Conversión         Float32List             Onsets & Frames       MIDI/MusicXML/PDF
```

### Etapa 1: Conversión de Audio (MP3 → WAV)
- **Herramienta**: `ffmpeg_kit_flutter_new_audio`
- **Proceso**: Convierte cualquier archivo de audio (MP3, M4A, etc.) a formato WAV mono 16kHz
- **Salida**: Archivo `.wav` almacenado en el directorio temporal de la app
- **Estado BLoC**: `AudioProcessing`

### Etapa 2: Generación de Espectrograma Mel
- **Herramienta**: Procesamiento FFI nativo (C++) o Dart puro
- **Proceso**:
  1. Lee el archivo WAV crudo
  2. Aplica ventana Hanning y FFT (Fast Fourier Transform)
  3. Genera filterbank Mel con `N` bandas (configurado por el modelo)
  4. Produce un arreglo `Float32List` plano: `[numFrames × numMelBins]`
- **Telemetría**: Registra frames totales, rango de valores, media
- **Salida**: `AudioFeatures` con `melSpectrogram`, `numFrames`, `numMelBins`, `sampleRate`
- **Estado BLoC**: `AudioProcessing` (segunda fase)

### Etapa 3: Inferencia de IA (TFLite — Onsets and Frames)
- **Modelo**: TensorFlow Lite (archivo `.tflite` en `assets/models/`)
- **Arquitectura del modelo**:
  - **Input**: Tensor 1D plano `[17920]` = `32 frames × 560 mel bins`, o 3D `[1, 32, melBins]`
  - **Outputs**: 4 tensores 3D de forma `[1, 32, 88]`:
    - `Output[0]`: **Onsets** — Probabilidad de inicio de nota
    - `Output[1]`: **Frames** — Probabilidad de nota activa por frame
    - `Output[2]`: **Velocities** — Velocidad estimada (dinámica)
    - `Output[3]`: Tensor auxiliar
- **Procesamiento por bloques**: La canción se divide en chunks de `modelFrames` (32 frames)
  - Cada chunk se alimenta al modelo secuencialmente
  - Los resultados se acumulan en buffers globales `flatOnsets`, `flatFrames`, `flatVelocities`
  - Padding de silencio (-100.0) para el último bloque incompleto
- **Detección de forma dinámica**: El código detecta automáticamente si el input es 1D, 2D o 3D
- **Decodificación de notas**:
  - Umbral de onset (>0.5) para detectar inicio de nota
  - Umbral de frame (>0.3) para mantener la nota activa
  - Velocidad MIDI (0-127) extraída del tensor de velocidades
  - Conversión: frame index → tiempo en segundos, nota index → MIDI pitch (21-108)
- **Salida**: `List<NoteEvent>` con `startTime`, `endTime`, `midiNote`, `velocity`, `confidence`
- **Estado BLoC**: `Transcribing`

### Etapa 4: Generación de Partitura
- **Proceso**:
  1. Los `NoteEvent` se empaquetan en una entidad `Score`
  2. Se genera el PDF del espectrograma (vía `pdf` + `printing`)
  3. Se almacenan en SQLite: audio path, WAV path, PDF path, notas, MusicXML, timestamp
  4. Se pueden exportar como MIDI (Format 0) y MusicXML (3.1 Partwise)
- **Estado BLoC**: `TranscriptionSuccess` → (usuario confirma) → `TranscriptionSaved`

---

## 📁 Estructura del Proyecto

```
lib/
├── main.dart                          # Entry point
├── injection_container.dart           # Configuración de get_it/injectable
│
├── core/                              # Utilidades transversales
│   ├── constants/
│   │   ├── app_constants.dart         # dbVersion, dbName, rutas de modelos
│   │   ├── db_constants.dart          # Nombres de tablas y columnas
│   │   └── version_constants.dart     # appVersion, buildNumber, fullVersion
│   ├── error/                         # Excepciones custom (DatabaseException, etc.)
│   ├── mixins/                        # Mixins reutilizables
│   ├── security/                      # Almacenamiento seguro, encriptación
│   ├── usecases/                      # Clase base UseCase<T, Params>
│   └── utils/
│       └── logger.dart                # AppLogger (sistema de logs interno)
│
├── domain/                            # Lógica de negocio pura (sin dependencias Flutter)
│   ├── entities/
│   │   ├── audio_features.dart        # Espectrograma Mel + metadata
│   │   ├── log_entry.dart             # Entrada de log con timestamp
│   │   ├── midi_event.dart            # Eventos MIDI individuales
│   │   ├── note_event.dart            # Nota musical (pitch, onset, offset, velocity)
│   │   ├── score.dart                 # Partitura completa con todas las notas
│   │   └── song.dart                  # Canción del cancionero
│   ├── repositories/                  # Interfaces (contratos)
│   │   ├── audio_repository.dart      # Procesamiento de audio
│   │   ├── log_repository.dart        # Persistencia de logs
│   │   ├── score_repository.dart      # CRUD de partituras
│   │   ├── songbook_repository.dart   # Gestión del cancionero
│   │   └── transcription_repository.dart  # Pipeline de transcripción
│   └── usecases/
│       ├── add_song_usecase.dart       # Agregar canción al cancionero
│       ├── delete_score_usecase.dart   # Eliminar partitura
│       ├── evaluate_metrics_usecase.dart  # Métricas de calidad
│       ├── export_midi_usecase.dart    # Exportar a MIDI
│       ├── export_musicxml_usecase.dart  # Exportar a MusicXML
│       ├── get_scores_usecase.dart     # Obtener todas las partituras
│       ├── get_songs_usecase.dart      # Obtener todas las canciones
│       ├── process_audio_usecase.dart  # Procesar audio (MP3→WAV→Mel)
│       ├── save_score_usecase.dart     # Guardar partitura en BD
│       ├── transcribe_audio_usecase.dart  # Ejecutar transcripción completa
│       └── update_score_usecase.dart   # Actualizar partitura existente
│
├── data/                              # Implementaciones concretas
│   ├── datasources/
│   │   ├── local/
│   │   │   └── database_helper.dart   # SQLite: init, migrations, CRUD
│   │   └── native/                    # Puente FFI con código C++ nativo
│   ├── models/                        # Modelos de datos (con serialización)
│   │   └── note_event_model.dart      # NoteEvent con fromJson/toJson
│   └── repositories/
│       ├── audio_repository_impl.dart
│       ├── log_repository_impl.dart
│       ├── score_repository_impl.dart
│       ├── songbook_repository_impl.dart
│       └── transcription_repository_impl.dart  # ⭐ Pipeline principal
│
├── presentation/                      # UI y gestión de estado
│   ├── blocs/
│   │   ├── score_library/             # ScoreLibraryBloc — biblioteca de partituras
│   │   ├── songbook/                  # SongbookBloc — cancionero
│   │   └── transcription/             # TranscriptionBloc — pipeline de transcripción
│   ├── pages/
│   │   ├── splash_screen.dart         # Pantalla de inicio con versión
│   │   ├── login_page.dart            # Autenticación
│   │   ├── home_page.dart             # Dashboard principal (últimas partituras)
│   │   ├── transcription_page.dart    # ⭐ Módulo de transcripción
│   │   ├── score_library_page.dart    # Biblioteca completa
│   │   ├── score_detail_page.dart     # Detalle de partitura
│   │   ├── songbook_page.dart         # Cancionero
│   │   ├── log_viewer_page.dart       # Visor de logs (debug)
│   │   └── database_viewer_page.dart  # Visor de BD (debug)
│   ├── theme/                         # Tema visual (colores, tipografía)
│   └── widgets/                       # Componentes reutilizables
│
assets/
├── audio/                             # Archivos de audio de demo
├── database/                          # yanitadb.db preempaquetada
├── fonts/                             # Tipografías (MusicSymbols)
├── images/                            # Logos e imágenes
├── models/                            # Modelo TFLite (.tflite)
├── scores/                            # Partituras MusicXML de ejemplo
└── training_data/                     # Datos de entrenamiento
```

---

## 📦 Entidades de Dominio

| Entidad | Descripción | Campos clave |
|---------|-------------|--------------|
| `NoteEvent` | Nota musical individual | `startTime`, `endTime`, `midiNote` (21-108), `velocity` (0-127), `confidence` |
| `Score` | Partitura completa | `noteEvents[]`, `duration`, `tempo`, `midiData`, `musicXml`, `wavPath`, `pdfPath` |
| `Song` | Canción del cancionero | `title`, `audioPath`, `duration` |
| `AudioFeatures` | Representación espectral | `melSpectrogram` (Float32List), `numFrames`, `numMelBins`, `sampleRate` |
| `MidiEvent` | Evento MIDI crudo | `type`, `channel`, `note`, `velocity`, `timestamp` |
| `LogEntry` | Entrada de log | `message`, `level`, `timestamp`, `tag` |

---

## 🔄 Gestión de Estado (BLoC)

### TranscriptionBloc (Principal)
Gestiona todo el ciclo de vida de la transcripción:

```
TranscriptionInitial
    ↓ (usuario selecciona archivo)
AudioFileSelected
    ↓ (StartTranscription event)
AudioProcessing  ← Paso 1: MP3→WAV + Espectrograma
    ↓
Transcribing     ← Paso 2: Inferencia TFLite
    ↓
TranscriptionSuccess ← Resultado con noteEvents[]
    ↓ (usuario presiona "OK - Continuar")
SavingTranscription
    ↓
TranscriptionSaved ← Guardado en SQLite
```

### ScoreLibraryBloc
- Carga y gestiona la biblioteca de partituras desde SQLite
- Eventos: `LoadScores`, `DeleteScore`, `UpdateScore`

### SongbookBloc
- Gestiona el cancionero de archivos de audio
- Eventos: `LoadSongs`, `AddSong`, `DeleteSong`

---

## 📚 Dependencias Principales

| Categoría | Paquete | Uso |
|-----------|---------|-----|
| **Estado** | `flutter_bloc`, `bloc`, `equatable` | Patrón BLoC para gestión reactiva |
| **DI** | `get_it`, `injectable` | Inyección de dependencias |
| **BD** | `sqflite`, `sqflite_common_ffi`, `sqlite3_flutter_libs` | SQLite local |
| **IA** | `tflite_flutter` | Inferencia TFLite offline |
| **Audio** | `ffmpeg_kit_flutter_new_audio`, `just_audio`, `record` | Conversión, reproducción, grabación |
| **Archivos** | `file_picker`, `share_plus`, `path_provider` | Selección, compartir, rutas |
| **Seguridad** | `flutter_secure_storage`, `encrypt`, `crypto` | Almacenamiento seguro |
| **UI** | `google_fonts`, `flutter_svg`, `lottie` | Tipografía, SVG, animaciones |
| **PDF** | `pdf`, `printing` | Generación de PDF del espectrograma |
| **XML** | `xml` | Parsing de MusicXML |

---

## 📤 Exportación de Formatos

### PDF (Espectrograma)
- Genera un informe visual del espectrograma Mel
- Se comparte vía `share_plus`
- Verificación de existencia del archivo antes de compartir

### MIDI (Format 0)
- Archivo `.mid` estándar compatible con cualquier DAW
- Tempo: 120 BPM, 480 ticks por beat
- Notas ordenadas por tiempo de inicio con delta-time variable-length

### MusicXML (3.1 Partwise)
- Archivo `.musicxml` compatible con MuseScore, Finale, Sibelius
- Agrupación automática por compases (4/4 a 120 BPM)
- Notación correcta de pitch con alteraciones (sostenidos)

---

## 🗄️ Base de Datos

SQLite local con versionamiento automático (`dbVersion = 17`):

### Tablas principales:
- **scores** — Partituras transcritas (ID, título, notas, paths, timestamps)
- **songs** — Cancionero de archivos de audio

### Migración y Reset:
- Versionamiento vía `SharedPreferences` (`last_db_version`)
- Reset forzado al actualizar: borra la BD local y crea una nueva vacía
- No se copia la BD preempaquetada de assets durante reset (evita datos residuales)

---

## 🚀 Configuración y Ejecución

### Requisitos previos
- Flutter SDK ≥ 3.11.1
- Android SDK (para compilación móvil)
- NDK para componentes nativos C++

### Instalación
```bash
# Clonar el repositorio
git clone <repo-url>
cd yanita_music

# Instalar dependencias
flutter pub get

# Verificar que no hay errores
flutter analyze

# Ejecutar en modo debug
flutter run

# Compilar APK de producción
flutter build apk --release --no-tree-shake-icons
```

### Estructura de Assets requeridos
```
assets/
├── models/         # Colocar el archivo .tflite del modelo aquí
├── database/       # yanitadb.db (esquema preempaquetado)
└── audio/          # Archivos de audio de ejemplo (opcionales)
```

---

## 📊 Versión Actual

| Campo | Valor |
|-------|-------|
| **Versión** | 1.2.0 |
| **Build** | 50 |
| **DB Version** | 17 |
| **SDK** | Flutter 3.11.1 |
| **Última actualización** | 2026-03-23 |

---

## 📄 Licencia

Proyecto privado — Todos los derechos reservados.

---

*Desarrollado con ❤️ usando Flutter y TensorFlow Lite*
