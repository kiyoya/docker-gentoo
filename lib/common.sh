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
  bootstrap_shell "${NAME}" <<EOM
    umount -l /build/dev{/shm,/pts,}
    umount -l /build/sys
    umount /build/proc
EOM
  # Copies runtime libraries from sys-devel/gcc if not installed.
  set +e
  docker exec ${DOCKER_OPTS} "${NAME}" 'test' -d /build/etc/env.d/gcc
  HAS_GCC=$?
  set -e
  if [ ${HAS_GCC} -ne 0 ]; then
    GCC_LIBS=$(docker exec ${DOCKER_OPTS} "${NAME}" gcc-config -L)
    GCC_LIBS64=$(echo "${GCC_LIBS}" | cut -d : -f 1)
    GCC_LIBS32=$(echo "${GCC_LIBS}" | cut -d : -f 2)
    bootstrap_shell "${NAME}" <<EOM
      cp -r /etc/env.d/gcc /build/etc/env.d
      mkdir -p /build${GCC_LIBS32}
      mkdir -p /build${GCC_LIBS64}
      cp -P ${GCC_LIBS32}/lib*.so* /build${GCC_LIBS32}
      cp -P ${GCC_LIBS64}/lib*.so* /build${GCC_LIBS64}
      env-update
EOM
  fi
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
  docker exec ${DOCKER_OPTS} "${NAME}" \
    mkdir -p '/etc/portage/package.{keywords,mask,use}'
  bootstrap_emerge "${NAME}" ${BASE_PACKAGES}
  bootstrap_shell "${NAME}" <<EOM
    cp -L /etc/resolv.conf /build/etc/
    mkdir -p /build{/dev,/proc,/sys}
    mount -t proc proc /build/proc
    mount --rbind /sys /build/sys
    mount --rbind /dev /build/dev
EOM
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
