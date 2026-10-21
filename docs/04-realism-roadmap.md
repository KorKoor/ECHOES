# Hoja de ruta de realismo — estado real de los 12 puntos

Versión de código: Echoes 0.1.0. **Nada se ha ejecutado en el juego.** "Implementado" significa: escrito, con sintaxis Lua válida, usando métodos que existen en el Javadoc 42.20.0; no que funcione.

| # | Sistema | Estado | Qué hay | Qué falta / límite técnico |
|---|---|---|---|---|
| 1 | Cuerpo humano | **Parcial** | `Body.lua`: respiración agitada al agotarse (resuelve el sonido real del juego), recuperación gradual tras correr, temblor/frío calculados (`tremor`, `cold`), oído algo reducido con pánico o falta de aliento (solo para sonidos de ECHOES). Sin HUD. | Mareo, visión borrosa y manos temblorosas **no** se implementan: Lua no puede sacudir cámara ni brazos; necesitan Viewpoint/Java o `SearchMode` (sin verificar). No se fingen. |
| 2 | Propagación acústica | **Parcial** | `Acoustics.lua`: distancia, muros/puertas cerradas (`isBlockedTo`), pisos, interior/exterior, lluvia/viento. `WorldEvents.lua`: alarma lejana que dura horas y atrae zombis con `addSound` (el motor decide quién oye; nadie sabe dónde estás). | Reverberación y suelo distinto por pisada: sin API verificada (requiere parámetros FMOD por emisor, `setParameterValueByName`, por probar). Reacción en cadena de alarmas urbanas: pendiente de ver cómo el juego propaga alarmas. |
| 3 | Electricidad que falla | **Parcial** | `RoomDecay.lua`: con los días, cada vez más lámparas encontradas apagadas o con parpadeo al entrar (determinista por sala, persistente en ModData, solo la sala actual). | Circuitos por zona, generadores con mantenimiento y consecuencias en neveras: no iniciados (`IsoGenerator` tiene combustible y condición; vanilla ya gestiona parte). |
| 4 | Clima | **Parcial** | `Weather.lua`: lluvia/viento enmascaran sonidos; exposición (frío, mojado) alimenta la presión psicológica. Se reutiliza el clima vanilla (ropa mojada, frío). | Niebla/tormenta sobre visión y conducción: dependen de 7 y 12. |
| 5 | Conciencia espacial 1ª persona | **No iniciado** | — | Viewpoint no publica API de cámara; no hay ángulo de visión modificable desde Lua verificado. Spike pendiente: leer su documentación/código. |
| 6 | Deterioro de lugares | **No iniciado** | (RoomDecay es el patrón a reutilizar: función del tiempo + hash + ModData) | Fugas, humedad, suciedad: requieren crear/modificar objetos; evaluar tras validar RoomDecay. Comida: vanilla ya la pudre. |
| 7 | Vehículos | **No iniciado** | — | `BaseVehicle` expone motor, luces, batería, `engineDoStartingFailed`; retrovisores/suciedad en cristal: no verificados. |
| 8 | Objetos que cuentan historias | **No iniciado** | — | Necesita colocar objetos/cadáveres; planificar como "plantillas" aplicadas al cargar edificios, tras validar RoomDecay. |
| 9 | Psicología y aislamiento | **Implementado (opcional)** | `Psyche.lua`: presión 0–1 desde fatiga, estrés, aislamiento (14 días), oscuridad, exposición, cordura y trauma configurable. Solo sube la frecuencia de fenómenos ambiguos. Sin daño ni penalización, sin lenguaje de violencia/locura. | Calibrar con partidas reales. |
| 10 | Fantasmas / inexplicable | **Parcial** | Director: pasos escalonados, puertas, voz (si el juego tiene un sonido adecuado), puerta que aparece entreabierta, luz que parpadea, eco de lugar, cooldowns, memoria. Todo con posible explicación natural. | Figuras/siluetas visuales: sin técnica verificada (capa 2D o entidad); queda para después del probe. |
| 11 | Mundo persistente | **Parcial** | Alarma lejana persistente en `ModData` (dura horas, atrae zombis); decaimiento por sala bajo demanda. | Simulación por zonas de recursos/lugares: pendiente. |
| 12 | Percepción visual imperfecta | **No iniciado** | — | Adaptación a la luz, deslumbramiento, polvo: requieren post-proceso; con shader packs de Viewpoint puede no verse. Evaluar `SearchMode` y capa 2D tras el probe. |

## Orden propuesto tras las pruebas
1. Corregir lo que falle del probe y de Echoes 0.1.0.
2. Validar RoomDecay → extender a 6 y 8 (mismo patrón).
3. Leer la API de Viewpoint → decidir 5, 7, 12.
4. Calibrar 1, 9 y 10 con tus impresiones de juego.
