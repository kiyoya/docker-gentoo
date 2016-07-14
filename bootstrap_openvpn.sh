#!/bin/bash
# @(#) Script to build and maintain gentoo-based openvpn docker images.

set -eu

P="bash coreutils iptables openvpn"

NAME="${NAME:-openvpn}"
IMAGE="${IMAGE:-kiyoya/openvpn}"

ROOT="${ROOT:-$(dirname $0)}"
ENTRYPOINT="${ENTRYPOINT:-${ROOT}/openvpn/docker-entrypoint.sh}"

"${ROOT}"/bootstrap.sh create "${NAME}"
"${ROOT}"/bootstrap.sh shell "${NAME}" \
  -ci "emerge_prepare ${P} --quiet && emerge_build ${P} --quiet"
"${ROOT}"/bootstrap.sh cp "${NAME}" "${ENTRYPOINT}" /build/docker-entrypoint.sh
"${ROOT}"/bootstrap.sh build "${NAME}" "${IMAGE}" \
  -c '"CMD [\"/docker-entrypoint.sh\"]"' \
  -c '"VOLUME [\"/etc/openvpn\"]"' \
  -c '"EXPOSE 1194"' \
  -c '"EXPOSE 1194/udp"'
"${ROOT}"/bootstrap.sh clean "${NAME}"
