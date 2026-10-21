> **Nota:** este documento se fue ampliando por versiones. La primera tabla y las secciones 0.2–0.5 son históricas; el estado vigente (Echoes 0.6.0 / EchoesEngine 0.4.0) está en las secciones finales y en `README.md`. Cada versión corrige cosas de las anteriores.

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

---

# Actualización 0.2.0 — los 6 sistemas, punto por punto

| Sistema | Implementado (sin probar en juego) | No implementado y por qué |
|---|---|---|
| **1. Percepción** | `Senses.lua`: pistas direccionales desde la **posición real** de zombis que no ves (4–12 casillas, atenuadas por muros/puertas, con cooldown); incertidumbre posicional de los sonidos propios de noche (hasta ~3 casillas con presión alta); ruidos a tu espalda (el Director favorece fuentes detrás de ti cuando hay presión). `Weather`, `Body`, cabina de vehículo modulan lo que oyes. | "Pérdida de referencias en la oscuridad" visual: solo vía capa de pantalla (`Visual`, experimental). |
| **2. Interacción** | `Interaction.lua`: menú contextual **"Listen at the door"** (acción temporizada): tras unos segundos con el oído en la puerta oyes, amortiguados, los zombis reales detrás de ella (máx. 4); coste: quedarte quieto y hacer un ruido mínimo. | **Asomarte por esquinas/ventanas:** no hay API verificada de inclinación ni de cámara de Viewpoint; no se simula. |
| **3. IA zombi** | `ZombieAwareness.lua` (servidor/SP): un zombi que investigó un ruido y no encontró nada busca en hasta 3 habitaciones cercanas (`pathToLocationF` a casillas interiores aleatorias **junto a él**, sin conocer tu posición); presupuesto de 6 búsquedas por tick, 400 zombis escaneados, cooldown 90 s. Alarma lejana persistente que atrae con `addSound`. | Reacción en cadena urbana entre alarmas reales: depende de cómo propague el juego las alarmas de edificio (pendiente de observar). Rastreo avanzado: se deja al motor. |
| **4. Conducción** | `VehicleSense.lua`: amortiguación de cabina y enmascaramiento por velocidad; pista de punto ciego (zombi real cerca por detrás). | Retrovisores, lluvia sobre cristales, suciedad: sin técnica verificada (render propio / Viewpoint). La visibilidad por lluvia/niebla la sigue dando el juego. |
| **5. Mundo dinámico** | Alarma que dura horas y atrae zombis; **luces de actividad humana** (una lámpara lejana aparece encendida de noche y se apaga horas después, guardada en ModData); tiros lejanos tenues (sin atraer); historia "puerta cerrada por dentro" con golpes ocasionales (`Stories.lua`); decaimiento eléctrico por sala; goteras en salas deterioradas cuando llueve. | Rastros de evacuación, habitaciones de lucha: requieren colocar objetos; pendiente. |
| **6. Presencias** | Pasos, puertas, voces (si existe sonido), puerta entreabierta, luz que parpadea, **lugares cargados** (`Places.lua`: donde sufriste un pico de pánico, los fenómenos vuelven con más probabilidad), eco de lugar, memoria y cooldowns. **Siluetas**: `Visual.lua` dibuja una figura con rectángulos en el borde de la pantalla durante 0,7–1,6 s, desaparece si te giras hacia ella; no finge ser un objeto del mundo. | Figuras 3D en el mundo: sin técnica verificada. |

## Experimental y desactivado por defecto
`Visual` (adaptación a la luz/deslumbramiento con un panel transparente a pantalla completa) y `Apparitions` (siluetas). Riesgo a comprobar: que el panel **no bloquee clics del ratón**. Activar en Sandbox → ECHOES solo para probar.

---

# 0.4.0 — olfato, sangre, manada, miedo y mareo

## IA de zombis (servidor / un jugador): `Tracking.lua`
- **Rastro de olor.** Cada jugador deja puntos de su recorrido. La intensidad sube con **heridas sangrantes** (`getNumPartsBleeding`, hasta +0,45), **esfuerzo** (correr, +0,15) y algo de ropa mojada; **se desvanece** con el tiempo (≈25 min de juego en aire quieto) y mucho más rápido con **lluvia** (−70 %) y **viento** (−30 %).
- Un zombi **sin objetivo** que pasa cerca de un punto aún fresco (alcance 4–11 casillas según intensidad) camina por el rastro hacia puntos más nuevos. **Nunca recibe tu posición actual:** los puntos de menos de 1 minuto de juego están fuera de su alcance, así que sigue por dónde pasaste, no por dónde estás. Presupuesto de 5 zombis por pasada.
- **Alerta de manada.** Un zombi que persigue a un objetivo que ve atrae a vecinos inactivos (≤12 casillas) hacia **él** (los gemidos), no hacia ti. Presupuesto de 4.
- Un indicador `echoesBusy` por zombi evita que búsqueda, olor y manada se pisen.
- Todo se apaga/ajusta en Sandbox (`Scent`, `ScentStrength`, `PackAlert`). Con el nivel Java, el oído físico ya reduce lo que los zombis oyen tras muros.

## Tu personaje
- **Miedo** (`Fear.lua`): nivel 0–1 a partir de zombis visibles y persiguiéndote (datos del propio juego), salud baja, presión nocturna y sustos de eventos inexplicables. Se expresa como **latido del corazón** (más rápido con más miedo; busca el sonido real del juego) y, con la capa visual activada, **bordes oscuros que laten**. No toca PANIC/STRESS ni ninguna estadística vanilla.
- **Mareo** (`Dizzy.lua`): tras agotarte, con pérdida de sangre, frío profundo o sin dormir, usa el efecto nativo de "tripping" (`Stats.setTripping/setTrippingRotAngle`) con una onda lenta. **Desactivado por defecto** porque la unidad del ángulo y qué más hace el juego en ese estado no están verificados. **F8** (con Debug) lanza una demo de 6 s para comprobarlo. Si Viewpoint usa su propia cámara puede no verse.
- **Respiración** (v0.1.0), **temblor/frío** calculados, y oído algo reducido con pánico o falta de aliento.

## Qué sigue sin estar
Temblor visible de manos o del arma, cojera/tropiezos físicos (hay `setBumpType`, `setSlowFactor`… sin semántica verificada), visión borrosa real. Y la IA visual de zombis (conos, luz, sigilo), que requiere el nivel Java con datos del motor.

---

# 0.5.0 — individuos, lugares encantados y herramientas

- **Personalidad de zombi** (`ZombieUtil.personality`): cada zombi recibe de forma estable *olfato* (0,4–1,6: alcance y disposición a seguir el rastro), *persistencia* (cuántas habitaciones sigue buscando) y *audacia* (disposición a unirse a la persecución de otro). La multitud deja de comportarse como un solo animal.
- **Sangre en el suelo:** un zombi de buen olfato inactivo puede ir a una casilla cercana con sangre en el suelo (`haveBloodFloor`); cada casilla se "agota" 20 min de juego para no formar bucles con manchas viejas.
- **Lugares encantados con tema y etapa** (`Places.lua` + Director): al marcarse un lugar (pico de pánico) recibe un *tema* (pasos, puerta, golpes, voz, luz) y una *etapa* 0–4. Volver allí sube la etapa: más volumen, respuestas a los pocos segundos "a un lado" y, en etapas altas, **pasos que caminan hacia ti**. Tras la etapa 4 el fenómeno se calma y se apaga poco a poco.
- **Nuevo fenómeno de golpes** (`knock`) si el juego tiene un sonido de golpes.
- **Informe de estado y coste** (`Debug.lua`, F7): todo `Echoes.safe(...)` cuenta llamadas, tiempo medio/máximo y errores por módulo; también cada 6 h con Debug.
- **Corrección encontrada por pruebas aleatorias:** `math.atan2` no existe en todas las variantes de Lua; ahora se usa `Echoes.atan2`.
- Hecho notable del Javadoc: el juego **ya aplica** un desvío de 2–10 casillas al oír ruidos que no ve (`HEARING_UNSEEN_OFFSET_*`, mayor con lluvia fuerte) y tiene constantes de visión por oscuridad/niebla/lluvia; el nivel Java *añade* atenuación física, no sustituye eso.

---

# 0.6.0 — señales de radio, sordera, motor Java ampliado

- **Superviviente por radio** (`RadioSignals.lua`): una frecuencia oculta por mundo (`ZomboidRadio.getRandomFrequency`) por la que un grupo lejano transmite una historia de 8 mensajes (EN/ES) a lo largo de la partida, cada uno repetido 3 minutos de juego; más degradado con lluvia, viento y niebla (`scrambleString`). El jugador debe barrer el dial de una radio encendida. Sin marcadores ni aviso. Tras el mensaje 8, silencio. Todo por `ZomboidRadio.SendTransmission`; la semántica de alcance/`codes`/potencia no está verificada.
- **Sordera tras disparos** (`Body.lua` + `LoudPatch`): −60 % de oído para los sonidos de ECHOES durante 30 s y zumbido, salvo con protección auditiva.
- **EchoesEngine 0.4.0:** oído físico de zombis; visión de zombis (observa, sigilo opcional); ruido del jugador por carga (observa, opcional); detección de ruidos fuertes. Todo medible con `EchoesEngine_stats()`.
- **Infraestructura:** CI en GitHub (sintaxis Lua, humo con API simulada en 12 semillas, build y pruebas del JAR), traducciones ES/EN, informe F7, verificación cruzada con mods B42 reales.
