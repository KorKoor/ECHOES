package com.echoes.engine;

import java.util.concurrent.atomic.AtomicLong;

/** Counters so the effect (and its cost) can be read from Lua with EchoesEngine_stats(). */
public final class Stats {
    private Stats() {}

    public static final AtomicLong calls = new AtomicLong();
    public static final AtomicLong adjusted = new AtomicLong();
    public static final AtomicLong cacheHits = new AtomicLong();
    public static final AtomicLong errors = new AtomicLong();
    public static final AtomicLong nanos = new AtomicLong();
    /** Sum of applied factors in millionths, for the mean. */
    public static final AtomicLong factorMicros = new AtomicLong();
    public static final AtomicLong spottedCalls = new AtomicLong();
    public static final AtomicLong spottedForced = new AtomicLong();
    public static final AtomicLong spottedSkipped = new AtomicLong();
    public static final AtomicLong noiseCalls = new AtomicLong();
    public static final AtomicLong noiseAdjusted = new AtomicLong();
    public static final AtomicLong noiseRadiusSum = new AtomicLong();
    public static volatile int consecutiveErrors = 0;

    public static String summary() {
        long a = adjusted.get();
        double mean = a == 0 ? 1.0 : factorMicros.get() / 1_000_000.0 / a;
        long c = calls.get();
        double usPerCall = c == 0 ? 0 : nanos.get() / 1000.0 / c;
        return String.format("hearing[calls=%d adjusted=%d cacheHits=%d meanFactor=%.3f usPerCall=%.2f] "
                        + "vision[spotted=%d forced=%d skipped=%d] noise[calls=%d adjusted=%d meanRadius=%.1f] errors=%d",
                c, a, cacheHits.get(), mean, usPerCall,
                spottedCalls.get(), spottedForced.get(), spottedSkipped.get(),
                noiseCalls.get(), noiseAdjusted.get(), noiseCalls.get() == 0 ? 0.0 : noiseRadiusSum.get() / (double) noiseCalls.get(),
                errors.get());
    }

    public static void reset() {
        calls.set(0); noiseCalls.set(0); noiseAdjusted.set(0); noiseRadiusSum.set(0); spottedCalls.set(0); spottedForced.set(0); spottedSkipped.set(0); adjusted.set(0); cacheHits.set(0); errors.set(0); nanos.set(0); factorMicros.set(0);
        consecutiveErrors = 0;
    }
}
