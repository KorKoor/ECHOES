package zombie.iso;

public class IsoGridSquare {
    public int getX() { return 0; }
    public int getY() { return 0; }
    public int getZ() { return 0; }
    public boolean isBlockedTo(IsoGridSquare other) { return false; }
    public boolean isOutside() { return false; }
    public float getLightLevel(int playerIndex) { return 1f; }
}
