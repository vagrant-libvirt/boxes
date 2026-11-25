#!/usr/bin/env python3
"""Build the Vagrant box catalog served from GitHub Pages.

The releases of this repository are the source of truth. A release tagged
``<name>-<X.Y.Z>`` carrying an asset ``<name>-<X.Y.Z>.libvirt.box`` (plus the
sidecar ``.sha256`` written by scripts/publish-box.sh) becomes one version of
the box ``<namespace>/<name>`` in ``site/<name>.json``.

Usage: scripts/build-catalog.py [--repo OWNER/REPO] [--out site]
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

TAG = re.compile(r"^(?P<name>[a-z0-9][a-z0-9._-]*)-(?P<version>\d+\.\d+\.\d+)$")
ASSET = ".libvirt.box"
ARCHITECTURE = "amd64"


def releases(repo):
    """Yield every release of repo as a dict."""
    out = subprocess.run(
        ["gh", "api", "--paginate", "--jq", ".[] | @json", f"repos/{repo}/releases"],
        check=True, capture_output=True, text=True,
    ).stdout
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        release = json.loads(line)
        if isinstance(release, str):  # gh quoted the @json string
            release = json.loads(release)
        yield release


def fetch(url):
    request = urllib.request.Request(url, headers={"Accept": "application/octet-stream"})
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request) as response:
        return response.read().decode()


def checksum(assets, name):
    """Return the sha256 recorded in the sidecar asset for name, if any."""
    sidecar = assets.get(name + ".sha256")
    if sidecar is None:
        print(f"warning: {name} has no .sha256 sidecar, publishing it unverified",
              file=sys.stderr)
        return None
    return fetch(sidecar["url"]).split()[0]


def build(repo, config):
    """Collect the released box versions, newest first, keyed by box name."""
    versions = {}
    for release in releases(repo):
        if release.get("draft"):
            continue
        match = TAG.match(release["tag_name"])
        if not match:
            print(f"warning: ignoring release {release['tag_name']}, "
                  "expected <name>-<X.Y.Z>", file=sys.stderr)
            continue

        name, version = match["name"], match["version"]
        if name not in config["boxes"]:
            print(f"warning: ignoring release {release['tag_name']}, "
                  f"'{name}' is not listed in catalog.json", file=sys.stderr)
            continue

        assets = {asset["name"]: asset for asset in release["assets"]}
        box = assets.get(f"{name}-{version}{ASSET}")
        if box is None:
            print(f"warning: release {release['tag_name']} carries no "
                  f"{name}-{version}{ASSET} asset", file=sys.stderr)
            continue

        provider = {
            "name": "libvirt",
            "architecture": ARCHITECTURE,
            "default_architecture": True,
            "url": box["browser_download_url"],
        }
        digest = checksum(assets, box["name"])
        if digest:
            provider["checksum_type"] = "sha256"
            provider["checksum"] = digest

        versions.setdefault(name, []).append(
            {"version": version, "providers": [provider]}
        )

    for entries in versions.values():
        entries.sort(key=lambda e: [int(p) for p in e["version"].split(".")], reverse=True)
    return versions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "vagrant-libvirt/boxes"))
    parser.add_argument("--out", default="site")
    parser.add_argument("--config", default="catalog.json")
    args = parser.parse_args()

    with open(args.config) as handle:
        config = json.load(handle)

    namespace = config["namespace"]
    base_url = config["base_url"].rstrip("/")
    versions = build(args.repo, config)

    os.makedirs(args.out, exist_ok=True)
    published = []
    for name, settings in config["boxes"].items():
        if name not in versions:
            print(f"note: {name} has no released versions yet", file=sys.stderr)
            continue
        metadata = {
            "name": f"{namespace}/{name}",
            "description": settings["description"],
            "versions": versions[name],
        }
        with open(os.path.join(args.out, f"{name}.json"), "w") as handle:
            json.dump(metadata, handle, indent=2)
            handle.write("\n")
        published.append((name, settings, versions[name][0]["version"]))
        print(f"wrote {args.out}/{name}.json ({len(versions[name])} version(s))")

    write_index(args.out, namespace, base_url, published)


def write_index(out, namespace, base_url, published):
    rows = "\n".join(
        f"""      <tr>
        <td><code>{namespace}/{name}</code></td>
        <td>{latest}</td>
        <td><a href="{base_url}/{name}.json">{name}.json</a></td>
        <td>{settings["description"]}</td>
      </tr>"""
        for name, settings, latest in published
    ) or '      <tr><td colspan="4">No boxes published yet.</td></tr>'

    with open(os.path.join(out, "index.html"), "w") as handle:
        handle.write(f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>vagrant-libvirt boxes</title>
<style>
  body {{ font-family: system-ui, sans-serif; max-width: 60rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }}
  table {{ border-collapse: collapse; width: 100%; margin: 1.5rem 0; }}
  th, td {{ border-bottom: 1px solid #ddd; padding: .5rem; text-align: left; vertical-align: top; }}
  pre {{ background: #f6f8fa; padding: 1rem; overflow-x: auto; }}
</style>
</head>
<body>
<h1>vagrant-libvirt boxes</h1>
<p>Libvirt boxes used by the <a href="https://github.com/vagrant-libvirt/vagrant-libvirt">vagrant-libvirt</a>
acceptance tests, hosted here after the HCP Vagrant registry shut down. The box files are GitHub release
assets of <a href="https://github.com/{namespace}/boxes">{namespace}/boxes</a>; the JSON files below are
the Vagrant metadata catalogs.</p>
<table>
  <thead><tr><th>Box</th><th>Latest</th><th>Catalog</th><th>Description</th></tr></thead>
  <tbody>
{rows}
  </tbody>
</table>
<h2>Usage</h2>
<pre>Vagrant.configure("2") do |config|
  config.vm.box     = "{namespace}/tinycore"
  config.vm.box_url = "{base_url}/tinycore.json"
end</pre>
<pre>vagrant box add --name {namespace}/tinycore {base_url}/tinycore.json</pre>
</body>
</html>
""")
    print(f"wrote {out}/index.html")


if __name__ == "__main__":
    main()
