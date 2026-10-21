package com.echoes.engine;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * zombie.WorldSoundManager#addSound(Object source, int x, int y, int z, int radius, int volume, ...): every overload
 * starts with the same six parameters, so source (0) and radius (4) are bound by index. Observation only.
 */
@Patch(className = "zombie.WorldSoundManager", methodName = "addSound")
public class LoudPatch {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Object source, @Patch.Argument(4) int radius) {
        LoudLogic.observe(source, radius);
    }
}
