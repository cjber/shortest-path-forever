#!/usr/bin/env bash
# Bake local client terrain with pinned TrinityCore tools. All output stays under OUT.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${OUT:-$HERE/work}")
WOW=$(realpath -m "${WOW:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft}")
PRODUCT=${PRODUCT:-wow_classic_beta}
MAPS=${MAPS:-"0 1 2991"}
THREADS=${THREADS:-8}
JOBS=${JOBS:-6}
TRINITY_REV=e3916b2adcf2f8a70ae33817fc57b6c0266e2fb0
case "$OUT/" in
"$WOW/"*)
	echo "OUT must be outside the game installation" >&2
	exit 1
	;;
esac
if [ "${BUILD_ONLY:-0}" != 1 ]; then
	test -f "$WOW/.build.info"
fi
mkdir -p "$OUT"
SOURCE=$OUT/TrinityCore
PATCH=$HERE/trinitycore.patch
CLIENT_PATCH=$HERE/trinitycore-client.patch
NAV_PATCH=$HERE/trinitycore-nav.patch
if [ ! -d "$SOURCE" ]; then
	git init -q "$SOURCE"
	git -C "$SOURCE" remote add origin https://github.com/TrinityCore/TrinityCore.git
	git -C "$SOURCE" fetch -q --depth 1 origin "$TRINITY_REV"
	git -C "$SOURCE" sparse-checkout set src/tools src/common src/genrev dep cmake sql/base/dev
	git -C "$SOURCE" checkout -q --detach FETCH_HEAD
fi
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$TRINITY_REV"
if git -C "$SOURCE" diff --quiet; then
	git -C "$SOURCE" apply "$CLIENT_PATCH" "$PATCH" "$NAV_PATCH"
fi
# A changed patch or a hand-edited source tree needs a fresh output directory.
source_diff=(git -C "$SOURCE" diff --binary --full-index --no-ext-diff --no-textconv --diff-algorithm=myers --unified=1)
"${source_diff[@]}" -- . ':(exclude)src/common/mmaps_common' ':(exclude)src/tools/mmaps_generator' ':(exclude)src/tools/extractor_common' | cmp -s "$PATCH" - || {
	echo "TrinityCore source differs from the pinned patch; use a fresh OUT" >&2
	exit 1
}
"${source_diff[@]}" -- src/tools/extractor_common | cmp -s "$CLIENT_PATCH" - || {
	echo "TrinityCore client source differs from the pinned patch; use a fresh OUT" >&2
	exit 1
}
"${source_diff[@]}" -- src/common/mmaps_common src/tools/mmaps_generator | cmp -s "$NAV_PATCH" - || {
	echo "TrinityCore navigation source differs from the pinned patch; use a fresh OUT" >&2
	exit 1
}
cmake -S "$SOURCE" -B "$OUT/build" -G Ninja -DTOOLS=ON -DSERVERS=OFF -DSCRIPTS=none \
	-DBUILD_TESTING=OFF -DUSE_COREPCH=OFF -DNOJEM=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$OUT/build" --target mapextractor vmap4extractor vmap4assembler mmaps_generator -j "$JOBS"
python3 "$HERE/check_hazards.py" "$SOURCE" "$OUT/build"
if [ "${BUILD_ONLY:-0}" = 1 ]; then
	exit 0
fi
read -r -a maps <<<"$MAPS"
args=(--wow "$WOW" --product "$PRODUCT" --out "$OUT" --bin "$OUT/build/bin/Release/bin"
	--maps "${maps[@]}" --threads "$THREADS" --jobs "$JOBS" --rev "$TRINITY_REV"
	--patch "$CLIENT_PATCH" --patch "$PATCH" --patch "$NAV_PATCH"
	--name "0=Eastern Kingdoms" --name "1=Kalimdor" --name "2991=Zephras Isle")
if [ -n "${ROWS:-}" ]; then
	read -r -a rows <<<"$ROWS"
	args+=(--rows "${rows[@]}")
fi
if [ -n "${COLS:-}" ]; then
	read -r -a cols <<<"$COLS"
	args+=(--cols "${cols[@]}")
fi
python3 "$HERE/trinity.py" "${args[@]}"
