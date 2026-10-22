package com.echoes.engine;

import me.zed_0xff.zombie_buddy.Patch;

/** zombie.characters.IsoPlayer#addWorldSoundUnlessInvisible(int radius, int volume, boolean stressHumans). */
@Patch(className = "zombie.characters.IsoPlayer", methodName = "addWorldSoundUnlessInvisible")
public class NoisePatch {
    @Patch.OnEnter
    public static void enter(@Patch.This Object self,
                             @Patch.Argument(value = 0, readOnly = false) int radius,
                             @Patch.Argument(value = 1, readOnly = false) int volume) {
        int original = radius;
        radius = NoiseLogic.radius(self, original);
        volume = NoiseLogic.volume(self, volume, original);
    }
}
