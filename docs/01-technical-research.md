# ECHOES — Fase 1: Investigación técnica

Fecha: 2026-10-21. Estado: **investigación documental; nada de esto se ha ejecutado en el juego.**

## 0. Limitaciones de esta investigación (leer primero)

- No tengo el juego instalado: no he leído los `.lua` vanilla (`media/lua/...`) ni la lista real de eventos. Los **nombres de eventos Lua no están verificados**.
- La API Java sí está verificada contra el Javadoc no oficial de **42.20.0** (`demiurgequantified/ProjectZomboidJavaDocs`, archivado a favor de `codeberg.org/albion/PZ-JavaDocs`). El juego actual es 42.21 → puede haber diferencias.
- El Javadoc lista miembros Java; **no demuestra que estén expuestos a Lua**. Cada llamada debe confirmarse en juego (ver spike §6).
- No localicé el código fuente de **Project Viewpoint**. Todo lo que sé de él procede de resultados de búsqueda (fichas de Steam Workshop, pzfans, top-mods), es decir, fuentes secundarias. `WebFetch` no tuvo resolución DNS, así que no pude abrir las páginas.

## 1. Versiones y dependencias

| Componente | Dato | Confianza |
|---|---|---|
| Project Zomboid | Build 42.21 (parches 42.20 = estable según un resultado de julio 2026) | media |
| Estructura de mod B42 | `<Mod>/42/mod.info` + `<Mod>/common/` (+ `media/` dentro de `common/` o `42/`) | media (guías comunitarias) |
| Project Viewpoint | Workshop 3809306528, mod id `Viewpoint`, autores ellu y norkus, lanzado ~fin sept 2026, para 42.21. O = 1ª persona, Shift+O = alterna 1ª/3ª, Supr = ajustes. **La ficha principal mostraba un aviso de retirada en los resultados: comprobar si sigue disponible.** | media-baja |
| ZombieBuddy | Obligatorio para Viewpoint. Agente Java (ByteBuddy). Repo `zed-0xff/ZombieBuddy` (leído). Versiones 2.3.x/3.x. | **alta** (leí el repo) |
| Add-ons Viewpoint | Addons (construcción en 1ª persona, 3812839109), Immersive Effects (3812984535), Immersive Camera Motion (3818432217), Recoil & ADS, QOL, Controller Support, **3D RVs [WIP] (3820158673)** | media |
| Alternativa | `pz3d` (kolpaque): también 1ª/3ª persona, **solo un jugador**, muy WIP | media |

Hechos de ZombieBuddy (del repo, verificados):
- Los mods Java **no tienen sandbox**; cada JAR nuevo/cambiado pide aprobación al usuario (política `prompt`/`deny-new`/`allow-all`).
- Un mod Java declara `require=\ZombieBuddy`, `javaJarFile`, `javaPkgName` en `mod.info`; los JAR en rutas `media/java/client/` o `server/` se omiten en el lado contrario.
- Expone a Lua `ZombieBuddy.Events.getAll()/getByName()` (enumera eventos y callbacks registrados) y utilidades de depuración (`zbinspect`, `zbmethods`, `zbgrep`… en `doc/DevDebugFunctions.md`). **Útil para el spike.**

**Implicación de diseño:** ECHOES no debe exigir Java ni ZombieBuddy. Viewpoint es dependencia *opcional* (detectar y adaptar). Un usuario que no quiera un agente Java sin sandbox debe poder usar ECHOES completo salvo lo específico de Viewpoint.

## 2. APIs confirmadas (Javadoc 42.20.0)

Existencia de clase/método Java confirmada; exposición a Lua sin confirmar.

| Área | Confirmado |
|---|---|
| Sonido de mundo | `WorldSoundManager.addSound(Object,x,y,z,radius,volume[,…])`, `getSoundZomb`, `getSoundAttract`, `getHearingMultiplier`, `getStressFromSounds`; `IsoGameCharacter.addWorldSoundUnlessInvisible` |
| Audición zombi | `IsoZombie.HEARING_{PINPOINT,NORMAL,POOR,RANDOM,NORMAL_OR_POOR}`, `hearing`, `isMovingToPlayerSound`, `isRespondingToPlayerSound`, `HEARING_UNSEEN_OFFSET_*` (el motor ya impone imprecisión) |
| Control zombi | `IsoZombie.setTarget`, `pathToLocationF`, `pathToCharacter`, `Wander`, `WanderFromWindow`, `addAggro`, `clearAggroList`, `spotted*`, `setFakeDead`, `getTarget`, `isTargetVisible`, `isTargetLocationKnown` |
| Emisores de audio | `IsoWorld.getFreeEmitter(x,y,z)`, `BaseSoundEmitter`, `CharacterSoundEmitter`, `BaseVehicle.getEmitter` |
| Estadísticas B42 | `CharacterStat` (registro) con `SANITY, STRESS, PANIC, FATIGUE, ENDURANCE, BOREDOM, UNHAPPINESS, MORALE, PAIN, ANGER, INTOXICATION, ZOMBIE_FEVER…` |
| Edificios/estancias | `BuildingDef.isAlarmed/setAlarmed/alarmDecay/isHasBeenVisited`, `RoomDef`, `IsoGridSquare.isOutside/getRoom/isInARoom/getLightLevel/isCouldSee/isCanSee/isSeen` |
| Luz y mundo | `IsoLightSource`, `IsoCell.addLamppost`, `IsoLightSwitch`, `IsoGenerator`, `IsoHeatSource` |
| Clima | `ClimateManager`: `getRainIntensity, getFogIntensity, getNightStrength, getDayLightStrength, getWindIntensity, isRaining, getThunderStorm…` |
| Puertas/ventanas | `IsoDoor` (`isOpen, isLocked, isBarricaded, ToggleDoor, ToggleDoorSilent`), `IsoWindow` (`IsOpen, isSmashed, isBarricaded, canClimbThrough`) |
| Vehículos | `BaseVehicle`: `getDriver, getCurrentSpeedKmHour, getHeadlightsOn, getWindowLightsOn, isEngineRunning, isAlarmSounding, getEmitter, getPassenger*` |
| Eventos (mecanismo) | `LuaEventManager.AddEvent(String)`, `triggerEvent(...)` → se pueden **crear eventos propios** para el bus interno |
| Oclusión | `LosUtil` existe (clase); uso desde Lua sin verificar |

**Nota:** en B42 las estadísticas ya no son `Stats.getStress()` sino el registro `CharacterStat` (solo quedó `getNicotineStress`). Todo código B41 heredado fallará.

## 3. Viabilidad por sistema

Leyenda: ✅ viable · 🟡 incierto (requiere spike) · ❌ no viable sin Java / no demostrado.

| # | Sistema | Veredicto | Detalle |
|---|---|---|---|
| 6 | **Echoes (audio)** | ✅ (verificar llamadas) | Emisores posicionales con sonidos vanilla, desde el cliente, sin sincronizar. Menor riesgo de todo el proyecto. |
| 6 | Echoes (visual 2D) | 🟡 | Capa UI (ISUI) con texturas existentes: independiente del renderer, por tanto robusta ante Viewpoint. |
| 6 | Echoes (siluetas en el mundo 3D) | 🟡/❌ | Opciones: entidad real con apariencia/estado especial, o cadáver/NPC existente. Sin API verificada para "fantasma" ni de cómo lo dibuja Viewpoint. No prometer. |
| 5 | **Living World** | ✅ | Alarmas (`BuildingDef`), luces/generadores, sonidos de actividad, rastros, condicionados por clima/hora. Autoridad: servidor. |
| 3 | **Zombie Awareness** | ✅ (enfoque indirecto) | No reescribir IA: **inyectar estímulos** (`addSound`) y dejar que el motor decida. Para búsquedas contextuales, `pathToLocationF` limitado a pocos zombis cercanos, escalonado. Riesgo: rendimiento y MP. |
| 1 | **Survival Senses** | 🟡 | Audio contextual factible. Oclusión realista (muros) no demostrada; aproximar con `isOutside/getRoom` y distancia. Sin marcadores en pantalla. |
| 2 | Physical Interaction | 🟡/❌ | Acciones contextuales sobre puertas/ventanas: ✅ (acciones temporizadas + exposición a amenazas). **Asomarse/inclinarse: no encontré API de lean en `IsoPlayer`**; dependería de la cámara de Viewpoint (sin API pública conocida) → probablemente requiere Java. Aplazar. |
| 4 | Driver's Perspective | 🟡/❌ | Audio del vehículo y visibilidad por clima/niebla: parcialmente viable. **Retrovisores y efectos sobre cristal: no viables sin render propio**; no afirmar. Existe un add-on "Viewpoint 3D RVs" (WIP) que indica que Viewpoint trata vehículos de forma propia → estudiar antes de tocar. |

## 4. Proyectos existentes / solapamientos

- **Add-ons de Viewpoint** (Immersive Effects, Immersive Camera Motion, Recoil & ADS): cubren efectos de cámara/ADS, no ambiente sobrenatural. Revisar Immersive Effects para evitar duplicar efectos de pantalla.
- **Reactive Sound Events** (Workshop 2969551071): según comentarios, solo cliente, incompatible con MP, sonidos demasiado cercanos y demasiado frecuentes. Es el antecedente de lo que *no* hacer en Senses.
- Mods de "esquizofrenia/insanity" y un "Haunted [Horror]": mencionados solo de forma anecdótica; **sin confirmar** que existan ni qué hacen.
- No encontré ningún mod que cubra ECHOES de forma integrada. (Ausencia de resultados ≠ ausencia de mods; revisar Workshop a mano.)

## 5. Arquitectura propuesta (realista, mínima)

```
Echoes/
  mod.info                         (raíz: B41 no soportado; ver nota)
  common/
    media/
      lua/
        shared/Echoes/             Core: Log, Config, Registry, Events (bus), Rng, Compat
        client/Echoes/             Director (cliente), Phenomena, Senses, UI, Debug
        server/Echoes/             WorldEvents, AI, autoridad MP
      sandbox-options.txt          (convención PZ; verificar sintaxis B42)
  42/
    mod.info
```

- **Core (shared):** log con niveles, config por módulo (sandbox options + kill-switch por sistema), bus de eventos propio sobre `LuaEventManager.AddEvent`, RNG con semilla, detección de Viewpoint (`getActivatedMods():contains("Viewpoint")` — API a verificar).
- **Director de tensión (cliente):** presupuesto de fenómenos, cooldowns largos, memoria de lo ocurrido ("recuerdo"), puertas por hora/lugar/estrés/`SANITY`. Todos los sistemas piden permiso al Director; así se evita que se acumulen sustos.
- **Cliente vs servidor:** Echoes es experiencia *por jugador* → cliente, sin sincronizar (salvo semilla compartida opcional). WorldEvents y AI que cambian el mundo/zombis → **servidor** (`OnClientCommand`/`sendServerCommand`, nombres a verificar). Senses → cliente.
- **Rendimiento:** nada por fotograma salvo contadores baratos; trabajo en eventos periódicos de baja frecuencia; límite de zombis procesados por tick; sin barrido de celdas.
- **Sin carpetas por estética:** Vehicles, Interaction y ViewpointIntegration no se crean hasta tener una mecánica real.

## 6. Spike obligatorio (antes de escribir sistemas)

Un mod mínimo `EchoesProbe` que, en juego, imprima en `console.txt`:
1. Lista de eventos vía `ZombieBuddy.Events.getAll()` (si hay ZB) o `Events` vanilla → fija nombres reales.
2. Si `getWorld():getFreeEmitter(x,y,z)` y `emitter:playSound(nombre)` funcionan desde Lua, y qué sonidos vanilla existen (en `media/sound/` y scripts `sound`).
3. Si `getPlayer():getStats():get(CharacterStat.SANITY)` (o la firma real) funciona.
4. Si `getWorldSoundManager():addSound(...)` es invocable.
5. Detección de Viewpoint y si `getCore()`/cámara cambian al pulsar O.
6. Funciona en SP y en servidor local (host coop).

## 7. Primera mecánica recomendada

**"Sonido inexplicable" (Echoes, solo cliente, solo Lua):** el Director programa, con probabilidad baja y cooldowns largos, un sonido vanilla (pasos, una puerta, una voz lejana) en un emisor posicional detrás/lateral al jugador, condicionado a noche/interior/aislamiento y modulado por `SANITY`/`STRESS`. Con kill-switch, intensidad y frecuencia configurables y log.

Por qué primero:
- Riesgo técnico mínimo: sin Java, sin sincronización, sin dependencia de Viewpoint, sin tocar IA.
- Valida las piezas que reutilizarán los otros cinco sistemas: Core, Config, Log, bus de eventos, Director.
- Es el "ADN" del proyecto y se prueba rápido en una partida.
- Fallar es barato: si `emitter:playSound` no funciona, el spike lo revela en minutos.

Después: (2) Living World server-side con alarmas de edificio, (3) Senses sobre la misma infraestructura, (4) capa visual 2D de Echoes. Interaction (asomarse) y Driver's Perspective, solo tras estudiar la cámara de Viewpoint.

## 8. Fuentes

- ZombieBuddy: <https://github.com/zed-0xff/ZombieBuddy> (README, `doc/ModdingGuide.md`, `doc/LuaAPI.md`, `doc/Installation.md`) — leído en local.
- Javadoc B42.20.0: <https://github.com/demiurgequantified/ProjectZomboidJavaDocs> — leído en local.
- PZ API Docs (scripts/datos, game_version 42.21.0): <https://github.com/PZ-Wiki-Modding/PZ-API-Docs>.
- Viewpoint y add-ons (secundarias, vía búsqueda): Steam Workshop 3809306528, 3812839109, 3812984535, 3818432217, 3820158673, 3786653645; pzfans.com/project-zomboid-3d-viewpoint; top-mods.com.
- ZombieBuddy en pzwiki.net/wiki/ZombieBuddy y Workshop 3619862853, 3807686870.
- Reactive Sound Events: Workshop 2969551071 (comentarios).
- Estructura B42: guías comunitarias (Workshop discussion 2735294987; projectzomboid.wiki/multiplayer/mods).

## 9. Adenda: shaders y efectos de pantalla (aportado por el usuario: "shaders de Minecraft Java")

Contexto: en Minecraft Java los shader packs funcionan porque OptiFine/Iris exponen un pipeline de post-proceso sustituible. Project Zomboid **no tiene** un equivalente oficial. Lo que sí hay (Javadoc 42.20.0, verificado como existencia de clases/métodos):

| Nivel | Qué | Estado |
|---|---|---|
| A. Efectos vanilla desde Lua | `SearchMode` (accesible vía `LuaManager.GlobalObject.getSearchMode()`): por jugador `setEnabled`, `setOverride`, y valores `blur`, `darkness`, `desat`, `radius`, `gradientWidth` con `SearchModeFloat` (`setInterior/Exterior`, `setTargets`), `setFadeTime`. `ClimateManager.setDesaturation(float)`. `ScreenFader`. | Existe en Java; **por verificar** que Lua pueda fijar los valores y que se vea bajo Viewpoint |
| B. UI 2D | Capas ISUI con texturas existentes (viñetas, ruido). Independiente del renderer. | Viable, riesgo bajo |
| C. GLSL propio | Existen `ShaderProgram` (`createFragShader`, `setValue`, `Start/End`) y `ShaderManager.getOrCreateShader`; los shaders de juego (niebla, agua, charcos, clima) son clases Java con ficheros GLSL. Un post-proceso nuevo exige **Java (ZombieBuddy)** o sustituir ficheros GLSL vanilla (no verificado que los mods puedan hacerlo). | Incierto; fuera del MVP |

Riesgos del nivel C: Viewpoint trae su propio renderer, así que un shader escrito para el pipeline vanilla puede no aplicarse o romperse; además obliga al usuario a aceptar un JAR sin sandbox. Recomendación: **A y B en ECHOES core; C como add-on opcional separado ("Echoes Shaders") más adelante**, con spike propio.

Idea concreta para Echoes con el nivel A: oscurecimiento/desaturación lenta y breve cuando ocurre un fenómeno (`SearchMode` en modo override con fade largo), sin sustos bruscos. Es compatible con la regla "efectos de pantalla mediante mecanismos existentes".

## 10. Adenda 2: Viewpoint ya integra shaders de Minecraft (hallazgo importante)

Según fichas de Workshop y guías (fuentes secundarias, no he podido abrirlas ni leer código de Viewpoint):
- Viewpoint es un **renderer propio** (OpenGL moderno, pipeline PBR) con **puente a shader packs de Minecraft (estilo Iris)**: se colocan en `Zomboid/viewpoint-shaderpacks`, se elige el pack en *Supr → Graphics → Shaders*. Se citan BSL, Eclipse, Noble, Bliss, Solas, Complementary y Photon (Photon "probado por la comunidad" según una ficha; otra fuente lo trata como no verificado).
- Existe un mod de compatibilidad "Viewpoint PZO Eclipse Shader Compatibility" (Workshop 3815225881) para 42.21 / Viewpoint 0.1.5a-0.1.6 / ZombieBuddy ≥ 2.3.0, y "Viewpoint Rolling Hills" (3815630947) que declara soportar el puente. La documentación de shaders de Viewpoint figuraba como "próximamente".
- Guía: pzmanual.com/guides/project-zomboid-shaders/. Errores de shader: `Zomboid/console.txt`.

Consecuencias para ECHOES:
1. **Los efectos vanilla (`SearchMode`, `setDesaturation`) pueden no verse o verse distintos con un shader pack activo** (el pack reemplaza el post-proceso). Hay que probarlo con y sin pack; no asumir.
2. **Capa de UI 2D (nivel B) pasa a ser el fallback fiable**: se dibuja encima de cualquier renderer.
3. **Oportunidad:** un shader pack es solo texto GLSL empaquetado. Un "Echoes shader pack" (viñeta, aberración, ruido, desaturación localizada) sería 100% programático, sin arte, y no requeriría Java en ECHOES. Pero depende del formato soportado por Viewpoint, aún sin documentación pública → no se empieza hasta leerla.
4. No competir con Photon/BSL: no son mods de ECHOES; solo se garantiza que ECHOES no se rompe con ellos (caso de prueba obligatorio: Photon y BSL activos).
