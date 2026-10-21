package com.echoes.engine.patches;

import com.echoes.engine.VisionLogic;

import me.zed_0xff.zombie_buddy.annotations.Patch;

/** zombie.characters.IsoZombie#spotted(IsoMovingObject, boolean) -> void. Returning true skips the original. */
@Patch(className = "zombie.characters.IsoZombie", methodName = "spotted")
public class VisionPatch {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.This Object zombie,
                                @Patch.Argument(0) Object other,
                                @Patch.Argument(1) boolean forced) {
        return VisionLogic.shouldSkip(zombie, other, forced);
    }
}
