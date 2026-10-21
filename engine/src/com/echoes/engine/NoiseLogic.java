package com.echoes.engine;

import zombie.characters.IsoPlayer;

/**
 * Applied to IsoPlayer.addWorldSoundUnlessInvisible(radius, volume, stressHumans): the noise the PLAYER makes.
 * DEFAULT: observe only (count calls and radii). With Options.noise on, a heavily loaded character is louder:
 * up to +25 % radius and +15 % volume when carrying at full capacity (nothing below half capacity).
 * Never makes the player quieter than vanilla, never touches zombies, and any error leaves the values unchanged.
 */
public final class NoiseLogic {
    private NoiseLogic() {}

    /** Pure maths: multiplier for a load ratio (carried weight / capacity). 1.0 up to 50 % load, 1.25 at 100 %+. */
    public static float radiusFactor(float loadRatio) {
        float over = Math.max(0f, Math.min(1f, (loadRatio - 0.5f) * 2f));
        return 1.0f + 0.25f * over * Options.noiseStrength;
    }

    public static float volumeFactor(float loadRatio) {
        float over = Math.max(0f, Math.min(1f, (loadRatio - 0.5f) * 2f));
        return 1.0f + 0.15f * over * Options.noiseStrength;
    }

    /** Load ratio of an IsoPlayer, or -1 when this is not the load-affected case (observe-only, other object, error). */
    private static float load(Object selfObj) {
        if (!Options.noise || !(selfObj instanceof IsoPlayer)) return -1f;
        IsoPlayer p = (IsoPlayer) selfObj;
        return p.getInventoryWeight() / Math.max(1, p.getMaxWeight());
    }

    /**
     * Radius to use. Loud events (>= LoudLogic.loudRadius: gunshots, explosions) are left exactly as they are, and a
     * load-inflated radius is capped just below that threshold, so this never turns a footstep into a "gunshot" for
     * LoudLogic. Counts the call (observe-only mode counts too).
     */
    public static int radius(Object selfObj, int radius) {
        try {
            Stats.noiseCalls.incrementAndGet();
            Stats.noiseRadiusSum.addAndGet(radius);
            float load = load(selfObj);
            if (load < 0f || radius >= LoudLogic.loudRadius) return radius;
            float rf = radiusFactor(load);
            if (rf <= 1.0001f) return radius;
            Stats.noiseAdjusted.incrementAndGet();
            return Math.min(Math.round(radius * rf), Math.max(radius, LoudLogic.loudRadius - 1));
        } catch (Throwable t) {
            Stats.errors.incrementAndGet();
            return radius;
        }
    }

    /** Volume to use for a noise whose ORIGINAL radius was `originalRadius`. */
    public static int volume(Object selfObj, int volume, int originalRadius) {
        try {
            float load = load(selfObj);
            if (load < 0f || originalRadius >= LoudLogic.loudRadius) return volume;
            return Math.round(volume * volumeFactor(load));
        } catch (Throwable t) {
            Stats.errors.incrementAndGet();
            return volume;
        }
    }
}
