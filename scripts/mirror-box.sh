#!/bin/bash
#
# Mirror a box from a Vagrant metadata catalog — the JSON that config.vm.box_url
# points at — and store it locally together with its checksum and a record of
# where it came from.
#
# scripts/archive-box.sh talks to the HCP Vagrant registry, which shuts down on
# 2026-12-31. This script instead reads the catalogs upstream projects publish
# themselves, which is how boxes that are still maintained get here:
#
#   scripts/mirror-box.sh almalinux10 https://vagrant.almalinux.org/almalinux/10
#   scripts/mirror-box.sh almalinux10 https://vagrant.almalinux.org/almalinux/10 10.3.20261116
#
# <name> is the name the box is published under here, without the namespace, so
# the box above is consumed as vagrant-libvirt/almalinux10. Without a version
# the newest one offering the wanted provider and architecture is taken.
#
# Writes <outdir>/<name>-<version>.libvirt.box, .box.sha256 and .meta.json.

set -eu -o pipefail

NAME=${1:?usage: mirror-box.sh <name> <catalog url> [version] [outdir]}
CATALOG=${2:?missing catalog url}
VERSION=${3:-}
OUTDIR=${4:-./archive}

PROVIDER=${PROVIDER:-libvirt}
ARCHITECTURE=${ARCHITECTURE:-amd64}

mkdir -p "${OUTDIR}"

echo "==> fetching catalog ${CATALOG}"
META=$(curl -fsSL "${CATALOG}")

# the provider entry wanted, matching catalogs that predate the architecture key
SELECT='.providers[] | select(.name == $p) | select((.architecture // $a) == $a)'

if [ -z "${VERSION}" ]; then
    # catalogs are not ordered, so compare the versions numerically rather than
    # trusting the order they are listed in
    VERSION=$(jq -r --arg p "${PROVIDER}" --arg a "${ARCHITECTURE}" '
        [ .versions[]
          | select((.status // "active") == "active")
          | select([ '"${SELECT}"' ] | length > 0)
          | .version ]
        | sort_by(split(".") | map(tonumber? // 0)) | last // empty' <<<"${META}")
    if [ -z "${VERSION}" ]; then
        echo "error: no active ${PROVIDER}/${ARCHITECTURE} version in ${CATALOG}" >&2
        exit 1
    fi
    echo "==> newest ${PROVIDER} version is ${VERSION}"
fi

PROVIDER_JSON=$(jq -c --arg v "${VERSION}" --arg p "${PROVIDER}" --arg a "${ARCHITECTURE}" '
    .versions[] | select(.version == $v) | '"${SELECT}" <<<"${META}" | head -n 1)

if [ -z "${PROVIDER_JSON}" ]; then
    echo "error: ${CATALOG} ${VERSION} has no ${PROVIDER}/${ARCHITECTURE} provider" >&2
    exit 1
fi

URL=$(jq -r '(.download_url // .url) // empty' <<<"${PROVIDER_JSON}")
EXPECTED=$(jq -r 'select((.checksum_type // "") | ascii_downcase == "sha256") | .checksum // empty' <<<"${PROVIDER_JSON}")

if [ -z "${URL}" ]; then
    echo "error: ${CATALOG} ${VERSION} lists no download url" >&2
    exit 1
fi

BOX="${OUTDIR}/${NAME}-${VERSION}.libvirt.box"

echo "==> downloading ${URL}"
curl -fL --progress-bar -o "${BOX}.part" "${URL}"
mv "${BOX}.part" "${BOX}"

echo "==> checksumming"
( cd "${OUTDIR}" && sha256sum "$(basename "${BOX}")" > "$(basename "${BOX}").sha256" )
CHECKSUM=$(cut -d' ' -f1 < "${BOX}.sha256")

if [ -n "${EXPECTED}" ] && [ "${EXPECTED}" != "${CHECKSUM}" ]; then
    echo "error: checksum mismatch, the catalog promised ${EXPECTED} but got ${CHECKSUM}" >&2
    exit 1
fi
[ -n "${EXPECTED}" ] && echo "==> sha256 matches the one published in the catalog"

jq -n \
    --arg source "${CATALOG}" \
    --arg version "${VERSION}" \
    --arg provider "${PROVIDER}" \
    --arg architecture "${ARCHITECTURE}" \
    --arg url "${URL}" \
    --arg checksum "${CHECKSUM}" \
    --arg mirrored_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '$ARGS.named' > "${OUTDIR}/${NAME}-${VERSION}.meta.json"

echo
echo "mirrored ${CATALOG} ${VERSION}"
echo "  box      ${BOX}"
echo "  sha256   ${CHECKSUM}"
echo
echo "publish it with:"
echo "  scripts/publish-box.sh ${NAME} ${VERSION} ${BOX}"
