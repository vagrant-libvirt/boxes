#!/bin/bash
#
# Build the tinycore-two-disks box from a plain tinycore box by adding a second,
# empty qcow2 disk and declaring both disks in the box metadata.
#
# vagrant-libvirt's tools/create_box_with_two_disks.sh assembles this box inside
# ~/.vagrant.d on every acceptance test run. Building it once here means the test
# can simply consume vagrant-libvirt/tinycore-two-disks like any other box.
#
# Usage: scripts/build-two-disks-box.sh <tinycore box file> [outdir] [size]
#
#   scripts/build-two-disks-box.sh archive/tinycore-1.1.libvirt.box build 10G

set -eu -o pipefail

SOURCE=${1:?usage: build-two-disks-box.sh <tinycore box file> [outdir] [size]}
OUTDIR=${2:-./build}
SIZE=${3:-10G}

NAME=tinycore-two-disks
OUT="${OUTDIR}/${NAME}.libvirt.box"

[ -f "${SOURCE}" ] || { echo "error: no such file: ${SOURCE}" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

echo "==> unpacking ${SOURCE}"
tar -xf "${SOURCE}" -C "${WORK}"

[ -f "${WORK}/box.img" ] || { echo "error: ${SOURCE} contains no box.img" >&2; exit 1; }

echo "==> creating second disk (${SIZE})"
qemu-img create -f qcow2 "${WORK}/disk2.qcow2" "${SIZE}" >/dev/null

echo "==> writing metadata.json"
cat > "${WORK}/metadata.json" <<'JSON'
{
  "provider": "libvirt",
  "disks": [
    {
      "path": "box.img"
    },
    {
      "path": "disk2.qcow2"
    }
  ]
}
JSON

mkdir -p "${OUTDIR}"
echo "==> packing ${OUT}"
tar -czf "${OUT}" -C "${WORK}" .

echo
echo "built ${OUT}"
echo "publish it with:"
echo "  scripts/publish-box.sh ${NAME} <version> ${OUT}"
