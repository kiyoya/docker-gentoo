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

LOG_INFO="\033[1;31m"

case "${MSYSTEM:-}" in
  MINGW*)
    DOCKER="$(command -v docker)"
    function docker() {
      MSYS2_ARG_CONV_EXCL='*' "${DOCKER}" "$@"
    }
    function volpath() {
      cygpath -w "${@}"
    }
    ;;
  *)
    function volpath() {
      realpath "${@}"
    }
    ;;
esac

function bootstrap_build() {
  NAME="${1}"
  IMAGE="${2}"
  docker exec -i "${NAME}" /bin/bash <<EOM
    umount -l /build/dev{/shm,/pts,}
    umount -l /build/sys
    umount /build/proc
EOM
  # Copies runtime libraries from sys-devel/gcc if not installed.
  set +e
  docker exec -i "${NAME}" 'test' -d /build/etc/env.d/gcc
  HAS_GCC=$?
  set -e
  if [ ${HAS_GCC} -ne 0 ]; then
    GCC_LIBS=$(docker exec -i "${NAME}" gcc-config -L)
    GCC_LIBS64=$(echo "${GCC_LIBS}" | cut -d : -f 1)
    GCC_LIBS32=$(echo "${GCC_LIBS}" | cut -d : -f 2)
    docker exec -i "${NAME}" /bin/bash <<EOM
      mkdir -p /build${GCC_LIBS32}
      mkdir -p /build${GCC_LIBS64}
      cp -P ${GCC_LIBS32}/lib*.so* /build${GCC_LIBS32}
      cp -P ${GCC_LIBS64}/lib*.so* /build${GCC_LIBS64}
      cp /etc/ld.so.conf.d/??gcc* /build/etc/ld.so.conf.d/
EOM
    bootstrap_shell_chroot "${NAME}" -c ldconfig
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
  docker run -it -d --name "${NAME}" \
    --privileged \
    --volumes-from "${BUILD_NAME}" \
    --volumes-from "${PORTAGE_NAME}" \
    "${GENTOO_IMAGE}" /bin/bash
  docker exec -i "${NAME}" \
    mkdir -p '/etc/portage/package.{keywords,mask,use}'
  bootstrap_emerge "${NAME}" ${BASE_PACKAGES}
  docker exec -i "${NAME}" /bin/bash <<EOM
    cp -L /etc/resolv.conf /build/etc/
    mkdir -p /build{/dev,/proc,/sys}
    mount -t proc proc /build/proc
    mount --rbind /sys /build/sys
    mount --rbind /dev /build/dev
EOM
}

function bootstrap_emerge() {
  NAME="${1}"
  docker exec -it "${NAME}" \
    emerge --buildpkg --usepkg --onlydeps --quiet "${@:2}"
  docker exec -it "${NAME}" \
    emerge --buildpkg --usepkg --root=/build --root-deps=rdeps \
    --quiet "${@:2}"
}

function bootstrap_shell() {
  NAME="${1}"
  docker exec -it "${NAME}" /bin/bash "${@:2}"
}

function bootstrap_shell_chroot() {
  NAME="${1}"
  docker exec -it "${NAME}" chroot /build /bin/bash "${@:2}"
}

function die() {
  printf "${LOG_INFO}$@\033[0m\n" >&2
  exit 1
}

function log() {
  printf "${LOG_INFO}$@\033[0m\n"
}
