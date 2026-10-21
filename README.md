# ECHOES

Mod modular para **Project Zomboid Build 42** centrado en tensión, sentidos y simulación, con compatibilidad opcional con **Project Viewpoint**. Lua puro para la lógica y un **nivel Java opcional (ZombieBuddy)** para lo que el motor no deja hacer desde Lua.

> **Estado: prototipo 0.5.0. Nada se ha ejecutado todavía en el juego.** Lo que está verificado es la existencia de las clases y métodos usados (Javadoc 42.20.0), la sintaxis de todo el Lua, la lógica contra un mundo simulado (`tests/mock_harness.lua`, varias semillas) y la lógica del módulo Java (`engine/build.sh`). Ver `docs/03-test-plan.md`.

## Contenido
| Carpeta | Qué es |
|---|---|
| `Echoes/` | Mod principal (Lua). Instalar en `~/Zomboid/mods/`. |
| `EchoesEngine/` | Mod Java opcional (requiere ZombieBuddy): audición física de los zombis. |
| `EchoesProbe/` | Diagnóstico: vuelca a `console.txt` qué APIs funcionan, sonidos reales, estado de Viewpoint/ZombieBuddy. **Ejecutar primero.** |
| `engine/` | Fuente, stubs y pruebas del mod Java (`./build.sh`). |
| `tests/` | Simulación de la API del juego para pruebas de lógica. |
| `docs/` | Investigación, diseño, hoja de ruta, plan de pruebas, nivel Java. |

## Qué hace (resumen)
- **Sentidos:** pistas direccionales de amenazas reales no vistas, incertidumbre posicional en la oscuridad, acústica con muros/puertas/pisos/clima/cabina.
- **Interacción:** "Listen at the door" (escuchar tras una puerta).
- **IA de zombis:** búsqueda por habitaciones, **rastro de olor** (sangre, esfuerzo; la lluvia lo borra), atracción por sangre del suelo, **alerta de manada**, **personalidad individual** (olfato, persistencia, audacia), oído físico vía Java.
- **Tu personaje:** respiración agitada, **miedo** (latido, bordes oscuros), **mareo** (experimental), presión psicológica opcional.
- **Mundo:** alarmas que duran horas y atraen zombis, luces de actividad humana, disparos lejanos, decaimiento eléctrico por sala, goteras, historias ambientales.
- **Presencias:** sonidos y fenómenos ambiguos con lugares "encantados" que **escalan por etapas** (pasos que acaban viniendo hacia ti), siluetas fugaces (experimental).

Estado detallado por sistema y límites técnicos: `docs/04-realism-roadmap.md`.

## Herramientas de depuración (Sandbox → ECHOES → Debug)
`F9` fuerza un fenómeno · `F8` demo de mareo · `F7` informe de estado y coste por módulo · `F10` inventario del motor (EchoesProbe).

## Compatibilidad
Viewpoint es **opcional**; el nivel Java requiere ZombieBuddy. Conflictos conocidos: ninguno confirmado (sin probar). Multijugador: la lógica del mundo y de zombis está pensada para ejecutarse en servidor/host; los efectos locales son de cliente. Sin verificar en MP.
