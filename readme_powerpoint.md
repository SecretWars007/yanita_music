# Presentación Técnica: Yanita Music (Core AI & Architecture)
## Guía para Generación de Diapositivas

---

### Diapositiva 1: Portada
*   **Título:** Yanita Music: El futuro de la Transcripción Musical Automática (AMT)
*   **Subtítulo:** Una solución móvil avanzada basada en Flutter y Deep Learning.
*   **Imagen sugerida:** Un piano fusionándose con una onda de audio digital.

### Diapositiva 2: El Problema (The Challenge)
*   **Punto clave:** La conversión manual de audio a partituras es lenta y costosa.
*   **Limitación actual:** Las apps móviles suelen carecer de la potencia para procesar polifonía (múltiples notas) en tiempo real con precisión.
*   **Visión:** Democratizar el acceso a la escritura musical mediante IA local.

### Diapositiva 3: Arquitectura Técnica (Clean Architecture)
*   **Estructura:** Separación en 3 capas (Presentación, Dominio, Datos).
*   **Patrón de estado:** BLoC (Business Logic Component) para flujos de trabajo concurrentes.
*   **Beneficio:** Código robusto, testeable y desacoplado del hardware.

### Diapositiva 4: Procesamiento de Audio (Input Stage)
*   **FFmpeg Integration:** Normalización automática a WAV (16kHz, Mono).
*   **Mel Spectrogram:** Extracción de características espectrales (229 bins).
*   **Concepto:** Transformamos sonido en una representación visual que la IA puede interpretar.

### Diapositiva 5: El Cerebro (TFLite Inference)
*   **Modelo:** Onsets and Frames (basado en Google Magenta).
*   **Local Processing:** Inferencia 100% offline dentro del dispositivo para privacidad y velocidad.
*   **Optimización:** Procesamiento fragmentado por "chunks" para soportar audios largos sin agotar la RAM.

### Diapositiva 6: Algoritmo de Decodificación (Post-processing)
*   **Problema de los Onsets anchos:** Ruido que genera notas repetidas.
*   **Solución Yanita:** *Rising-Edge Detection* (Detección por flanco de subida) para capturar solo el ataque real de la nota.
*   **Estabilidad:** Implementación de un cap de seguridad de 10k notas para proteger la integridad de la base de datos.

### Diapositiva 7: Resultados y Exportación
*   **Formatos soportados:**
    *   **PDF:** Reporte visual del espectrograma.
    *   **MIDI:** Archivo digital para DAWs.
    *   **MusicXML:** Para edición profesional en MuseScore/Finale.
*   **Biblioteca Digital:** Almacenamiento local seguro en SQLite.

### Diapositiva 8: Próximos Pasos y Escalabilidad
*   **Mejora de Modelo:** Soporte para instrumentos más complejos.
*   **Cloud Sync:** Sincronización opcional de la biblioteca.
*   **UX Premium:** Una interfaz "State of the Art" diseñada para músicos profesionales.

---
*Fin de la estructura de presentación.*
