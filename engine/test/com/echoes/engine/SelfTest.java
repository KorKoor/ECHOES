package com.echoes.engine;

import zombie.WorldSoundManager;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.weather.ClimateManager;

/** Logic checks against a tiny fake world (stubs). NOT a game test. */
public class SelfTest {
    static int failures = 0;
    static void check(String name, boolean ok) {
        System.out.println((ok ? "PASS " : "FAIL ") + name);
        if (!ok) failures++;
    }

    static class Sq extends IsoGridSquare {
        final int x, y, z; final boolean outside; final Fake w;
        Sq(Fake w, int x, int y, int z) { this.w = w; this.x = x; this.y = y; this.z = z; this.outside = x < 0 || x > 20; }
        @Override public int getX() { return x; }
        @Override public int getY() { return y; }
        @Override public int getZ() { return z; }
        @Override public boolean isOutside() { return outside; }
        @Override public boolean isBlockedTo(IsoGridSquare o) {
            // a wall between x=5 and x=6 and another between x=9 and x=10
            int a = x, b = o.getX();
            return (a == 5 && b == 6) || (a == 6 && b == 5) || (a == 9 && b == 10) || (a == 10 && b == 9);
        }
    }
    static class Fake extends IsoCell {
        @Override public IsoGridSquare getGridSquare(int x, int y, int z) { return new Sq(this, x, y, z); }
    }
    static class World extends IsoWorld {
        final Fake cell = new Fake();
        @Override public IsoCell getCell() { return cell; }
    }
    static class Zed implements HearingLogic.ZView {
        final Sq sq;
        Zed(Sq sq, int ignoredId) { this.sq = sq; }
        public zombie.iso.IsoGridSquare square() { return sq; }
    }
    static class Climate extends ClimateManager {
        float rain = 0f;
        @Override public float getRainIntensity() { return rain; }
        @Override public float getWindIntensity() { return 0f; }
    }

    public static void main(String[] a) throws Exception {
        World w = new World();
        IsoWorld.instance = w;

        float open = Occlusion.factor(0, 0, 0, 4, 0, 0);
        float oneWall = Occlusion.factor(0, 0, 0, 7, 0, 0);
        float twoWalls = Occlusion.factor(0, 0, 0, 12, 0, 0);
        float otherFloor = Occlusion.factor(0, 0, 0, 4, 0, 1);
        check("open air = 1", Math.abs(open - 1f) < 1e-6);
        check("one wall ~ 0.55 (got " + oneWall + ")", Math.abs(oneWall - 0.55f) < 1e-4);
        check("two walls ~ 0.30 (got " + twoWalls + ")", Math.abs(twoWalls - 0.3025f) < 1e-3);
        check("one floor ~ 0.6 (got " + otherFloor + ")", Math.abs(otherFloor - 0.6f) < 1e-4);
        check("monotonic: more walls, less sound", open > oneWall && oneWall > twoWalls);
        float env = Occlusion.factor(15, 0, 0, 25, 0, 0); // inside -> outside, no walls on this stretch
        check("envelope crossing ~ 0.85 (got " + env + ")", Math.abs(env - 0.85f) < 1e-4);

        // Hearing patch logic
        WorldSoundManager.WorldSound s = new WorldSoundManager.WorldSound();
        s.x = 0; s.y = 0; s.z = 0;
        Zed behindWalls = new Zed(new Sq(w.cell, 12, 0, 0), 1);
        Zed inOpen = new Zed(new Sq(w.cell, 3, 0, 0), 2);
        float adjOpen = HearingLogic.adjustCore(100f, s, inOpen);
        float adjWalls = HearingLogic.adjustCore(100f, s, behindWalls);
        check("zombie in the open keeps full attraction (" + adjOpen + ")", Math.abs(adjOpen - 100f) < 1e-3);
        check("zombie behind two walls is less attracted (" + adjWalls + ")", adjWalls < 40f && adjWalls > 5f);
        // Two zombies with the SAME id (or -1 in single player) at different places must not share a cached factor.
        Zed sameIdOpen = new Zed(new Sq(w.cell, 3, 1, 0), -1);
        Zed sameIdWalls = new Zed(new Sq(w.cell, 12, 1, 0), -1);
        float a1 = HearingLogic.adjustCore(100f, s, sameIdOpen);
        float a2 = HearingLogic.adjustCore(100f, s, sameIdWalls);
        check("cache does not mix zombies at different places (" + a1 + " vs " + a2 + ")", a1 > 90f && a2 < 40f);
        check("zero stays zero", HearingLogic.adjustCore(0f, s, behindWalls) == 0f);
        check("bad argument types never throw", HearingLogic.adjust(50f, "x", "y") == 50f);

        Options.set("strength", 0.5);
        float half = HearingLogic.adjustCore(100f, s, behindWalls);
        check("strength 0.5 halves the reduction (" + half + ")", half > adjWalls && half < 100f);
        Options.set("strength", 1.0);

        // Vision concealment maths (pure function)
        class V implements VisionLogic.View {
            boolean player = true, sneak = false, facing = true; float light = 1f; double dist = 10;
            public boolean targetIsPlayer() { return player; }
            public boolean sneaking() { return sneak; }
            public float light() { return light; }
            public double distance() { return dist; }
            public boolean zombieFacing() { return facing; }
        }
        V v = new V();
        check("lit, standing, facing, far: no concealment", VisionLogic.concealment(v) == 0.0);
        v.sneak = true;
        double sneakFar = VisionLogic.concealment(v);
        check("sneaking far away conceals (" + sneakFar + ")", sneakFar > 0.1 && sneakFar <= 0.9);
        v.light = 0.0f; v.facing = false;
        double worst = VisionLogic.concealment(v);
        check("sneak + dark + not facing is capped at 0.9 and higher (" + worst + ")", worst > sneakFar && worst <= 0.9);
        v.dist = 2;
        check("close range is never concealed", VisionLogic.concealment(v) == 0.0);
        v.dist = 100; v.player = false;
        check("non-player targets are never concealed", VisionLogic.concealment(v) == 0.0);
        check("shouldSkip is false when stealth is off", !VisionLogic.shouldSkip("z", "o", false));
        check("forced sightings are never skipped", !VisionLogic.shouldSkip("z", "o", true));
        // A decision holds for DECISION_MS: repeated calls cannot defeat concealment.
        boolean first = VisionLogic.decide(42, 1.0, 10_000);
        boolean again = VisionLogic.decide(42, 1.0, 10_000 + 1000);
        check("vision: p=1 conceals and the decision holds within the window", first && again);
        VisionLogic.decide(43, 0.0, 10_000);
        check("vision: p=0 never conceals", !VisionLogic.decide(43, 0.0, 10_001));
        check("spotted calls are counted", Stats.spottedCalls.get() >= 2);

        // Player noise maths
        check("noise: light load = 1.0", NoiseLogic.radiusFactor(0.3f) == 1.0f && NoiseLogic.radiusFactor(0.5f) == 1.0f);
        check("noise: full load = 1.25 radius", Math.abs(NoiseLogic.radiusFactor(1.0f) - 1.25f) < 1e-6);
        check("noise: over capacity is capped", Math.abs(NoiseLogic.radiusFactor(3.0f) - 1.25f) < 1e-6);
        check("noise: volume +15 % at full load", Math.abs(NoiseLogic.volumeFactor(1.0f) - 1.15f) < 1e-6);
        int[] same = NoiseLogic.adjust("not a player", 20, 10);
        check("noise: non-player or observe-only leaves values", same[0] == 20 && same[1] == 10);
        check("noise: calls are counted", Stats.noiseCalls.get() >= 1);

        // Loud-noise bookkeeping
        LoudLogic.reset();
        check("loud: nothing recorded yet", LoudLogic.msSince(1000) == -1);
        LoudLogic.record(10, 1000);
        check("loud: quiet noise ignored", LoudLogic.msSince(2000) == -1);
        LoudLogic.record(80, 5000);
        check("loud: gunshot recorded (" + LoudLogic.msSince(7500) + " ms ago)", LoudLogic.msSince(7500) == 2500 && LoudLogic.radius() == 80);
        LoudLogic.observe("not a player", 90);
        check("loud: non-player source never throws or records", LoudLogic.msSince(7500) == 2500);

        System.out.println(Stats.summary());
        System.out.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        if (failures > 0) System.exit(1);
    }
}
