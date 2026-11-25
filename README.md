# vagrant-libvirt boxes

Libvirt boxes for the [vagrant-libvirt](https://github.com/vagrant-libvirt/vagrant-libvirt)
acceptance tests, hosted here because the HCP Vagrant registry (Vagrant Cloud)
stopped accepting boxes on 2026-10-01 and shuts down on 2026-12-31.

Box files are published as **GitHub release assets** of this repository. The
Vagrant metadata catalogs that point at them are generated from those releases
and served from **GitHub Pages**:

| Box | Catalog | Replaces |
| --- | --- | --- |
| `vagrant-libvirt/tinycore` | <https://vagrant-libvirt.github.io/boxes/tinycore.json> | `infernix/tinycore` |
| `vagrant-libvirt/tinycore-two-disks` | <https://vagrant-libvirt.github.io/boxes/tinycore-two-disks.json> | `infernix/tinycore-two-disks` |
| `vagrant-libvirt/debian10` | <https://vagrant-libvirt.github.io/boxes/debian10.json> | `generic/debian10` |

## Using a box

```ruby
Vagrant.configure("2") do |config|
  config.vm.box     = "vagrant-libvirt/tinycore"
  config.vm.box_url = "https://vagrant-libvirt.github.io/boxes/tinycore.json"
end
```

or, outside a Vagrantfile:

```shell
vagrant box add --name vagrant-libvirt/tinycore \
  https://vagrant-libvirt.github.io/boxes/tinycore.json
```

The name in `config.vm.box` has to match the `name` in the catalog, otherwise
Vagrant rejects the download. Because the catalog carries versions and
checksums, `config.vm.box_version` and `vagrant box update` keep working.

## Publishing a box

1. **Archive the upstream box** — only possible until the registry shuts down:

   ```shell
   scripts/archive-box.sh infernix/tinycore
   scripts/archive-box.sh generic/debian10
   ```

   This downloads the newest active libvirt version into `archive/` next to its
   `.sha256` and a `.meta.json` recording where it came from.

2. **Build derived boxes**, if any:

   ```shell
   scripts/build-two-disks-box.sh archive/tinycore-1.1.libvirt.box
   ```

3. **Add the box to `catalog.json`** if it is not listed yet — the name there is
   the name boxes are consumed under, and `publish-box.sh` refuses unknown names.

4. **Publish it** as a release. Versions must be `X.Y.Z`, since Vagrant only
   accepts semantic versions in a catalog. Keep the upstream version where it
   already has that shape — `infernix/tinycore` is at `0.0.2` and
   `generic/debian10` at `4.3.12`, so republishing under the same numbers leaves
   the `config.vm.box_version` pin in the two-disks test valid:

   ```shell
   scripts/publish-box.sh tinycore 0.0.2 archive/tinycore-0.0.2.libvirt.box
   scripts/publish-box.sh debian10 4.3.12 archive/debian10-4.3.12.libvirt.box
   ```

`publish-box.sh` then dispatches the `Publish Catalog` workflow on `main`,
which regenerates every `site/*.json` from the releases of this repository and
deploys them to GitHub Pages.


```shell
gh workflow run publish-catalog.yml --ref main --repo vagrant-libvirt/boxes
```

Release assets are free and CDN-served for public repositories, with a 2 GiB
limit per asset. Box files are never committed to git and never go through Git
LFS, whose bandwidth quota would be exhausted by CI runs.

## Repository layout

```
catalog.json                      box names, descriptions and upstream provenance
scripts/archive-box.sh            download a box from the HCP Vagrant registry
scripts/build-two-disks-box.sh    derive the two-disks box from a tinycore box
scripts/publish-box.sh            publish a box file as a release asset
scripts/build-catalog.py          generate the Pages catalog from the releases
```

Boxes built from scratch rather than archived (a replacement for the
discontinued `generic/*` boxes, for instance) get a build recipe of their own
here; `scripts/build-two-disks-box.sh` is the first of them.

## Consuming side

vagrant-libvirt's acceptance tests have to be repointed once the boxes are
published, in:

- `spec/acceptance/support-skeletons/*/Vagrantfile` — `config.vm.box` plus a new
  `config.vm.box_url`
- `spec/acceptance/support-skeletons/two_disks/Vagrantfile` — the
  `config.vm.box_version` pin stays `0.0.2` as long as the boxes are republished
  under their upstream version numbers
- `tools/create_box_with_two_disks.sh` — obsolete once
  `vagrant-libvirt/tinycore-two-disks` is published, as the box no longer has to
  be assembled on the fly

## Provenance and licensing

- `tinycore` and `tinycore-two-disks` originate from `infernix/tinycore`, built
  on [Tiny Core Linux](http://tinycorelinux.net/) (GPL/BSD components).
- `debian10` originates from `generic/debian10` of the
  [roboxes](https://roboxes.org/) project, built on
  [Debian](https://www.debian.org/) 10, which is end of life. It is kept only to
  keep the existing tests running and should be replaced by a current Debian
  built here.
