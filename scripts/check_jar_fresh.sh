#!/usr/bin/env bash
# Fails if the committed EchoesEngine.jar was not built from the committed Java sources.
set -euo pipefail
cd "$(dirname "$0")/.."
JAR=EchoesEngine/42/media/java/EchoesEngine.jar
WANT="$(cat $(find engine/src -name '*.java' | LC_ALL=C sort) | sha256sum | cut -d' ' -f1)"
# manifest lines are wrapped at 72 bytes (continuation lines start with one space): unfold before reading
HAVE="$(unzip -p "$JAR" META-INF/MANIFEST.MF | tr -d '\r' | sed ':a;N;$!ba;s/\n //g' | sed -n 's/^Echoes-Source-Hash: //p')"
if [ "$WANT" != "$HAVE" ]; then
  echo "STALE JAR: sources hash $WANT but jar manifest says '$HAVE'. Run engine/build.sh and commit the jar." >&2
  exit 1
fi
echo "jar matches sources ($WANT)"
