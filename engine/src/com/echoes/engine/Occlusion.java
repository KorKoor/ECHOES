package com.echoes.engine;

import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;

/**
 * Rough physical model of how much of a sound gets from point A to point B: every blocked edge between squares
 * (wall, closed door or window, as reported by the game's own IsoGridSquare.isBlockedTo) attenuates, each floor of
 * height difference attenuates, and crossing the building envelope attenuates a little.
 * Returns a factor in [minFactor, 1]. It never reports a position, only a number.
 */
public final class Occlusion {
    private Occlusion() {}

    /** Factor between two world points (tile coordinates). 1.0 if the world is not available. */
    public static float factor(int x0, int y0, int z0, int x1, int y1, int z1) {
        IsoWorld world = IsoWorld.instance;
        IsoCell cell = world == null ? null : world.getCell();
        if (cell == null) return 1.0f;

        int barriers = countBarriers(cell, x0, y0, z0, x1, y1);
        float f = (float) Math.pow(Options.wallFactor, barriers);

        int dz = Math.abs(z1 - z0);
        if (dz > 0) f *= (float) Math.pow(Options.levelFactor, dz);

        IsoGridSquare a = cell.getGridSquare(x0, y0, z0);
        IsoGridSquare b = cell.getGridSquare(x1, y1, z1);
        if (a != null && b != null && a.isOutside() != b.isOutside()) f *= Options.envelopeFactor;

        return Math.max(Options.minFactor, Math.min(1.0f, f));
    }

    /** Blocked edges along the straight line; squares that are not loaded count as half a barrier. */
    static int countBarriers(IsoCell cell, int x0, int y0, int z, int x1, int y1) {
        int dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
        int steps = Math.max(dx, dy);
        int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
        int err = dx - dy;
        int x = x0, y = y0;

        int half = Math.max(2, Options.maxLine / 2);
        boolean skipMiddle = steps > Options.maxLine;

        int barriers = 0;
        int unloaded = 0;
        IsoGridSquare prev = cell.getGridSquare(x, y, z);
        for (int i = 0; i < steps; i++) {
            int e2 = 2 * err;
            if (e2 > -dy) { err -= dy; x += sx; }
            if (e2 < dx) { err += dx; y += sy; }

            // Long lines: walls close to either end matter most; skip the middle.
            if (skipMiddle && i >= half && i < steps - half) {
                prev = null;
                continue;
            }
            IsoGridSquare cur = cell.getGridSquare(x, y, z);
            if (prev != null && cur != null) {
                if (prev.isBlockedTo(cur)) barriers++;
            } else if (cur == null && prev != null) {
                unloaded++;
            }
            prev = cur;
        }
        return barriers + unloaded / 2;
    }
}
