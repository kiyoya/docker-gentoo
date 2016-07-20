#!/bin/bash

set -eu

BUILD_IMAGE="${BUILD_IMAGE:-tianon/true}"
BUILD_NAME="${BUILD_NAME:-portage-build}"
BUILD_ROOT="${BUILD_ROOT:-/build}"
GENTOO_IMAGE="${GENTOO_IMAGE:-gentoo/stage3-amd64}"
PORTAGE_IMAGE="${PORTAGE_IMAGE:-gentoo/portage}"
PORTAGE_NAME="${PORTAGE_NAME:-portage}"

# Fundamental packages
BASE_PACKAGES="
  app-shells/bash
  sys-apps/baselayout
  sys-apps/busybox
  sys-libs/glibc"

case "${MSYSTEM:-}" in
  MINGW*)
    DOCKER="$(command -v docker)"
    function docker() {
      MSYS2_ARG_CONV_EXCL='*' "${DOCKER}" "$@"
    }
    ;;
esac

function bootstrap_build() {
  NAME="${1}"
  IMAGE="${2}"
  docker exec "${NAME}" \
    tar -cf - -C ${BUILD_ROOT} . \
    | docker import "${@:3}" - "${IMAGE}"
}

function bootstrap_create() {
  NAME="${1}"
  # --privileged is required to build glibc.
  docker run -d -it --name "${NAME}" \
    --privileged \
    --volumes-from "${PORTAGE_NAME}" \
    "${GENTOO_IMAGE}" /bin/bash
  bootstrap_shell "${NAME}" \
    -c 'mkdir -p /etc/portage/package.{keywords,mask,use}'
  bootstrap_emerge "${NAME}" ${BASE_PACKAGES}
}

function bootstrap_clean() {
  NAME="${1}"
  docker stop "${NAME}"
  docker rm "${NAME}"
}

function bootstrap_emerge() {
  NAME="${1}"
  docker exec -it "${NAME}" \
    emerge --buildpkg --usepkg --onlydeps --quiet "${@:2}"
  docker exec -it "${NAME}" \
    emerge --buildpkg --usepkg --root="${BUILD_ROOT}" --root-deps=rdeps \
    --quiet "${@:2}"
}

function bootstrap_shell() {
  NAME="${1}"
  docker exec -it "${NAME}" /bin/bash "${@:2}"
}
