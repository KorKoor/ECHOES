package com.echoes.engine;

import se.krka.kahlua.integration.annotations.LuaMethod;

/** Global Lua functions. The Lua side (Echoes.Engine) checks that EchoesEngine_version exists before using any. */
public final class LuaApi {
    private LuaApi() {}

    @LuaMethod(name = "EchoesEngine_version", global = true)
    public static String version() {
        return Main.VERSION;
    }

    /** Returns true if the option name is known. See Options for names. */
    @LuaMethod(name = "EchoesEngine_set", global = true)
    public static boolean set(String name, double value) {
        return Options.set(name, value);
    }

    @LuaMethod(name = "EchoesEngine_stats", global = true)
    public static String stats() {
        return Stats.summary();
    }

    @LuaMethod(name = "EchoesEngine_resetStats", global = true)
    public static void resetStats() {
        Stats.reset();
    }

    /** Sound transmission factor 0..1 between two tile coordinates (same model zombies use). */
    @LuaMethod(name = "EchoesEngine_occlusion", global = true)
    public static double occlusion(double x0, double y0, double z0, double x1, double y1, double z1) {
        try {
            return Occlusion.factor((int) Math.floor(x0), (int) Math.floor(y0), (int) Math.floor(z0),
                    (int) Math.floor(x1), (int) Math.floor(y1), (int) Math.floor(z1));
        } catch (Throwable t) {
            Stats.errors.incrementAndGet();
            return 1.0;
        }
    }
}
