#!/bin/bash
#
# Download a box from the HCP Vagrant registry (app.vagrantup.com) and store it
# locally together with its checksum and a record of where it came from.
#
# The registry stopped accepting new boxes on 2026-10-01 and shuts down on
# 2026-12-31, so anything still needed has to be fetched before that date.
#
# Usage: scripts/archive-box.sh <namespace/name> [version] [outdir]
#
#   scripts/archive-box.sh infernix/tinycore
#   scripts/archive-box.sh generic/debian10 4.3.12 ./archive
#
# Writes <outdir>/<name>-<version>.libvirt.box, .box.sha256 and .meta.json.

set -eu -o pipefail

SOURCE=${1:?usage: archive-box.sh <namespace/name> [version] [outdir]}
VERSION=${2:-}
OUTDIR=${3:-./archive}

API=https://app.vagrantup.com/api/v2/box
PROVIDER=libvirt

NAMESPACE=${SOURCE%%/*}
NAME=${SOURCE##*/}

if [ "${NAMESPACE}" = "${SOURCE}" ] || [ -z "${NAME}" ]; then
    echo "error: expected <namespace/name>, got '${SOURCE}'" >&2
    exit 1
fi

mkdir -p "${OUTDIR}"

echo "==> fetching registry metadata for ${SOURCE}"
META=$(curl -fsSL "${API}/${NAMESPACE}/${NAME}")

if [ -z "${VERSION}" ]; then
    VERSION=$(jq -r --arg p "${PROVIDER}" '
        [ .versions[]
          | select(.status == "active")
          | select([.providers[].name] | index($p))
          | .version ] | first // empty' <<<"${META}")
    if [ -z "${VERSION}" ]; then
        echo "error: no active ${PROVIDER} version found for ${SOURCE}" >&2
        exit 1
    fi
    echo "==> latest ${PROVIDER} version is ${VERSION}"
fi

URL=$(jq -r --arg v "${VERSION}" --arg p "${PROVIDER}" '
    .versions[] | select(.version == $v)
    | .providers[] | select(.name == $p)
    | (.download_url // .url) // empty' <<<"${META}" | head -n 1)

if [ -z "${URL}" ]; then
    echo "error: ${SOURCE} ${VERSION} has no ${PROVIDER} provider" >&2
    exit 1
fi

BOX="${OUTDIR}/${NAME}-${VERSION}.libvirt.box"

echo "==> downloading ${URL}"
curl -fL --progress-bar -o "${BOX}.part" "${URL}"
mv "${BOX}.part" "${BOX}"

echo "==> checksumming"
( cd "${OUTDIR}" && sha256sum "$(basename "${BOX}")" > "$(basename "${BOX}").sha256" )
CHECKSUM=$(cut -d' ' -f1 < "${BOX}.sha256")

jq -n \
    --arg source "${SOURCE}" \
    --arg version "${VERSION}" \
    --arg provider "${PROVIDER}" \
    --arg url "${URL}" \
    --arg checksum "${CHECKSUM}" \
    --arg archived_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '$ARGS.named' > "${OUTDIR}/${NAME}-${VERSION}.meta.json"

echo
echo "archived ${SOURCE} ${VERSION}"
echo "  box      ${BOX}"
echo "  sha256   ${CHECKSUM}"
echo
echo "publish it with:"
echo "  scripts/publish-box.sh ${NAME} ${VERSION} ${BOX}"
