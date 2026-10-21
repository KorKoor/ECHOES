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

    /** Returns {radius, volume} to use. */
    public static int[] adjust(Object selfObj, int radius, int volume) {
        try {
            Stats.noiseCalls.incrementAndGet();
            Stats.noiseRadiusSum.addAndGet(radius);
            if (!Options.noise || !(selfObj instanceof IsoPlayer)) return new int[] { radius, volume };
            IsoPlayer p = (IsoPlayer) selfObj;
            float max = Math.max(1, p.getMaxWeight());
            float load = p.getInventoryWeight() / max;
            float rf = radiusFactor(load), vf = volumeFactor(load);
            if (rf <= 1.0001f) return new int[] { radius, volume };
            Stats.noiseAdjusted.incrementAndGet();
            return new int[] { Math.round(radius * rf), Math.round(volume * vf) };
        } catch (Throwable t) {
            Stats.errors.incrementAndGet();
            return new int[] { radius, volume };
        }
    }
}
