#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")"

repobase=${REPOBASE:-ghcr.io/geniusdynamics}
tag=${IMAGETAG:-latest}
# The frontend, Redis, Pyxform and PostgreSQL pins follow the Central release.
central_version=v2026.3.2
frontend_version=v2026.3.1
postgres_image=docker.io/library/postgres:14.25
redis_image=docker.io/library/redis:8.10.1
pyxform_image=ghcr.io/getodk/pyxform-http:v4.5.0
images=("$repobase/odk-service" "$repobase/odk-nginx" "$repobase/odk-enketo" "$repobase/odk")

upstream=$(mktemp -d)
ui_builder=
module=
cleanup() {
    [[ -z $ui_builder ]] || buildah rm "$ui_builder"
    [[ -z $module ]] || buildah rm "$module"
    rm -rf "$upstream"
}
trap cleanup EXIT
git clone --depth 1 --branch "$central_version" --recurse-submodules --shallow-submodules https://github.com/getodk/central.git "$upstream"

python3 containers/adapt-central.py "$upstream" "$frontend_version"
cp containers/start-nginx.sh "$upstream/files/nginx/start-ns8.sh"
for component in service nginx enketo; do
    buildah bud --label org.opencontainers.image.source=https://github.com/geniusdynamics/ns8-odk \
        --build-arg "FRONTEND_BUILD_MODE=fetch" --build-arg "FRONTEND_VERSION=$frontend_version" \
        -f "$upstream/$component.dockerfile" -t "$repobase/odk-$component" "$upstream"
done

ui_builder=$(buildah from -v "$PWD:/usr/src:Z" docker.io/library/node:26.13.0-slim)
buildah run --workingdir /usr/src/ui --env NODE_OPTIONS=--openssl-legacy-provider "$ui_builder" \
    sh -ec 'npm install -g corepack@0.36.0 && corepack enable && yarn install --immutable && yarn build'

module=$(buildah from scratch)
buildah add "$module" imageroot /imageroot
buildah add "$module" ui/dist /ui
buildah config --entrypoint=/ \
    --label org.opencontainers.image.source=https://github.com/geniusdynamics/ns8-odk \
    --label "org.opencontainers.image.version=$central_version" \
    --label "org.nethserver.authorizations=traefik@node:routeadm cluster:accountconsumer idp@any:clientadm keycloak@any:clientadm lemonldapng@any:clientadm" \
    --label org.nethserver.tcp-ports-demand=1 \
    --label org.nethserver.rootfull=0 \
    --label org.nethserver.min-core=3.20.1 \
    --label "org.nethserver.images=${images[0]}:$tag ${images[1]}:$tag ${images[2]}:$tag $postgres_image $redis_image $pyxform_image" \
    "$module"
buildah commit "$module" "${images[3]}"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    printf 'images=%s\n' "${images[*]}" >> "$GITHUB_OUTPUT"
else
    for image in "${images[@]}"; do
        printf 'buildah push %s docker://%s:%s\n' "$image" "$image" "$tag"
    done
fi
