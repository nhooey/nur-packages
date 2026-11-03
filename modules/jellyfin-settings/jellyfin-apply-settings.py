"""Apply declared Jellyfin settings through Jellyfin's REST API.

Usage: jellyfin-apply-settings SETTINGS_JSON [--if-changed STAMP]
           [--secretspec PATH] [--manifest PATH] [--dry-run | --diff]

SETTINGS_JSON holds:
  {"url": "http://localhost:8096",
   "encoding": {"HardwareAccelerationType": "videotoolbox", ...},
   "users": {"<name>": {"SubtitleMode": "Always", ...}},
   "libraries": {"<name>": {"type": "movies", "paths": ["~/Video/Movies"]}}}

Only the keys listed are changed: the encoding configuration and each
user's configuration are read, the listed keys set, and the whole posted
back. A library missing from Jellyfin is added and scanned; one that exists
gets any listed path it lacks. Nothing is ever removed.

--diff changes nothing: it prints each declared key whose value in Jellyfin
differs, such as one changed in the web interface, and each declared
library or path Jellyfin lacks. --dry-run prints the requests it would send.

The API key comes from `secretspec get JELLYFIN_API_KEY` with the given
manifest, and is never printed. With --if-changed, nothing runs when STAMP
already holds the settings' hash, and STAMP is written after a successful
run. When the key can't be read or Jellyfin doesn't answer, it prints one
line and exits 0, so a Home Manager switch carries on.

The planning is pure: plan() maps what Jellyfin holds and what is declared
to the drift found and the requests that remove it. main() does the I/O.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

# A request: (method, path, body, note). A plan: (drift, requests), both
# tuples of strings and requests.
EMPTY = ((), ())


def join(*plans):
    """The plans' drift and requests, in order."""
    return (tuple(d for p in plans for d in p[0]),
            tuple(r for p in plans for r in p[1]))


def changed(current, wanted):
    """The wanted keys whose value differs from current's."""
    return {k: v for k, v in wanted.items() if current.get(k) != v}


def config_plan(label, current, wanted, path):
    """Drift in one configuration, and the one POST that sets it."""
    diff = changed(current, wanted)
    drift = tuple(f"{label}.{k}: Jellyfin has {current.get(k)!r}, declared {diff[k]!r}"
                  for k in sorted(diff))
    requests = ((("POST", path, {**current, **diff},
                  f"{label}: set {', '.join(sorted(diff))}"),) if diff else ())
    return drift, requests


def encoding_plan(current, wanted):
    """The plan for the encoding configuration."""
    return config_plan("encoding", current, wanted, "/System/Configuration/encoding")


def users_plan(users, wanted):
    """The plan for each declared user that Jellyfin has, by name."""
    by_name = {u["Name"]: u for u in users}
    return join(*(
        config_plan(f"users.{name}", by_name[name]["Configuration"], settings,
                    f"/Users/{by_name[name]['Id']}/Configuration")
        if name in by_name else ((f"users.{name}: no such Jellyfin user; skipped",), ())
        for name, settings in sorted(wanted.items())))


def add_library(name, lib_type, paths):
    query = urllib.parse.urlencode(
        {"name": name, "collectionType": lib_type, "refreshLibrary": "false"})
    return (("POST", f"/Library/VirtualFolders?{query}",
             {"LibraryOptions": {"PathInfos": [{"Path": p} for p in paths]}},
             f"library {name}: added"),)


def add_paths(name, missing):
    return tuple(("POST", "/Library/VirtualFolders/Paths?refreshLibrary=false",
                  {"Name": name, "PathInfo": {"Path": p}},
                  f"library {name}: added path {p}") for p in missing)


def library_plan(name, lib, existing, expand):
    paths = tuple(expand(p) for p in lib["paths"])
    if name not in existing:
        return (f"libraries.{name}: missing in Jellyfin",), add_library(name, lib["type"], paths)
    missing = tuple(p for p in paths if p not in existing[name])
    return (tuple(f"libraries.{name}: lacks path {p}" for p in missing),
            add_paths(name, missing))


def libraries_plan(folders, wanted, expand):
    """The plan for the declared libraries, then one scan if any changed."""
    existing = {f["Name"]: f.get("Locations", []) for f in folders}
    drift, requests = join(*(library_plan(name, lib, existing, expand)
                             for name, lib in sorted(wanted.items())))
    scan = (("POST", "/Library/Refresh", None, "libraries: scan started"),) if requests else ()
    return drift, requests + scan


def plan(state, settings, expand):
    """Everything to change, from Jellyfin's state and the declared settings."""
    return join(encoding_plan(state["encoding"], settings.get("encoding", {})),
                users_plan(state["users"], settings.get("users", {})),
                libraries_plan(state["folders"], settings.get("libraries", {}), expand))


def call(url, key, method, path, body=None):
    """One API request; the decoded JSON reply, or None."""
    req = urllib.request.Request(
        url + path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": f'MediaBrowser Token="{key}"',
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
        return json.loads(data) if data else None


def read_state(get):
    return {"encoding": get("/System/Configuration/encoding"),
            "users": get("/Users"),
            "folders": get("/Library/VirtualFolders")}


def warn(msg):
    print(f"jellyfin-apply-settings: {msg}", file=sys.stderr)


def read_key(secretspec, manifest):
    """The API key through SecretSpec, or None with a warning."""
    try:
        out = subprocess.run(
            [secretspec, "--file", manifest, "get", "JELLYFIN_API_KEY",
             "--reason", "jellyfin-apply-settings: apply the declared Jellyfin settings"],
            capture_output=True, text=True, timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        warn(f"couldn't run secretspec ({e.__class__.__name__}); nothing applied")
        return None
    if out.returncode != 0 or not out.stdout.strip():
        warn("couldn't read JELLYFIN_API_KEY through SecretSpec; nothing applied")
        return None
    return out.stdout.strip()


def answers(url):
    try:
        urllib.request.urlopen(url + "/System/Info/Public", timeout=5).read()
        return True
    except (urllib.error.URLError, OSError):
        return False


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("settings")
    p.add_argument("--if-changed", metavar="STAMP")
    p.add_argument("--secretspec", default="secretspec")
    p.add_argument("--manifest",
                   default=os.path.expanduser("~/.config/secretspec/jellyfin.toml"))
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--diff", action="store_true")
    return p.parse_args(argv)


def read_stamp(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def write_stamp(path, digest):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(digest + "\n")


def main(argv):
    a = parse_args(argv)
    with open(a.settings, "rb") as f:
        raw = f.read()
    digest = hashlib.sha256(raw).hexdigest()
    if a.if_changed and not a.diff and read_stamp(a.if_changed) == digest:
        return 0
    settings = json.loads(raw)
    url = settings.get("url", "http://localhost:8096").rstrip("/")

    if not answers(url):
        warn(f"Jellyfin doesn't answer at {url}; nothing applied, will retry next switch")
        return 0
    key = read_key(a.secretspec, a.manifest)
    if key is None:
        return 0

    try:
        drift, requests = plan(read_state(lambda path: call(url, key, "GET", path)),
                               settings, os.path.expanduser)
        if a.diff:
            print("\n".join(drift) if drift else "Jellyfin matches the declared settings")
            return 0
        for d in drift:
            if d.endswith("; skipped"):
                warn(d)
        for method, path, body, note in requests:
            if a.dry_run:
                print(f"would {method} {path}")
            else:
                call(url, key, method, path, body)
                print(note)
    except urllib.error.HTTPError as e:
        warn(f"Jellyfin refused a request: HTTP {e.code} {e.reason}; stopped")
        return 0

    if a.if_changed and not a.dry_run:
        write_stamp(a.if_changed, digest)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
