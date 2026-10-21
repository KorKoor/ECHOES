# Plan de pruebas para mañana (nada de esto se ha ejecutado aún)

## Paso 1 — EchoesProbe
1. Copiar `EchoesProbe/` a `~/Zomboid/mods/`. Activar en partida de un jugador; entrar en un edificio.
2. Esperar ~5 s y enviar las líneas `[EchoesProbe]` de `~/Zomboid/console.txt`.

## Paso 2 — Prototipo Echoes (copiar `Echoes/` a `~/Zomboid/mods/`)
1. Nueva partida (o una existente) con el mod activo; en Sandbox → página ECHOES activar **Debug logging**.
2. Buscar `[Echoes] v0.0.2 started` en `console.txt`. Si no aparece: error de carga, enviar el log.
3. Pulsar **F9** dentro de un edificio de noche: debe oírse un sonido a 6–12 casillas y aparecer `phenomenon fired`. Si sale `no candidate sound could be played`, los nombres de `Director.soundCandidates` no existen: enviar el log.
4. Esperar 1 h de juego con `Frequency=4`: sin errores `[Echoes][ERROR]`.
5. Desactivar **Enable ECHOES**: ningún fenómeno, sin errores.

## Paso 3 — Compatibilidad con Viewpoint y shaders
Repetir el paso 2 con: (a) sin Viewpoint, (b) Viewpoint sin shader pack, (c) con BSL, (d) con Photon. Anotar si el sonido se oye y si hay errores.

## Hipótesis a confirmar
- Nombres de sonidos vanilla; `emitter:playSound`; `CharacterStat.SANITY` y su rango; `EveryTenMinutes`, `OnKeyPressed`, `Keyboard.KEY_F9`; claves de `sandbox-options.txt` y traducciones B42.

## Novedades v0.0.2 a comprobar
- **Puertas:** el sonido de puerta debe venir de una casilla que realmente tiene una puerta (F9 varias veces; log `phenomenon fired: door`).
- **Pasos:** 4–7 pasos espaciados ~0,5 s, avanzando por casillas transitables (`footsteps`). Si no suenan, `FootstepsIndoor`/`ZombieFootstep` no existen: enviar log.
- **Acústica:** detrás de una pared o con puerta cerrada el sonido debe oírse más bajo (`Acoustics.factor`); en otro piso, aún más; con lluvia fuerte en exterior, más bajo.
- **Eco de lugar:** con varias activaciones (F9) alguna debe marcar `(callback)` y repetirse en un lugar anterior (tras >3 h de juego del anterior).
- Hipótesis nuevas [V]: `emitter:setVolume(handle, v)`, `setPitch`, `IsoGridSquare:isBlockedTo`, `getDoor(bool)`, `isFree(false)`, `isCouldSee`.

## Novedades v0.1.0 a comprobar (además de lo anterior)
**Sonidos:** los candidatos ya se filtran con `GameSounds.isKnownSound`; si hay `sound discovery unavailable` en el log, avisar. El probe vuelca palabras clave de sonidos reales (`sounds[breath]`, `sounds[footstep]`, `sounds[alarm]`…): enviar esas líneas para fijar nombres.
**Cuerpo:** correr hasta agotarte → respiración agitada que se calma al descansar (activar Debug: `breathing:` en el log). Con pánico alto, `Body` reduce un poco el volumen de los sonidos de ECHOES.
**Psicología:** con Debug aparece `pressure x.xx (...)` cada 10 min de juego; subir con fatiga/estrés/noche/frío.
**Fenómenos:** F9 repetidamente → `door_ajar` (una puerta cerrada y fuera de vista aparece abierta) y `light_flicker` (lámpara cercana parpadea y vuelve o queda apagada). Solo SP/host.
**Decaimiento:** en una partida con >10 días (usa Debug de Zomboid para avanzar el tiempo), entrar en habitaciones con lámparas: algunas apagadas, otras parpadean al entrar. Repetir en la misma sala: no debe cambiar más hasta cruzar 25/45 días.
**Alarma lejana:** con `Frequency=4` esperar horas de juego: `distant alarm started at x,y`, alarma tenue direccional y, a lo largo de las horas, zombis acercándose a esa zona. Si aparece `addSound failed`, enviar el log.
**Probe:** nuevas líneas (`room light switches`, `hydro power`, `endurance/fatigue ranges`, `running flags`, `thermoregulator core`).
