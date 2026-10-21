package zombie.characters;

public abstract class IsoGameCharacter extends zombie.iso.IsoMovingObject {
    public boolean isSneaking() { return false; }
    public float getInventoryWeight() { return 0f; }
    public int getMaxWeight() { return 1; }
    public float getWornItemsHearingMultiplier() { return 1f; }
}
