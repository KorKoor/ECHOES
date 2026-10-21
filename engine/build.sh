#!/usr/bin/env bash
# Builds EchoesEngine.jar WITHOUT the game: compiles against the stubs in ./stubs (compile-only, not shipped).
# At runtime the real game and ZombieBuddy classes are used, so stub signatures must match the game.
# To compile against the real game instead:  ./build.sh /path/to/ProjectZomboid/projectzomboid.jar:/path/to/ZombieBuddy.jar
set -euo pipefail
cd "$(dirname "$0")"
OUT=build; rm -rf "$OUT"; mkdir -p "$OUT/stubs" "$OUT/classes" "$OUT/test"
CP_EXTRA="${1:-}"
if [ -n "$CP_EXTRA" ]; then
  javac --release 17 -d "$OUT/classes" -cp "$CP_EXTRA" $(find src -name '*.java')
else
  javac --release 17 -d "$OUT/stubs" $(find stubs -name '*.java')
  javac --release 17 -d "$OUT/classes" -cp "$OUT/stubs" $(find src -name '*.java')
  javac --release 17 -d "$OUT/test" -cp "$OUT/stubs:$OUT/classes" $(find test -name '*.java')
  java -cp "$OUT/stubs:$OUT/classes:$OUT/test" com.echoes.engine.SelfTest
fi
mkdir -p ../EchoesEngine/42/media/java
jar --create --file ../EchoesEngine/42/media/java/EchoesEngine.jar -C "$OUT/classes" .
echo "built ../EchoesEngine/42/media/java/EchoesEngine.jar"
