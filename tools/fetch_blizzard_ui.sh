#!/usr/bin/env bash
# Fetch the Blizzard UI source tests/ui_client.lua runs against, pinned and checksummed, into tools/.cache.
set -euo pipefail

cd "$(dirname "$0")/.."
# Gethe/wow-ui-source 1.60.1 (70425), the client build the data is pinned to.
revision=b401e0332adfbf0460d319b06d8ea29279a941f1
root=tools/.cache/blizzard-ui
while read -r sum file; do
	path=$root/Interface/AddOns/$file
	if [[ ! -f "$path" ]]; then
		mkdir -p "$(dirname "$path")"
		curl -fsSLo "$path.tmp" "https://raw.githubusercontent.com/Gethe/wow-ui-source/$revision/Interface/AddOns/$file"
		mv "$path.tmp" "$path"
	fi
	echo "$sum  $path" | sha256sum --quiet -c -
done <<'FILES'
28ad9798f0f68d8d5ddd26f99ec5f8ef5ceebacec9fd941f25b05406336335b7 Blizzard_SharedXML/Spinner.lua
5cb19b521d4073eee01c73a3f22fe0fbcf9a0f84ba389e7bb301fc2b057e4630 Blizzard_SharedXML/Spinner.xml
0e7c53d743f81543f0ebb8263a4b232e12bb5799b16eddab8aa3ea97c71db134 Blizzard_SharedMapDataProviders/FlightPointDataProvider.lua
4f8cb2e7111bed235f2ba3f028fb1cba8e64da0f9c067e70a746aaa202098ab1 Blizzard_SharedMapDataProviders/WaypointLocationDataProvider.lua
be7610338144886df30a6ad6ad597981f1f49ab309644024c0d9574fab5776ab Blizzard_SharedMapDataProviders/QuestDataProvider.lua
22d116c7d374116623ca1f4adab12a5dea48a6f94485606712578b96a59df7a0 Blizzard_MapCanvas/MapCanvas_DataProviderBase.lua
82c415d02d28565636e8dda2954081fbdd3218b68b8f42cdf3c324eedcff4a01 Blizzard_POIButton/POIButton.lua
9ac0c9bd4b0cd15e34d0a27ec09a7c873bc5f0afe4cd24d6b9cc54bc04851d89 Blizzard_ObjectiveTracker/Blizzard_QuestObjectiveTracker.lua
bec7f169fecd9d1821bd6c9caa7bb31eae71f0e230f68b6b34ac89ba42fb8c3e Blizzard_ObjectiveTracker/Camelot/Blizzard_QuestObjectiveTrackerOverride.lua
f1339cc12ba2b4c0fc5c90fcdc96789691a34b460857e78995eafc095688c43b Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua
FILES
