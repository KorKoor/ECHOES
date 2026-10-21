Compile-only stand-ins for the few game and ZombieBuddy classes used by EchoesEngine, written from the
42.20 Javadoc and ZombieBuddy's Patch.java. They are NOT shipped in the jar. At runtime the real classes are used,
so every signature here must match the game exactly (see ../docs/05-java-tier.md).

`Patch` is stubbed in the **2.x package** (`me.zed_0xff.zombie_buddy.Patch`) on purpose: ZombieBuddy 2.x uses it natively and
3.x rewrites it to `me.zed_0xff.zombie_buddy.annotations.Patch` when the jar loads (ZB2Compat), so one jar works on both.
Patch classes must live in exactly the package named by `javaPkgName` (ZombieBuddy drops patches in subpackages).
