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
        int id();
    }

    public static float adjust(float result, Object soundObj, Object zomObj) {
        if (!(Options.hearingOcclusion || Options.weatherHearing) || result <= 0f) return result;
        if (Stats.consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) return result;
        try {
            final IsoZombie z = (IsoZombie) zomObj;
            if (z == null) return result;
            return adjustCore(result, (WorldSoundManager.WorldSound) soundObj, new ZView() {
                public IsoGridSquare square() { return z.getCurrentSquare(); }
                public int id() { return z.getOnlineID(); }
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

            long key = (((long) s.x * 73856093L) ^ ((long) s.y * 19349663L) ^ ((long) s.z * 83492791L)) << 16
                    ^ (z.id() & 0xffffL);
            long now = System.currentTimeMillis();
            Entry e = cache.get(key);
            float f;
            if (e != null && e.expires > now) {
                f = e.factor;
                Stats.cacheHits.incrementAndGet();
            } else {
                f = compute(s, z);
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

    private static float compute(WorldSoundManager.WorldSound s, ZView z) {
        float f = 1.0f;
        if (Options.hearingOcclusion) {
            IsoGridSquare zsq = z.square();
            if (zsq != null) f *= Occlusion.factor(zsq.getX(), zsq.getY(), zsq.getZ(), s.x, s.y, s.z);
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
