#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
# The annotation checkout and the LuaLS version come from tools/toolchain.json, synced from ForeverCore: the one
# place either is pinned, and the file CI installs LuaLS from.
pins=$(python3 -c 'import json; t = json.load(open("tools/toolchain.json"))["tools"]; print(t["annotations"]["commit"], t["luals"]["version"])')
revision=${pins% *}
luals=${pins#* }
library=.types/vscode-wow-api
mkdir -p .types
# Serialize the existence check and installation, including validation of an existing checkout.
exec 9>.types/.annotations.lock
flock -x 9
if [[ ! -e "$library" ]]; then
	checkout=$(mktemp -d .types/wow-api.XXXXXX)
	trap 'command rm -rf -- "$checkout"' EXIT
	git init -q "$checkout"
	git -C "$checkout" remote add origin "${WOW_API_REMOTE:-https://github.com/Ketho/vscode-wow-api.git}"
	git -C "$checkout" fetch --quiet --depth=1 origin "$revision"
	git -C "$checkout" checkout --quiet --detach FETCH_HEAD
	mv -T -- "$checkout" "$library"
	trap - EXIT
fi
if [[ $(git -C "$library" rev-parse HEAD) != "$revision" ]] ||
	[[ -n $(git -C "$library" status --porcelain) ]]; then
	echo "Expected clean WoW annotations at $revision in $library" >&2
	exit 1
fi
flock -u 9
exec 9>&-
if [[ $(lua-language-server --version) != "$luals" ]]; then
	echo "Install lua-language-server $luals to match CI." >&2
	exit 1
fi

python3 tools/forever_tools/sync.py check
python3 tools/typecheck_coverage.py
python3 -m unittest discover -s tests -p 'test_typecheck.py'
python3 -m unittest discover -s tools -p '*_test.py'
python3 tools/lint_multivalue.py
python3 tools/lint_art.py
python3 tools/lint_secret.py
python3 tools/lint_client_calls.py
python3 tools/check_font_glyphs.py
python3 tools/check_editorconfig.py
# --release: a shipped locale short of Locales/phrases.txt fails the PR, not the release.
python3 tools/check_locales.py --release
python3 tools/check_family.py
python3 tools/check_store_page.py
# An interrupted check must never leave a stale report looking like this run's result.
report=.types/diagnostics.json
command rm -f -- "$report"
status=0
lua-language-server --check . --checklevel=Information --check_format=json \
	--check_out_path="$report" --logpath=.types/luals-log || status=$?
python3 tools/typecheck_report.py "$report"
exit "$status"
