package com.echoes.engine;

import zombie.characters.IsoPlayer;

/**
 * Detects loud noises made by the LOCAL player (gunshots, explosions...) from WorldSoundManager.addSound calls whose
 * source is that player, and remembers when and how loud, so Lua can apply a short period of muffled hearing and
 * ringing. Ear protection (worn hearing multiplier < 0.8) means nothing is recorded. Pure bookkeeping: no gameplay
 * change happens in Java.
 */
public final class LoudLogic {
    private LoudLogic() {}

    private static volatile long lastLoudAtMs = -1;
    private static volatile int lastLoudRadius = 0;

    /** Radius (tiles) from which a noise counts as loud. Typical firearms are well above this. */
    public static volatile int loudRadius = 35;

    /** Pure bookkeeping, used by tests and by observe(). */
    /** addSound overloads delegate to each other, so one gunshot can arrive several times within a few ms. */
    static final int DEDUPE_MS = 250;

    public static void record(int radius, long nowMs) {
        if (radius < loudRadius) return;
        boolean duplicate = lastLoudAtMs >= 0 && nowMs - lastLoudAtMs < DEDUPE_MS;
        lastLoudAtMs = nowMs;
        lastLoudRadius = Math.max(duplicate ? lastLoudRadius : 0, radius);
        if (!duplicate) Stats.loudEvents.incrementAndGet();
    }

    public static long msSince(long nowMs) {
        return lastLoudAtMs < 0 ? -1 : Math.max(0, nowMs - lastLoudAtMs);
    }

    public static int radius() { return lastLoudRadius; }

    public static void reset() { lastLoudAtMs = -1; lastLoudRadius = 0; }

    /** Called from the patch with the raw arguments. Never throws. */
    public static void observe(Object source, int radius) {
        try {
            if (radius < loudRadius || !(source instanceof IsoPlayer)) return;
            IsoPlayer p = (IsoPlayer) source;
            if (!p.isLocalPlayer()) return;
            if (p.getWornItemsHearingMultiplier() < 0.8f) return; // earmuffs / protection
            record(radius, System.currentTimeMillis());
        } catch (Throwable t) {
            Stats.errors.incrementAndGet();
        }
    }
}
