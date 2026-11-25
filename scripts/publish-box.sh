#!/bin/bash
#
# Publish a box file as a GitHub release asset of this repository. The release
# tag is the single source of truth for the catalog: scripts/build-catalog.py
# turns the releases into the Vagrant metadata JSON served from GitHub Pages.
#
# Usage: scripts/publish-box.sh <name> <version> <box file> [notes file]
#
#   scripts/publish-box.sh tinycore 1.0.0 archive/tinycore-1.1.libvirt.box
#
# <name> is the box name without the namespace, so the box above is consumed as
# vagrant-libvirt/tinycore. <version> is the version under which it is published
# here, which need not match the upstream version it was archived from.

set -eu -o pipefail

NAME=${1:?usage: publish-box.sh <name> <version> <box file> [notes file]}
VERSION=${2:?missing version}
FILE=${3:?missing box file}
NOTES=${4:-}

REPO=${BOXES_REPO:-vagrant-libvirt/boxes}
TAG="${NAME}-${VERSION}"
ASSET="${NAME}-${VERSION}.libvirt.box"

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must be X.Y.Z (Vagrant only accepts semantic versions)" >&2
    exit 1
fi

if ! jq -e --arg n "${NAME}" '.boxes[$n]' catalog.json >/dev/null; then
    echo "error: '${NAME}' is not listed in catalog.json, add it there first" >&2
    exit 1
fi

[ -f "${FILE}" ] || { echo "error: no such file: ${FILE}" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

cp "${FILE}" "${WORK}/${ASSET}"
( cd "${WORK}" && sha256sum "${ASSET}" > "${ASSET}.sha256" )

echo "==> ${ASSET}  $(cut -d' ' -f1 < "${WORK}/${ASSET}.sha256")"

if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
    echo "==> updating existing release ${TAG}"
    gh release upload "${TAG}" --repo "${REPO}" --clobber \
        "${WORK}/${ASSET}" "${WORK}/${ASSET}.sha256"
else
    if [ -n "${NOTES}" ]; then
        NOTES_ARGS=(--notes-file "${NOTES}")
    else
        NOTES_ARGS=(--notes "Vagrant libvirt box \`vagrant-libvirt/${NAME}\` version ${VERSION}.")
    fi

    echo "==> creating release ${TAG}"
    gh release create "${TAG}" --repo "${REPO}" \
        --title "${NAME} ${VERSION}" \
        "${NOTES_ARGS[@]}" \
        "${WORK}/${ASSET}" "${WORK}/${ASSET}.sha256"
fi

echo "==> refreshing the catalog"
gh workflow run publish-catalog.yml --ref main --repo "${REPO}"

echo
echo "published. the catalog workflow is rebuilding"
echo "  https://vagrant-libvirt.github.io/boxes/${NAME}.json"
echo "follow it with: gh run watch --repo ${REPO}"
