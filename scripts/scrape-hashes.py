#!/usr/bin/env python3
"""Refresh config/pathfinder.json from the live web player.

Mirrors the device-side scrape in native-player/ios/Pathfinder.cpp: the page lists its
bundles, the main bundle holds most persisted-query hashes and the chunk map, and the search
route chunk holds the search operations. Writes only the operations the app uses, so the file
stays small and diffs stay readable. Exit code 0 whether or not anything changed; prints
"changed" or "unchanged" on the last line for the workflow.
"""
import json, re, sys, urllib.request, datetime, pathlib

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
WANTED = ["searchDesktop", "home", "libraryV3", "browseAll", "queryArtistOverview", "fetchPlaylist", "getAlbum",
          "addToLibrary", "removeFromLibrary", "addToPlaylist"]
PATTERN = re.compile(r'"([A-Za-z0-9_]+)","(?:query|mutation)","([0-9a-f]{64})"')

def get(url, limit=16 * 1024 * 1024):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read(limit).decode("utf-8", "replace")

def main():
    page = get("https://open.spotify.com/")
    m = re.search(r'/cdn/build/web-player/web-player\.[0-9a-f]+\.js', page)
    if not m:
        print("main bundle not found", file=sys.stderr); return 1
    bundle = get("https://open.spotifycdn.com" + m.group(0))
    found = dict(PATTERN.findall(bundle))
    name = bundle.find('"xpui-routes-search"')
    if name >= 0:
        chunk_id = re.search(r'(\d+):"xpui-routes-search"', bundle).group(1)
        for h in re.findall(r'(?<![0-9])' + chunk_id + r':"([0-9a-f]{8})"', bundle):
            try:
                found.update(PATTERN.findall(get(f"https://open.spotifycdn.com/cdn/build/web-player/xpui-routes-search.{h}.js")))
            except Exception:
                continue
            if "searchDesktop" in found:
                break
    path = pathlib.Path(__file__).resolve().parent.parent / "config" / "pathfinder.json"
    current = json.loads(path.read_text()) if path.exists() else {}
    updated = dict(current)
    changed = False
    for op in WANTED:
        if op in found and current.get(op) != found[op]:
            updated[op] = found[op]; changed = True
    missing = [op for op in WANTED if op not in found]
    if missing:
        print("not found in this build:", ", ".join(missing), file=sys.stderr)
    if changed:
        updated["updated"] = datetime.date.today().isoformat()
        updated.setdefault("note", "Persisted-query hashes of web player operations. The app fetches this file when a cached hash stops working. Keys are operation names; only 64-hex values are used.")
        path.write_text(json.dumps(updated, indent=2) + "\n")
    print("changed" if changed else "unchanged")
    return 0

if __name__ == "__main__":
    sys.exit(main())
