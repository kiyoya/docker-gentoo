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
    function volumepath() {
      cygpath -aw "$@"
    }
    ;;
  *)
    function volumepath() {
      realpath "$@"
    }
    ;;
esac

function bootstrap_build() {
  local NAME="${1}"
  local IMAGE="${2}"
  bootstrap_shell "${NAME}" <<EOM
    set -eu
    umount -l /build/dev{/shm,/pts,}
    umount -l /build/sys
    umount /build/proc
EOM
  # Copies runtime libraries from sys-devel/gcc if not installed.
  set +e
  docker exec -i "${NAME}" 'test' -d /build/etc/env.d/gcc
  local HAS_GCC=$?
  set -e
  if [ ${HAS_GCC} -ne 0 ]; then
    local GCC_LIBS=$(docker exec -i "${NAME}" gcc-config -L)
    local GCC_LIBS64=$(echo "${GCC_LIBS}" | cut -d : -f 1)
    local GCC_LIBS32=$(echo "${GCC_LIBS}" | cut -d : -f 2)
    bootstrap_shell "${NAME}" <<EOM
      set -eu
      mkdir -p /build${GCC_LIBS32}
      mkdir -p /build${GCC_LIBS64}
      cp -P ${GCC_LIBS32}/lib*.so* /build${GCC_LIBS32}
      cp -P ${GCC_LIBS64}/lib*.so* /build${GCC_LIBS64}
      cp /etc/ld.so.conf.d/??gcc* /build/etc/ld.so.conf.d/
EOM
    bootstrap_shell_chroot "${NAME}" -c ldconfig
  fi
  # TODO(kiyoya): Piping a tar archive does not work on msys.
  # docker exec "${NAME}" tar -cf - -C /build . \
  #   | docker import "${@:3}" - "${IMAGE}"
  docker exec "${NAME}" tar -cf - -C /build . > /tmp/"${NAME}".tar
  docker import "${@:3}" $(volumepath /tmp/"${NAME}".tar) "${IMAGE}"
  rm -f /tmp/"${NAME}".tar

  docker stop "${NAME}"
  docker rm "${NAME}"
}

function bootstrap_create() {
  local NAME="${1}"
  # --privileged is required to build glibc.
  docker run -it -d --name "${NAME}" \
    --privileged \
    --volumes-from "${BUILD_NAME}" \
    --volumes-from "${PORTAGE_NAME}" \
    "${@:2}" \
    "${GENTOO_IMAGE}" /bin/bash
  docker exec -i "${NAME}" \
    mkdir -p '/etc/portage/package.{keywords,mask,use}'
  bootstrap_emerge "${NAME}" ${BASE_PACKAGES}
  bootstrap_shell "${NAME}" <<EOM
    set -eu
    cp -L /etc/resolv.conf /build/etc/
    mkdir -p /build{/dev,/proc,/sys}
    mount -t proc proc /build/proc
    mount --rbind /sys /build/sys
    mount --rbind /dev /build/dev
EOM
}

# TODO(kiyoya): Add a command to check affected packages by GLSA.
#               glsa-check -t all && glsa-check -d affected
function bootstrap_emerge() {
  local NAME="${1}"
  docker exec -i "${NAME}" \
    emerge --buildpkg --usepkg --onlydeps --quiet "${@:2}"
  docker exec -i "${NAME}" \
    emerge --buildpkg --usepkg --root=/build --root-deps=rdeps \
    --quiet "${@:2}"
}

function bootstrap_shell() {
  local NAME="${1}"
  if [ -t 0 ]; then
    docker exec -i "${NAME}" /bin/bash "${@:2}"
  else
    docker exec -i "${NAME}" /bin/bash "${@:2}" -c "$(cat -)"
  fi
}

function bootstrap_shell_chroot() {
  local NAME="${1}"
  if [ -t 0 ]; then
    docker exec -i "${NAME}" chroot /build /bin/bash "${@:2}"
  else
    docker exec -i "${NAME}" chroot /build /bin/bash "${@:2}" -c "$(cat -)"
  fi
}

function docker_container_exists() {
  local NAME="${1}"
  docker ps -a --filter name=^/"${NAME}"$ | tail -n +2 | grep -q "${NAME}"
}

function docker_image_exists() {
  local REPO="${1}"
  local TAG="${2}"
  docker images "${REPO}" | awk '{print $2}' | tail -n +2 | grep -q ^"${TAG}"$
}

function docker_promote() {
  local REPO="${1}"
  local TAG="${2}"
  log "Promoting ${REPO}:${TAG} ..."
  docker tag "${REPO}":"${TAG}" "${REPO}":latest
  docker push "${REPO}":"${TAG}"
}

function die() {
  printf "${LOG_INFO}$@\033[0m\n" >&2
  exit 1
}

function log() {
  printf "${LOG_INFO}$@\033[0m\n"
}
