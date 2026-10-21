# ECHOES — Fase 2: Diseño (borrador)

Estado: diseño sobre APIs **no verificadas en juego**. Todo lo marcado `[V]` depende del resultado de `EchoesProbe`.

## 1. Principios
1. Lua puro; sin Java ni ZombieBuddy como requisito.
2. Viewpoint opcional: se detecta y se adapta; sin él, todo funciona igual.
3. Todo sistema pasa por el Director y tiene kill-switch propio.
4. Cero trabajo por fotograma salvo contadores baratos.

## 2. Estructura de archivos (MVP)

```
Echoes/
  42/mod.info
  common/media/
    sandbox-options.txt                       [V] sintaxis B42
    lua/shared/Echoes/
      Core.lua        namespace, versión, registro de módulos
      Log.lua         niveles (error/warn/info/debug), prefijo "[Echoes]"
      Config.lua      lectura de SandboxVars.Echoes, defaults, isEnabled(module)
      Bus.lua         eventos propios sobre LuaEventManager.AddEvent   [V]
      Rng.lua         RNG con semilla (mundo + jugador) reproducible
      Compat.lua      detección de Viewpoint / ZombieBuddy             [V]
    lua/client/Echoes/
      Director.lua    presupuesto de tensión, cooldowns, memoria
      Phenomena/Sound.lua   fenómeno "sonido inexplicable"
      Debug.lua       comandos y volcado de estado
```

## 3. Interfaces

```lua
-- Config
Echoes.Config.isEnabled("Echoes.Sound") -> boolean
Echoes.Config.get("Echoes.Sound", "Frequency") -> number

-- Fenómeno (registrado en el Director)
Echoes.Director.register{
  id = "Echoes.Sound.Footsteps",
  weight = 1.0,
  cooldown = 600,            -- segundos de juego
  canFire = function(ctx) end,   -- ctx: player, square, hour, night, indoor, sanity, stress
  fire    = function(ctx) end,   -- devuelve un registro de memoria o nil
}

-- Bus (eventos propios)
Echoes.Bus.on("EchoesPhenomenonFired", fn)   -- id, ctx
Echoes.Bus.emit("EchoesPhenomenonFired", id, ctx)
```

## 4. Director de tensión
- Se evalúa en un evento periódico lento (`EveryTenMinutes` o equivalente `[V]`), no por tick.
- Mantiene `tension` (0–1) que sube con oscuridad, aislamiento e interior y baja tras un fenómeno; un fenómeno solo puede dispararse si `tension >= umbral` y se pasó el cooldown global.
- Probabilidad base muy baja; multiplicada por la sandbox `Frequency` y modulada por `SANITY`/`STRESS` (suavemente, sin penalización mecánica: solo ambiente).
- Memoria: guarda los últimos N fenómenos (tipo, lugar, hora) en `player:getModData().Echoes` para evitar repetición y permitir referencias posteriores (mismo lugar, otro fenómeno).
- Anti-repetición: peso decreciente por tipo reciente.

## 5. Fenómeno MVP: sonido inexplicable
- Elige un sonido de una lista configurable de sonidos vanilla `[V]` (puertas, pasos, voz lejana).
- Posición: 5–12 casillas, fuera del campo visual directo si se puede estimar, preferentemente tras muros/otra estancia.
- Condiciones: noche o interior; no en combate; sin zombis a la vista; no durante conducción en la v1.
- Emisor: `getWorld():getFreeEmitter(x,y,z):playSound(name)` `[V]`. **No** llama a `addSound`, así que no atrae zombis y no tiene efecto mecánico.
- Intensidad (sandbox): Baja/Media/Alta = volumen y cercanía.

## 6. Configuración (sandbox)
`Echoes.Enabled`, `Echoes.Sound.Enabled`, `Echoes.Frequency` (0.25–4), `Echoes.Intensity`, `Echoes.Debug` (log nivel debug). Se añadirán `Echoes.WorldEvents.Enabled`, etc., con cada módulo.

## 7. Registro y depuración
- `Log.debug` solo si `Echoes.Debug`; `Log.error` siempre. Cada módulo registra su inicio y su desactivación.
- Debug: comando de consola para forzar un fenómeno y volcar tensión, cooldowns y memoria.

## 8. Rendimiento y pruebas
- Presupuesto: el Director debe costar <0,1 ms por evaluación (medir con `getTimestampMs()` `[V]`).
- Pruebas manuales de regresión: (a) mod desactivado → sin trazas ni errores; (b) Viewpoint instalado y no instalado; (c) cargar partida existente; (d) 30 min de juego con `Frequency=4` sin errores en consola; (e) dos jugadores en coop local `[V]`.

## 9. Efectos de pantalla (post-MVP, nivel A)
Tras el MVP de audio: `Phenomena/Screen.lua` usando `getSearchMode()` en override con `setFadeTime` largo (ver adenda §9 de la investigación). Requiere spike: añadir al probe `getSearchMode():getBlur(0)` y `setOverride`. GLSL propio queda fuera del core.

## 10. Fuera del MVP
Senses (oclusión), WorldEvents (servidor), AI, Vehicles, Interaction y capa visual 2D. Cada uno entra con su spike propio.
