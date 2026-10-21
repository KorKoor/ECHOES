package zombie;

public class WorldSoundManager {
    public static class WorldSound {
        public Object source;
        public int life;
        public int radius;
        public int volume;
        public int x;
        public int y;
        public int z;
        public float zombieIgnoreDist;
        public boolean sourceIsZombie;
        public boolean sourceIsPlayer;
    }
    public WorldSound addSound(Object source, int x, int y, int z, int radius, int volume) { return null; }
    public float getSoundAttract(WorldSound sound, zombie.characters.IsoZombie zom) { return 0f; }
}
