package com.echoes.engine;

import zombie.WorldSoundManager;
import zombie.characters.IsoZombie;
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
    static class Zed extends IsoZombie {
        final Sq sq; final short id;
        Zed(Sq sq, int id) { this.sq = sq; this.id = (short) id; }
        @Override public zombie.iso.IsoGridSquare getCurrentSquare() { return sq; }
        @Override public short getOnlineID() { return id; }
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
        float adjOpen = HearingLogic.adjust(100f, s, inOpen);
        float adjWalls = HearingLogic.adjust(100f, s, behindWalls);
        check("zombie in the open keeps full attraction (" + adjOpen + ")", Math.abs(adjOpen - 100f) < 1e-3);
        check("zombie behind two walls is less attracted (" + adjWalls + ")", adjWalls < 40f && adjWalls > 5f);
        check("zero stays zero", HearingLogic.adjust(0f, s, behindWalls) == 0f);
        check("bad argument types never throw", HearingLogic.adjust(50f, "x", "y") == 50f);

        Options.set("strength", 0.5);
        float half = HearingLogic.adjust(100f, s, behindWalls);
        check("strength 0.5 halves the reduction (" + half + ")", half > adjWalls && half < 100f);
        Options.set("strength", 1.0);

        System.out.println(Stats.summary());
        System.out.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        if (failures > 0) System.exit(1);
    }
}
