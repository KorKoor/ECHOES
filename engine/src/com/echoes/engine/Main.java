package com.echoes.engine;

/** Entry point called by ZombieBuddy when the mod's Java JAR is loaded. Patches are discovered automatically. */
public final class Main {
    private Main() {}

    public static final String VERSION = "0.1.0";

    public static void main(String[] args) {
        System.out.println("[EchoesEngine] v" + VERSION + " loaded (hearing occlusion patch on WorldSoundManager.getSoundAttract)");
    }
}
