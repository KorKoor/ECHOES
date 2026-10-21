package com.echoes.engine;

/** Runtime switches, changed from Lua through EchoesEngine_set(name, value). All reads are cheap volatile reads. */
public final class Options {
    private Options() {}

    /** Zombies hear less through walls, closed doors and floors. */
    public static volatile boolean hearingOcclusion = true;
    /** Rain and wind reduce how well zombies hear. */
    public static volatile boolean weatherHearing = true;
    /** 0 = no effect, 1 = full effect. Scales how far the factor departs from 1. */
    public static volatile float strength = 1.0f;
    /** Longest line (in tiles) that is walked square by square; longer lines only check both ends. */
    public static volatile int maxLine = 40;
    /** Wall / closed-door loss per blocked edge, per floor of height difference, and indoor/outdoor mismatch. */
    public static volatile float wallFactor = 0.55f;
    public static volatile float levelFactor = 0.6f;
    public static volatile float envelopeFactor = 0.85f;
    /** The factor never goes below this, so a loud enough noise can always be heard. */
    public static volatile float minFactor = 0.08f;
    /** Zombie vision: OFF by default (observe only). When on, hard-to-see players are sometimes not spotted. */
    public static volatile boolean stealth = false;
    public static volatile float stealthStrength = 1.0f;
    /** Closer than this many tiles nothing is concealed; the concealment ramps up over the next stealthRampTiles. */
    public static volatile float stealthNearTiles = 3.0f;
    public static volatile float stealthRampTiles = 10.0f;
    /** Cache lifetime for a (sound, zombie) factor, in milliseconds. */
    public static volatile int cacheMs = 400;

    public static boolean set(String name, double v) {
        boolean known = apply(name, v);
        if (known) HearingLogic.clearCache();
        return known;
    }

    private static boolean apply(String name, double v) {
        switch (name) {
            case "hearingOcclusion": hearingOcclusion = v != 0; return true;
            case "weatherHearing": weatherHearing = v != 0; return true;
            case "stealth": stealth = v != 0; return true;
            case "stealthStrength": stealthStrength = (float) Math.max(0, Math.min(1, v)); return true;
            case "stealthNear": stealthNearTiles = (float) Math.max(0, Math.min(30, v)); return true;
            case "stealthRamp": stealthRampTiles = (float) Math.max(1, Math.min(60, v)); return true;
            case "strength": strength = (float) Math.max(0, Math.min(1, v)); return true;
            case "maxLine": maxLine = (int) Math.max(4, Math.min(120, v)); return true;
            case "wallFactor": wallFactor = (float) Math.max(0.05, Math.min(1, v)); return true;
            case "levelFactor": levelFactor = (float) Math.max(0.05, Math.min(1, v)); return true;
            case "envelopeFactor": envelopeFactor = (float) Math.max(0.05, Math.min(1, v)); return true;
            case "minFactor": minFactor = (float) Math.max(0.0, Math.min(1, v)); return true;
            case "cacheMs": cacheMs = (int) Math.max(0, Math.min(5000, v)); return true;
            default: return false;
        }
    }
}
