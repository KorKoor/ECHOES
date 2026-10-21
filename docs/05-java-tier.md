# ECHOES — Nivel Java ("más allá de Lua")

## Por qué Lua se queda corto
Todo lo implementado hasta 0.2.0 es Lua puro. Es el techo de lo que el juego deja hacer sin tocar el motor: sonidos, objetos existentes, una capa 2D. **Asomarse, retrovisores, siluetas 3D en el mundo, FOV real, reverberación, un post-proceso propio o una percepción de zombis distinta requieren engancharse al motor.** Eso es exactamente lo que hacen Project Viewpoint y los shader packs: usan **Java con ZombieBuddy** (agente ByteBuddy).

Por tanto sí es posible un nivel muy superior. Lo que no puedo hacer a ciegas es escribir esos parches: dependen de **clases internas que no he visto** (el juego decompilado y, sobre todo, Viewpoint, cuyo código no localicé).

## Qué da ZombieBuddy (verificado en su repositorio)
- `@Patch(className, methodName)` con `@OnEnter` / `@OnExit`, `skipOn` (saltarse el método original), lectura y escritura de argumentos, retorno y **campos privados** (`@Patch.Field`, `@Patch.VarHandle`), parcheo de clases ya cargadas. Las clases se nombran con cadenas: **se puede compilar sin el jar del juego**.
- `@Exposer.LuaClass` / `@LuaMethod(global=true)`: exponer funciones Java a Lua. El patrón será "Java mínimo que abre una capacidad, Lua con la lógica".
- Reconocimiento en caliente (modo `experimental`): `zbinspect`, `zbmethods`, `zbfields`, `zbgrep`, `zbcall`, `ZombieBuddy.Watches` (log de llamadas a cualquier método) y `ZombieBuddy.Events` (qué Lua escucha cada evento).

## Capacidades que abriría, por prioridad
| Capacidad | Para qué | Qué hay que descubrir |
|---|---|---|
| Percepción de zombis con conos/luz | Que ver y oír dependa de iluminación, ángulo, movimiento y sigilo reales, sin saltarse las reglas del motor | Métodos de visión en `IsoZombie` (`spotted*`, visibilidad), cómo calcula el motor la detección |
| Inclinación / asomarse | Leaning real con cámara | Cómo posiciona la cámara Viewpoint (¿exponen yaw/pitch/offset?) |
| Reverb y filtros de audio por sala | Ambiente acústico creíble | Parámetros FMOD disponibles (`setParameterValueByName`) y eventos con envío de reverb |
| Siluetas/presencias en el mundo | Aparición real a distancia | Cómo dibuja entidades Viewpoint; si hay forma de renderizar un personaje "fantasma" |
| Cristales/lluvia/retrovisores | Conducción inmersiva | Pipeline de render de Viewpoint (¿pases extra, FBO?) |
| Post-proceso propio | Adaptación a la luz, deslumbramiento, polvo, niebla local | Puente de shader packs de Viewpoint; qué uniforms acepta |

## Decisión de seguridad
Un mod con JAR es **código sin sandbox** y exige que el usuario apruebe el JAR (ZombieBuddy lo pregunta). Por eso:
1. `Echoes` (Lua) sigue funcionando solo, sin Java.
2. El nivel Java será un mod **separado y opcional** (`EchoesEngine`), con `require=\ZombieBuddy` y versión pinneada.
3. Si falla un parche, ZombieBuddy lo registra y el resto de ECHOES continúa.

## Siguiente paso concreto: reconocimiento (mañana)
`EchoesProbe/.../EchoesInventory.lua` (F10 o automático a los ~10 s) imprime en `console.txt` líneas `[EchoesInv]`:
- estado de ZombieBuddy y de los JAR de Viewpoint;
- globals Lua relacionados con Viewpoint/cámara/FOV (y sus funciones);
- callbacks de eventos registrados por los ficheros de Viewpoint;
- métodos y campos de `getCore()`, `getPlayer()`, `getCell()`, `getWorld()` relacionados con cámara/vista.

Para activarlo: lanzar ZombieBuddy con `experimental` (Windows `-agentlib:zbNative=experimental --`; Linux/macOS `-javaagent:ZombieBuddy.jar=experimental --`).

Además, **lista la carpeta del mod Viewpoint** en tu disco (Steam → `steamapps/workshop/content/108600/3809306528/`, o el nombre que tenga) y pásame el árbol de archivos: ahí estarán su JAR, sus Lua y posiblemente documentación. Con eso decido qué parchear y qué API de Viewpoint puedo usar en lugar de reinventarla.

## Plan por fases del nivel Java
- **J0** (mañana): inventario.
- **J1**: `EchoesEngine` mínimo: arranque, registro, versión y una función Lua de prueba; solo observa (Watches) y mide.
- **J2**: primera capacidad, elegida con los datos (probablemente percepción de zombis o audio por sala, que no dependen de la cámara de Viewpoint).
- **J3+**: cámara/inclinación y presencias visuales según lo que exponga Viewpoint.

---

# EchoesEngine 0.1.0 — primera capacidad Java (implementada, sin probar en juego)

**Decisión tomada:** ECHOES usa ZombieBuddy. `EchoesEngine` es un mod separado (`require=\ZombieBuddy`); `Echoes` (Lua) sigue funcionando sin él y, si está presente, lo usa.

## Qué hace: audición física de los zombis
Parche sobre `zombie.WorldSoundManager.getSoundAttract(WorldSound, IsoZombie) -> float` (firma verificada en el Javadoc 42.20.0): la "atracción" de un zombi hacia un ruido se multiplica por un factor ≤ 1 que depende de:
- **muros, puertas y ventanas cerradas** entre el origen del sonido y el zombi (usa `IsoGridSquare.isBlockedTo`, es decir las propias reglas del juego): ×0,55 por arista bloqueada;
- **diferencia de pisos**: ×0,6 por piso;
- **cruzar la envolvente del edificio** (interior↔exterior): ×0,85;
- **lluvia y viento**: hasta −25 % y −10 %.
Nunca baja de 0,08 y nunca aumenta. No revela posiciones. Es la **misma función** que usa el audio del jugador en Lua (`EchoesEngine_occlusion`), así que lo que a ti te suena amortiguado también lo oyen amortiguado los zombis.

Coste controlado: caché de 400 ms por (sonido, zombi), líneas largas solo comprueban ambos extremos, contadores de uso y tiempo (`EchoesEngine_stats()`), y el parche **se desactiva solo tras 25 errores seguidos** devolviendo el valor original.

## API Lua expuesta
`EchoesEngine_version()`, `EchoesEngine_set(nombre, valor)` (`hearingOcclusion`, `weatherHearing`, `strength`, `maxLine`, `wallFactor`, `levelFactor`, `envelopeFactor`, `minFactor`, `cacheMs`), `EchoesEngine_stats()`, `EchoesEngine_resetStats()`, `EchoesEngine_occlusion(x0,y0,z0,x1,y1,z1)`. Sandbox: `EngineHearing` y `EngineStrength`.

## Cómo está construido y qué se ha verificado
- Código en `engine/` (fuente, `build.sh`, `stubs/`). El JAR se compila **sin el juego** contra stubs hechos a mano desde el Javadoc y `Patch.java` de ZombieBuddy; en ejecución se usan las clases reales, por lo que **las firmas deben coincidir exactamente**.
- `./build.sh` compila y ejecuta `SelfTest` (mundo falso): muro = 0,55; dos muros = 0,3025; un piso = 0,6; envolvente = 0,85; sin muros = 1; un zombi a cielo abierto conserva el 100 % y detrás de dos muros el 30 %; el argumento erróneo no lanza; `strength 0.5` reduce a la mitad el efecto. **Resultado: todo pasa.** Esto prueba la lógica, no la integración con el juego.
- JAR resultante: `EchoesEngine/42/media/java/EchoesEngine.jar` (compilado con `--release 17`).

## Qué puede fallar y cómo lo veremos
| Riesgo | Cómo se manifiesta | Cómo se comprueba |
|---|---|---|
| El float que devuelve `getSoundAttract` no es una "puntuación" proporcional | Zombis ignoran ruidos que antes oían, o no cambia nada | `EchoesEngine_stats()`: `adjusted`, `meanFactor`; prueba empírica: martillar tras 2 muros y ver si llegan menos zombis |
| ZombieBuddy no aplica el parche (firma/clase) | El log de ZombieBuddy lo dice; `calls=0` en stats | `[EchoesEngine] v0.1.0 loaded` + `calls>0` tras hacer ruido |
| `isBlockedTo` no incluye puertas cerradas | Menos efecto del esperado | Mismo experimento con una puerta cerrada |
| Coste por llamada | FPS | `usPerCall` en stats; `maxLine`/`cacheMs` son ajustables en caliente |

## Instalación (mañana)
1. Instalar ZombieBuddy (si no lo tienes) y copiar `EchoesEngine/` a `~/Zomboid/mods/`.
2. Activar `EchoesEngine` y `Echoes` en la partida. ZombieBuddy preguntará por aprobar el JAR (hash SHA-256); aceptar.
3. Con Debug: `[EchoesEngine] v0.1.0 loaded` y `[Echoes] engine v0.1.0 hearing=true`.
4. Experimento: dentro de un edificio de 2+ muros, golpear (o hacer ruido) y observar cuántos zombis exteriores acuden; luego `EchoesEngine_set("hearingOcclusion",0)` en la consola Lua y repetir. Leer `EchoesEngine_stats()`.

## Siguientes capacidades (tras tus datos de `[EchoesInv]`)
Percepción visual de zombis (luz, cono, sigilo), reverberación por sala, inclinación/cámara según lo que exponga Viewpoint, presencias en el mundo y post-proceso propio.

---

# EchoesEngine 0.2.0 — visión de zombis (observar primero)

Parche sobre `zombie.characters.IsoZombie#spotted(IsoMovingObject, boolean)` (firma verificada; `IsoZombie` es `final`, hereda de `IsoGameCharacter`). `skipOn`: devolver `true` hace que el zombi **ignore esa detección**.

**Por defecto solo observa:** cuenta llamadas totales, forzadas y saltadas (`EchoesEngine_stats()` → `vision[spotted=… forced=… skipped=…]`). Con eso, mañana sabremos *cuántas veces por segundo* llama el motor a `spotted` y cuánto pesa lo forzado, antes de tocar nada.

**Modo sigilo (Sandbox `EngineStealth`, apagado):** una detección *no forzada* de un **jugador** puede ignorarse con probabilidad `c` (máx. 0,9) si el jugador es difícil de ver:
- agachado/sigiloso (+0,25);
- en una casilla oscura, `getLightLevel < 0,3` (hasta +0,30);
- el zombi no lo está encarando (+0,15);
- todo ello multiplicado por la distancia: a menos de 3 casillas **nunca** hay ocultación, y crece hasta 13 casillas.
Las detecciones forzadas, otros objetivos y cualquier error → no se omite nada. El motor ya penaliza visión por oscuridad (hasta 5), niebla (7) y lluvia: este modo *suma*, así que empezar con `EngineStealthStrength` bajo (0,6 por defecto) y subir según lo que se sienta.

**Verificado:** 8 pruebas nuevas de la función `concealment` (sin ocultación a plena luz, límites, cercanía, objetivos no jugador, contadores). **No verificado:** cuántas veces se llama `spotted`, si saltarse la llamada produce "pérdida de objetivo" natural o un comportamiento raro, y si el servidor tiene datos de luz (en MP la luz solo existe en el cliente; la excepción se traga y no se oculta nada).
