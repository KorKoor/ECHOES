package com.echoes.engine;

import java.util.concurrent.ThreadLocalRandom;

import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoMovingObject;

/**
 * Applied to IsoZombie.spotted(IsoMovingObject, boolean) through skipOn: returning true makes the zombie ignore that
 * sighting. DEFAULT: observe only (counts calls). With Options.stealth on, a non-forced sighting of a PLAYER is
 * sometimes ignored when the player is hard to see: sneaking, standing in a dark square, far away, or outside the
 * zombie's facing. Close range is never concealed, forced sightings are never touched, and every failure means
 * "do not skip".
 */
public final class VisionLogic {
    private VisionLogic() {}

    /** Seam so the maths can be tested without the (final) game classes. */
    public interface View {
        boolean targetIsPlayer();
        boolean sneaking();
        float light();            // 0 dark .. 1 bright, or -1 unknown
        double distance();
        boolean zombieFacing();
    }

    /** Probability in [0, 0.9] that a non-forced sighting is ignored. Pure function. */
    public static double concealment(View v) {
        if (!v.targetIsPlayer()) return 0;
        double d = v.distance();
        double range = Math.max(0, Math.min(1, (d - Options.stealthNearTiles) / Options.stealthRampTiles));
        if (range <= 0) return 0; // close: never concealed
        double c = 0;
        if (v.sneaking()) c += 0.25;
        float l = v.light();
        if (l >= 0 && l < 0.3f) c += (0.3 - l) / 0.3 * 0.30;
        if (!v.zombieFacing()) c += 0.15;
        return Math.max(0, Math.min(0.9, c * range));
    }

    /** Per-zombie decision kept for DECISION_MS, so concealment is not defeated by calling spotted() many times. */
    static final int DECISION_MS = 1500;
    private static final java.util.concurrent.ConcurrentHashMap<Integer, long[]> decisions =
            new java.util.concurrent.ConcurrentHashMap<>();

    /** True = ignore this sighting. long[]{expiresAtMs, skip(0/1)}. */
    static boolean decide(int zombieKey, double concealmentProbability, long nowMs) {
        if (concealmentProbability <= 0) { decisions.remove(zombieKey); return false; }
        long[] d = decisions.get(zombieKey);
        if (d == null || d[0] <= nowMs) {
            boolean skip = ThreadLocalRandom.current().nextDouble() < concealmentProbability;
            if (decisions.size() > 2048) decisions.clear();
            d = new long[] { nowMs + DECISION_MS, skip ? 1 : 0 };
            decisions.put(zombieKey, d);
        }
        if (d[1] == 1) Stats.spottedSkipped.incrementAndGet();
        return d[1] == 1;
    }

    public static boolean shouldSkip(Object zombieObj, Object otherObj, boolean forced) {
        try {
            Stats.spottedCalls.incrementAndGet();
            if (forced) { Stats.spottedForced.incrementAndGet(); return false; }
            if (!Options.stealth) return false;
            if (!(zombieObj instanceof IsoZombie) || !(otherObj instanceof IsoMovingObject)) return false;
            final IsoZombie z = (IsoZombie) zombieObj;
            final IsoMovingObject o = (IsoMovingObject) otherObj;
            View v = new View() {
                public boolean targetIsPlayer() { return o instanceof IsoPlayer; }
                public boolean sneaking() { return o instanceof IsoPlayer && ((IsoPlayer) o).isSneaking(); }
                public float light() {
                    if (!Options.stealthUseLight || !(o instanceof IsoPlayer)) return -1f;
                    IsoGridSquare sq = o.getCurrentSquare();
                    return sq == null ? -1f : sq.getLightLevel(((IsoPlayer) o).getPlayerNum());
                }
                public double distance() {
                    double dx = o.getX() - z.getX(), dy = o.getY() - z.getY();
                    return Math.sqrt(dx * dx + dy * dy);
                }
                // Geometric: is the target within about 70 degrees of the direction the zombie is facing? (isFacingTarget()
                // depends on the zombie's CURRENT target, which a first sighting does not have yet.)
                public boolean zombieFacing() {
                    double dx = o.getX() - z.getX(), dy = o.getY() - z.getY();
                    double len = Math.sqrt(dx * dx + dy * dy);
                    if (len < 1e-6) return true;
                    double dot = (dx * z.getForwardDirectionX() + dy * z.getForwardDirectionY()) / len;
                    return dot > 0.34;
                }
            };
            double c = concealment(v) * Options.stealthStrength;
            return decide(System.identityHashCode(z), c, System.currentTimeMillis());
        } catch (Throwable t) {
            Stats.errors.incrementAndGet();
            return false;
        }
    }
}
