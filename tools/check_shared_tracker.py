"""Check shared tracker code and tests across the four released main branches."""

import hashlib
import urllib.error
import urllib.request

REPOSITORIES = ("shortest-path-forever", "adventure-guide-forever", "skillup-forever", "legacy-forever")
SHARED = ("UI/TrackerHost.lua", "tools/fetch_tracker_ui.py", "tests/tracker_host_spec.lua")


def compare(copies, path):
    if len(set(copies.values())) != 1:
        details = "\n".join(f"{repo}: {hashlib.sha256(content).hexdigest()}" for repo, content in copies.items())
        raise SystemExit(f"Shared {path} has drifted between main branches:\n{details}")


def main():
    for path in SHARED:
        copies = {}
        for repo in REPOSITORIES:
            url = f"https://raw.githubusercontent.com/cjber/{repo}/main/{path}"
            try:
                with urllib.request.urlopen(url, timeout=60) as response:
                    copies[repo] = response.read()
            except (urllib.error.URLError, TimeoutError) as error:
                raise SystemExit(f"Could not check shared tracker drift: {url}: {error}") from error
        compare(copies, path)
    print("Shared tracker code, native UI pins and contract tests match across all four main branches.")


if __name__ == "__main__":
    main()
