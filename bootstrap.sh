#!/bin/bash
# @(#) Script to build and maintain gentoo-based docker images.

set -eu

BUILD_IMAGE="${BUILD_IMAGE:-tianon/true}"
BUILD_NAME="${BUILD_NAME:-portage-build}"
BUILD_ROOT="${BUILD_ROOT:-/build}"
GENTOO_IMAGE="${GENTOO_IMAGE:-gentoo/stage3-amd64}"
PORTAGE_IMAGE="${PORTAGE_IMAGE:-gentoo/portage}"
PORTAGE_NAME="${PORTAGE_NAME:-portage}"

# Fundamental packages
PACKAGES="
  app-shells/bash
  sys-apps/baselayout
  sys-apps/busybox
  sys-libs/glibc"

case "${MSYSTEM:-}" in
  MINGW*)
    function _absolute_path() {
      pushd "$(dirname $1)" 1> /dev/null
      local path=$(pwd)
      popd 1> /dev/null
      echo "/$(cygpath -w ${path}/$(basename $1) | sed -e 's|:\>\\|/|g')"
    }
    ;;
  *)
    function _absolute_path() {
    pushd "$(dirname $1)" 1> /dev/null
      local path=$(pwd)
      popd 1> /dev/null
      echo "${path}/$(basename $1)"
    }
esac


ROOT="${ROOT:-$(_absolute_path $(dirname $0))}"

case ${1:-} in
  build)
    NAME="${2}"
    IMAGE="${3}"
    docker exec "${NAME}" \
      tar -cf - -C ${BUILD_ROOT} . \
      | docker import "${@:4}" - "${IMAGE}"
    ;;
  cp)
    NAME="${2}"
    SOURCE="${3}"
    DEST="${4}"
    docker cp "${SOURCE}" "${NAME}":"${DEST}"
    ;;
  clean)
    NAME="${2}"
    docker stop "${NAME}"
    docker rm "${NAME}"
    ;;
  create)
    NAME="${2}"
    # --privileged is required to build glibc.
    docker run -d -it --name "${NAME}" \
      --privileged \
      --volumes-from "${PORTAGE_NAME}" \
      "${GENTOO_IMAGE}" /bin/bash
    $0 shell "${NAME}" -c 'mkdir -p /etc/portage/package.{keywords,mask,use}'
    $0 emerge "${NAME}" ${PACKAGES}
    ;;
  emerge)
    NAME="${2}"
    docker exec -it "${NAME}" \
      emerge --buildpkg --usepkg --onlydeps --quiet "${@:3}"
    docker exec -it "${NAME}" \
      emerge --buildpkg --usepkg --root="${BUILD_ROOT}" --root-deps=rdeps \
      --quiet "${@:3}"
    ;;
  portage)
    # TODO(kiyoya): Add update command and a command to delete old files.
    case ${2:-} in
      down)
        docker rm "${BUILD_NAME}"
        docker rm "${PORTAGE_NAME}"
        ;;
      pull)
        docker pull "${BUILD_IMAGE}"
        docker pull "${PORTAGE_IMAGE}"
        ;;
      up)
        docker create --name "${PORTAGE_NAME}" "${PORTAGE_IMAGE}"
        docker create --name "${BUILD_NAME}" \
          -v /usr/portage/distfiles \
          -v /usr/portage/packages \
          "${BUILD_IMAGE}"
        ;;
      *)
        echo "$0 portage [ down | pull | up ]"
        ;;
    esac
    ;;
  shell)
    NAME="${2}"
    docker exec -it "${NAME}" \
      /bin/bash "${@:3}"
    ;;
  *)
    echo "$0 [ build | clean | create | portage | shell ]"
    ;;
esac
