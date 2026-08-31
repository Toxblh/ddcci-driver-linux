#!/bin/sh
# Reproduce the ALS (altlinux.space) hasherc build locally: same image,
# same gear-hshc invocation as actions/build-rpm-action.
# Usage: ci/als-local.sh   (results land in ./out-als/)
set -e
cd "$(dirname "$0")/.."
mkdir -p out-als
podman run --rm -i -v "$PWD":/work:Z -w /work altlinux.space/actions/runner/hasherc:sisyphus sh -eux - <<'EOF'
set -euo pipefail
git config --global user.email "hasherc-ci@altlinux.org"
git config --global user.name "Builder"
git config --global --add safe.directory "$PWD"
git add .
echo "%packager Builder <hasherc-ci@altlinux.org>" > ~/.rpmmacros
gear-hshc --commit --no-sisyphus-check=gpg,packager --branch=p11 --platform=linux/amd64
find -L ~/.cache/hasherc/dkms-ddcci/out/RPMS -type f -name '*debuginfo*.rpm' -delete
cp -v ~/.cache/hasherc/dkms-ddcci/out/RPMS/*/*.rpm /work/out-als/
EOF
echo; ls -la out-als/
