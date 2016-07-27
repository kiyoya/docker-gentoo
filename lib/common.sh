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

DOCKER_OPTS="-i"

LOG_INFO="\033[1;31m"

case "${MSYSTEM:-}" in
  MINGW*)
    DOCKER="$(command -v docker)"
    function docker() {
      MSYS2_ARG_CONV_EXCL='*' "${DOCKER}" "$@"
    }
    ;;
  *)
    DOCKER_OPTS="${DOCKER_OPTS} -t"
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
  docker run ${DOCKER_OPTS} -d --name "${NAME}" \
    --privileged \
    --volumes-from "${BUILD_NAME}" \
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
  docker exec ${DOCKER_OPTS} "${NAME}" \
    emerge --buildpkg --usepkg --onlydeps --quiet "${@:2}"
  docker exec ${DOCKER_OPTS} "${NAME}" \
    emerge --buildpkg --usepkg --root="${BUILD_ROOT}" --root-deps=rdeps \
    --quiet "${@:2}"
}

function bootstrap_shell() {
  NAME="${1}"
  docker exec ${DOCKER_OPTS} "${NAME}" /bin/bash "${@:2}"
}

function die() {
  printf "${LOG_INFO}$@\033[0m\n" >&2
  exit 1
}

function log() {
  printf "${LOG_INFO}$@\033[0m\n"
}
