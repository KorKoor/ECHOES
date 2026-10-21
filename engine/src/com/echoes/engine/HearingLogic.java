package com.echoes.engine;

import java.util.concurrent.ConcurrentHashMap;

import zombie.WorldSoundManager;
import zombie.characters.IsoZombie;
import zombie.iso.IsoGridSquare;
import zombie.iso.weather.ClimateManager;

/**
 * Applied to WorldSoundManager.getSoundAttract: the score with which a zombie is drawn to a sound.
 * We only ever multiply it by a factor <= 1, using the same geometry the player's audio uses, so zombies stop
 * hearing a hammer through three walls as clearly as in the open. Nothing is revealed to anyone: it makes the
 * existing hearing rules more physical. Any failure returns the original value and, repeated, disables the patch.
 */
public final class HearingLogic {
    private HearingLogic() {}

    private static final class Entry {
        final float factor;
        final long expires;
        Entry(float f, long e) { factor = f; expires = e; }
    }

    private static final ConcurrentHashMap<Long, Entry> cache = new ConcurrentHashMap<>();
    private static final int MAX_CONSECUTIVE_ERRORS = 25;

    /** Called whenever an option changes so stale factors are not reused. */
    public static void clearCache() { cache.clear(); }

    /** Seam so the logic can be tested without the (final) IsoZombie class. */
    public interface ZView {
        IsoGridSquare square();
    }

    public static float adjust(float result, Object soundObj, Object zomObj) {
        if (!(Options.hearingOcclusion || Options.weatherHearing) || result <= 0f) return result;
        if (Stats.consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) return result;
        try {
            final IsoZombie z = (IsoZombie) zomObj;
            if (z == null) return result;
            return adjustCore(result, (WorldSoundManager.WorldSound) soundObj, new ZView() {
                public IsoGridSquare square() { return z.getCurrentSquare(); }
            });
        } catch (Throwable t) {
            return failed(result, t);
        }
    }

    private static float failed(float result, Throwable t) {
        Stats.errors.incrementAndGet();
        if (++Stats.consecutiveErrors == MAX_CONSECUTIVE_ERRORS) {
            System.out.println("[EchoesEngine] hearing patch disabled after repeated errors: " + t);
        }
        return result;
    }

    public static float adjustCore(float result, WorldSoundManager.WorldSound s, ZView z) {
        long t0 = System.nanoTime();
        try {
            if (s == null || z == null) return result;
            Stats.calls.incrementAndGet();

            // The factor depends only on the two positions, so the cache is keyed by exactly those (never by zombie id:
            // ids can be -1 or shared in single player, which would make zombies reuse each other's factor).
            IsoGridSquare zsq = z.square();
            if (zsq == null) return result;
            long key = key(s.x, s.y, s.z, zsq.getX(), zsq.getY(), zsq.getZ());
            long now = System.currentTimeMillis();
            Entry e = cache.get(key);
            float f;
            if (e != null && e.expires > now) {
                f = e.factor;
                Stats.cacheHits.incrementAndGet();
            } else {
                f = compute(s, zsq);
                if (cache.size() > 4096) cache.clear();
                cache.put(key, new Entry(f, now + Options.cacheMs));
            }
            Stats.consecutiveErrors = 0;
            if (f >= 0.999f) return result;
            Stats.adjusted.incrementAndGet();
            Stats.factorMicros.addAndGet((long) (f * 1_000_000));
            return result * f;
        } catch (Throwable t) {
            return failed(result, t);
        } finally {
            Stats.nanos.addAndGet(System.nanoTime() - t0);
        }
    }

    /** 64-bit mix of two 3D integer positions (splitmix64 finaliser over a packed value); collisions are negligible. */
    static long key(int sx, int sy, int sz, int zx, int zy, int zz) {
        long a = ((long) (sx & 0xFFFFF) << 40) | ((long) (sy & 0xFFFFF) << 20) | (sz & 0xFFFFF);
        long b = ((long) (zx & 0xFFFFF) << 40) | ((long) (zy & 0xFFFFF) << 20) | (zz & 0xFFFFF);
        long h = a * 0x9E3779B97F4A7C15L ^ Long.rotateLeft(b * 0xC2B2AE3D27D4EB4FL, 29);
        h ^= h >>> 30; h *= 0xBF58476D1CE4E5B9L; h ^= h >>> 27; h *= 0x94D049BB133111EBL; h ^= h >>> 31;
        return h;
    }

    private static float compute(WorldSoundManager.WorldSound s, IsoGridSquare zsq) {
        float f = 1.0f;
        if (Options.hearingOcclusion) {
            f *= Occlusion.factor(zsq.getX(), zsq.getY(), zsq.getZ(), s.x, s.y, s.z);
        }
        if (Options.weatherHearing) {
            ClimateManager c = ClimateManager.getInstance();
            if (c != null) {
                float w = 1.0f - 0.25f * clamp01(c.getRainIntensity()) - 0.10f * clamp01(c.getWindIntensity());
                f *= w;
            }
        }
        // strength scales the departure from 1
        return 1.0f - Options.strength * (1.0f - f);
    }

    private static float clamp01(float v) { return v < 0f ? 0f : (v > 1f ? 1f : v); }
}
