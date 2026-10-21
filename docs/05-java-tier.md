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
