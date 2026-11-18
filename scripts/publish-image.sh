#!/bin/bash
set -euo pipefail

repository="${DOCKER_USER:?}/textbook-library"
tag="${BUILD_NUMBER:?}"
metadata=$(mktemp)
existing_docker_config=${DOCKER_CONFIG:-$HOME/.docker}
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -f "$metadata"; rm -rf "$DOCKER_CONFIG"' EXIT
if [[ -d "$existing_docker_config/cli-plugins" ]]; then
    ln -s "$existing_docker_config/cli-plugins" "$DOCKER_CONFIG/cli-plugins"
fi

printf '%s\n' "${DOCKER_PASS:?}" | docker login --username "$DOCKER_USER" --password-stdin
docker buildx build --platform linux/arm64 --target packaged \
    --tag "$repository:$tag" --metadata-file "$metadata" --push .
digest=$(jq -er '."containerimage.digest" | select(test("^sha256:[a-f0-9]{64}$"))' "$metadata")
printf '%s@%s\n' "$repository" "$digest" > target/published-image.txt
