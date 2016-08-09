#!/bin/bash

set -eu

BUILD_IMAGE="${BUILD_IMAGE:-tianon/true}"
BUILD_NAME="${BUILD_NAME:-portage-build}"
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
  docker exec ${DOCKER_OPTS} "${NAME}" sh -c 'umount -l /build/dev{/shm,/pts,}'
  docker exec ${DOCKER_OPTS} "${NAME}" sh -c 'umount /build{/sys,/proc}'
  docker exec "${NAME}" \
    tar -cf - -C /build . \
    | docker import "${@:3}" - "${IMAGE}"
  docker stop "${NAME}"
  docker rm "${NAME}"
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
  # TODO(kiyoya): Copied files may conflict if sys-devel/gcc is installed into
  #               /build.
  bootstrap_shell "${NAME}" \
    -c 'cp -P `gcc-config -L | cut -d : -f 1`/lib*.so* /build/usr/lib64'
  bootstrap_shell "${NAME}" \
    -c 'cp -P `gcc-config -L | cut -d : -f 2`/lib*.so* /build/usr/lib32'
  docker exec ${DOCKER_OPTS} "${NAME}" sh -c 'mkdir -p /build{/dev,/proc,/sys}'
  docker exec ${DOCKER_OPTS} "${NAME}" mount -t proc proc /build/proc
  docker exec ${DOCKER_OPTS} "${NAME}" mount --rbind /sys /build/sys
  docker exec ${DOCKER_OPTS} "${NAME}" mount --rbind /dev /build/dev
}

function bootstrap_emerge() {
  NAME="${1}"
  docker exec ${DOCKER_OPTS} "${NAME}" \
    emerge --buildpkg --usepkg --onlydeps --quiet "${@:2}"
  docker exec ${DOCKER_OPTS} "${NAME}" \
    emerge --buildpkg --usepkg --root=/build --root-deps=rdeps \
    --quiet "${@:2}"
}

function bootstrap_shell() {
  NAME="${1}"
  docker exec ${DOCKER_OPTS} "${NAME}" /bin/bash "${@:2}"
}

function bootstrap_shell_chroot() {
  NAME="${1}"
  docker exec ${DOCKER_OPTS} "${NAME}" chroot /build /bin/bash "${@:2}"
}

function die() {
  printf "${LOG_INFO}$@\033[0m\n" >&2
  exit 1
}

function log() {
  printf "${LOG_INFO}$@\033[0m\n"
}
