package com.echoes.engine.patches;

import com.echoes.engine.HearingLogic;

import me.zed_0xff.zombie_buddy.annotations.Patch;

/**
 * zombie.WorldSoundManager#getSoundAttract(WorldSound, IsoZombie) -> float.
 * The two arguments are bound as Object and cast inside HearingLogic, which also catches every failure.
 */
@Patch(className = "zombie.WorldSoundManager", methodName = "getSoundAttract")
public class HearingPatch {
    @Patch.OnExit
    public static void exit(@Patch.Argument(0) Object sound,
                            @Patch.Argument(1) Object zombie,
                            @Patch.Return(readOnly = false) float result) {
        result = HearingLogic.adjust(result, sound, zombie);
    }
}
