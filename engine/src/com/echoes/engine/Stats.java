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
    public static volatile int consecutiveErrors = 0;

    public static String summary() {
        long a = adjusted.get();
        double mean = a == 0 ? 1.0 : factorMicros.get() / 1_000_000.0 / a;
        long c = calls.get();
        double usPerCall = c == 0 ? 0 : nanos.get() / 1000.0 / c;
        return String.format("calls=%d adjusted=%d cacheHits=%d errors=%d meanFactor=%.3f usPerCall=%.2f",
                c, a, cacheHits.get(), errors.get(), mean, usPerCall);
    }

    public static void reset() {
        calls.set(0); adjusted.set(0); cacheHits.set(0); errors.set(0); nanos.set(0); factorMicros.set(0);
        consecutiveErrors = 0;
    }
}
