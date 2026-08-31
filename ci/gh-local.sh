#!/bin/sh
# Reproduce the GitHub Actions build locally: same image, same steps.
# Usage: ci/gh-local.sh   (results land in ./out/)
set -e
cd "$(dirname "$0")/.."
mkdir -p out
podman run --rm -i -v "$PWD":/work:Z -w /work registry.altlinux.org/alt/alt:p11 sh -eux - <<'EOF'
set -euo pipefail
apt-get update -qq
apt-get install -y -qq rpm-build git

useradd -m builder
ver="$(sed -n 's/^Version:[[:space:]]*//p' dkms-ddcci.spec | tr -d ' ')"
git config --global --add safe.directory "$PWD"
git archive --format=tar --prefix="dkms-ddcci-${ver}/" HEAD > "dkms-ddcci-${ver}.tar"
install -d /tmp/rpmbuild/SOURCES /tmp/rpmbuild/SPECS /work/out
cp "dkms-ddcci-${ver}.tar" /tmp/rpmbuild/SOURCES/
cp dkms-ddcci.spec /tmp/rpmbuild/SPECS/
chown -R builder: /tmp/rpmbuild
chmod 777 /work/out
runuser -u builder -- sh -eux -c '
    rpmbuild -ba --define "_topdir /tmp/rpmbuild" /tmp/rpmbuild/SPECS/dkms-ddcci.spec &&
    cp -v /tmp/rpmbuild/RPMS/noarch/*.rpm /tmp/rpmbuild/SRPMS/*.src.rpm /work/out/
'
EOF
echo; ls -la out/
