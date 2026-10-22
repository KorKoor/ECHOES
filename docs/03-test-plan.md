# Plan de pruebas (versión actual: Echoes 0.6.0 · EchoesEngine 0.4.0)

> Nada de lo siguiente se ha ejecutado aún en el juego. Cada paso dice **qué enviar** (líneas de `~/Zomboid/console.txt`, a partir de aquí `console.txt`). Haz los pasos en orden: cada fase desbloquea a la siguiente.

## 0. Instalación
1. Copia `Echoes/`, `EchoesProbe/` y (opcional, requiere ZombieBuddy) `EchoesEngine/` a `~/Zomboid/mods/`. Cada carpeta contiene `42/mod.info`.
2. Para el reconocimiento del motor, lanza ZombieBuddy con `experimental` (Windows `-agentlib:zbNative=experimental --`; Linux/macOS `-javaagent:ZombieBuddy.jar=experimental --`).
3. Nueva partida de un jugador (o una existente) con esos mods activados. ZombieBuddy pedirá aprobar el JAR de `EchoesEngine`: aceptar.
4. Sandbox → página **ECHOES** → activar **Debug logging**.

## 1. Probe (lo más importante)
1. Dentro de un edificio, espera ~5 s: se imprimen líneas `[EchoesProbe]` (OK/FAIL por llamada, volcado de sonidos reales por palabra clave, eventos existentes, estado de Viewpoint/ZombieBuddy).
2. Espera ~10 s más (o **F10**): líneas `[EchoesInv]` (globals y callbacks de Viewpoint, métodos de cámara en `getCore()`, clases concretas de los emisores de audio).
3. **Enviar:** todas las líneas `[EchoesProbe]` y `[EchoesInv]`, y el listado de archivos de la carpeta del mod Viewpoint (workshop 3809306528) en tu disco.

## 2. Echoes (Lua) — arranque
- Debe aparecer `[Echoes] v0.6.0 started`. Si no, o hay `[Echoes][ERROR]`, enviar esas líneas.
- **F7** (Debug): informe de estado y coste por módulo. Enviarlo tras 10–20 min de juego.

## 3. Fenómenos y Director
- **F9** fuerza un fenómeno (dentro de un edificio y sin zombis a <14 casillas). Esperado: `phenomenon fired: <tipo> …`. Tipos: `door`, `knock`, `footsteps`, `voice`, `door_ajar`, `light_flicker`, `story_locked_in`, `apparition`.
- Si ves `sounds[x] = 0 candidates`, el juego no tiene un sonido con esas palabras: el volcado del probe dice cuáles existen.
- **Lugares encantados:** tras un pico de pánico, volver cerca: `place=<tema>/stage<N>` sube de etapa; en etapas altas los pasos se acercan; tras la 4ª se calma.
- Puertas/luces: solo puertas interiores (nunca la puerta de entrada); la puerta entreabierta/lámpara está cerca del lugar encantado y a <30 casillas de ti.

## 4. Cuerpo, miedo, sordera
- **Respiración:** correr hasta agotarte → respiración agitada que se calma (`breathing:`).
- **Miedo:** con 2+ zombis a la vista o presión alta de noche: `fear 0.xx: heartbeat starts`; latido más rápido con más miedo.
- **Sordera:** disparar un arma sin protección → los sonidos de ECHOES se amortiguan ~30 s; con orejeras no. Requiere EchoesEngine (`loudEvents` en `EchoesEngine_stats()`).
- **Mareo (experimental):** **F8** = demo de 6 s. ¿Rota o se balancea la pantalla? Cuéntalo (con y sin Viewpoint). Si funciona, activar `Dizziness` en Sandbox.

## 5. IA de zombis
- **Búsqueda:** haz un ruido y escóndete; al llegar al origen, algunos zombis siguen a habitaciones cercanas (`zombie searches started`).
- **Olor/sangre:** herida sangrante o correr, alejarse de un zombi que no te vio y pasar cerca de tu rastro (`tracking: scent=N`). Con lluvia el rastro dura menos. Ajustar `ScentStrength` (0–2) o apagar `Scent`.
- **Manada:** un zombi que te ve y persigue atrae a vecinos inactivos hacia **él** (`pack=N`).
- **Carácter individual:** unos siguen el rastro desde lejos y otros ni lo notan; unos buscan más habitaciones que otros. Si todos hacen lo mismo, enviar el log.
- **Rendimiento:** con una horda, F7 → coste de `Tracking.tick` y `ZombieAwareness.tick` (avgMs/maxMs).

## 6. Mundo
- De noche, tras varias horas: `activity light at x,y`, `distant alarm started` (alarma tenue y direccional; zombis hacia esa zona), disparos lejanos tenues.
- **Radio del superviviente:** con una radio encendida (pilas o corriente), barrer el dial; tras unas horas debería aparecer una frecuencia con mensajes (`survivor transmission begins`, `survivor radio frequency chosen: N`). Es la parte con más incertidumbre (`SendTransmission`); si no se oye nada, probar con `Frequency=4` y enviar el log.
- >10 días de juego (puedes avanzar el tiempo con las herramientas de depuración): lámparas apagadas/parpadeando al entrar en habitaciones (`room decay stage`); con lluvia y >25 días, goteras (`drip in leaky room`).

## 7. EchoesEngine (Java) — observar primero
1. Busca `[EchoesEngine] v0.4.0 loaded` y `[Echoes] engine v0.4.0 …`.
2. Tras 5–10 min de juego normal: `EchoesEngine_stats()` (consola Lua o F7). **Enviar la línea completa:** llamadas a `getSoundAttract`, `spotted`, `addWorldSoundUnlessInvisible`, radio medio de tu ruido y `loudEvents`.
3. Oído de zombis: haz ruido dentro de un edificio con 2+ muros; observa cuántos zombis exteriores acuden; repite con `EchoesEngine_set("hearingOcclusion", 0)` y compara.
4. Opcionales (apagados por defecto): `EngineNoise` (cargado = más ruido) y `EngineStealth` (zombis pueden no verte agachado/en la oscuridad a distancia; mirar `skipped`).

## 8. Capa visual (experimental, apagada por defecto)
- Activar `Visual` y `Apparitions`. **Primero:** comprobar que el ratón sigue funcionando en menús e inventario (el panel transparente no debe bloquear clics).
- Interior oscuro → calle de día: destello breve; calle → oscuridad: oscurecimiento breve. Con miedo, los bordes laten con el corazón. F9 varias veces: silueta fugaz en el borde.

## 9. Compatibilidad
Repetir §3–§5 en estas condiciones y anotar diferencias: (a) sin Viewpoint; (b) con Viewpoint sin shader pack; (c) con BSL; (d) con Photon.

## 10. Cómo enviar resultados
Copia de `console.txt` las líneas que empiezan por `[Echoes`, `[EchoesProbe]`, `[EchoesInv]`, `[EchoesEngine]` y cualquier traza de error de Lua o de ZombieBuddy relacionada. Añade una frase por cada cosa que se sintió mal, falsa o exagerada.
## Resultados de la primera ejecución real (PZ 42.21.0, ZombieBuddy 2.3.4, 2026-10-21)
- Validado: los 3 mods cargan; jar y 4 parches Java activos; todos los chequeos del Probe OK; 20 módulos Lua con errors=0.
- Validado: F7 imprime el informe; fenómeno `footsteps` disparado por el Director; alarma lejana y radio de supervivientes arrancan; oído (hearing adjusted=78/78, meanFactor medio 0.415 entre casa y exterior) y visión (forced>0) actúan.
- Sin validar: miedo/trauma/mareo/sordera tras una mordida o persecución (no se llegó a leer un informe posterior); ruido con efecto (`noise adjusted=0`, modo observar); `loudEvents`; capa visual.
- Hallado: `GameSounds` no tiene sonido de respiración humana (`breath` solo daba `FishBreath`); la búsqueda por patrón ahora excluye animal/fish/canned/plant. `ZombieBuddy.getPolicy/getJavaModStatus` no existen en 2.3.4.
## Efectos de pantalla (nuevo, sin validar)
- F6 activa/desactiva en partida todos los efectos de pantalla (por personaje; por defecto ON en un jugador): viñeta que late con el miedo, mareo (giro de pantalla), y pérdida de color (`Daze`: control DESATURATION del clima, el mismo que usa el panel admin del juego). Funciona aunque los valores guardados del mundo digan false.
- F8: demo de 6 s de mareo. Esperado: la pantalla gira suavemente; si no, `Viewpoint` puede estar usando su propia cámara.
- Sin implementar (no hay API verificada desde Lua): temblor/sacudida de cámara, desenfoque real. Hoy el temblor solo se refleja en la viñeta y el color.
- Comprobar: `[Echoes] colour drain` / errores `colour drain failed` en console.txt, que el color vuelve a la normalidad al calmarse, y la línea `events:` (`effects.on`/`effects.off`).
## Colisiones y emociones con el motor (nuevo, sin validar)
- Colisiones (`Physical.lua`, lectura de `isCollidedThisFrame` / `getCollidedObject` / `isCollidedWithDoor` / `isCollidedWithVehicle` / `isBumped` / `isFalling` y velocidad del vehículo): puerta/árbol/valla/roce de pared corriendo, atropello a pie, choque en vehículo (caída de 10 km/h en 0.1 s), aterrizaje (>0.6 s en el aire), zombi que te embiste, y tropiezos por agotamiento, mareo o terror. Contadores `physical.*` en F7. Umbrales a calibrar.
- Emociones reales (`Echoes.feel`): los momentos y acciones mueven `STRESS`, `PANIC`, `ANGER`, `UNHAPPINESS`, `BOREDOM` y `PAIN` del propio personaje (los moodles del juego reaccionan). Calmar (respirar, tararear, llorar, rezar, cielo) los baja. F7 imprime `vanilla emotions:`. Comprobar que no se acumulan ni se quedan pegados.
- F6 apaga efectos, física y emociones reales; opciones `PhysicalEnabled` y `FeelEnabled`.
## Tácticas de zombis (nuevo, sin validar)
- `ZombieTactics.lua`: perfil persistente por zombi (rol por ropa: policía/soldado/guardia...; 60 % conservan arma con 3-12 balas y puntería 0.3-0.8; rencor si el jugador los golpeó). Un zombi armado que te persigue, a 4-16 casillas y a la vista, se detiene, apunta ~2 s y dispara (sonido de disparo, ruido de mundo, tirada de impacto; daño `damageFromFirearm` 12-20 en torso/brazos/piernas, nunca cabeza/cuello). Planes: con 3 o más perseguidores, hasta 2 zombis atrevidos flanquean.
- Contadores F7: `ai.gunner`, `ai.aim`, `ai.shot`, `ai.shot_hit`, `ai.flank`, `ai.grudge`. A calibrar: escala del daño, nombres de outfit reales, si `pathToLocationF` a su propia casilla los frena, reacción de la horda al flanqueo.
- Apagar: opciones `ArmedZombiesEnabled` / `TacticsEnabled` o F6.
