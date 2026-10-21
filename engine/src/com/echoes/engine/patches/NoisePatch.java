package com.echoes.engine.patches;

import com.echoes.engine.NoiseLogic;

import me.zed_0xff.zombie_buddy.annotations.Patch;

/** zombie.characters.IsoPlayer#addWorldSoundUnlessInvisible(int radius, int volume, boolean stressHumans). */
@Patch(className = "zombie.characters.IsoPlayer", methodName = "addWorldSoundUnlessInvisible")
public class NoisePatch {
    @Patch.OnEnter
    public static void enter(@Patch.This Object self,
                             @Patch.Argument(value = 0, readOnly = false) int radius,
                             @Patch.Argument(value = 1, readOnly = false) int volume) {
        int[] r = NoiseLogic.adjust(self, radius, volume);
        radius = r[0];
        volume = r[1];
    }
}
