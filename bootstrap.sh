#!/bin/bash
# @(#) Script to build and maintain gentoo-based docker images.

set -eu

BUILD_IMAGE="${BUILD_IMAGE:-tianon/true}"
BUILD_NAME="${BUILD_NAME:-portage-build}"
BUILD_ROOT="${BUILD_ROOT:-/build}"
GENTOO_IMAGE="${GENTOO_IMAGE:-gentoo/stage3-amd64}"
PORTAGE_IMAGE="${PORTAGE_IMAGE:-gentoo/portage}"
PORTAGE_NAME="${PORTAGE_NAME:-portage}"

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
    docker run --rm \
      --volumes-from "${NAME}" \
      "${GENTOO_IMAGE}" \
      tar -cf - -C ${BUILD_ROOT} . \
      | docker import "${@:4}" - "${IMAGE}"
    ;;
  cp)
    NAME="${2}"
    SOURCE="${3}"
    DEST="${4}"
    docker cp "${SOURCE}" "${NAME}:${DEST}"
    ;;
  clean)
    NAME="${2}"
    docker rm "${NAME}"
    ;;
  create)
    NAME="${2}"
    docker create --name "${NAME}" \
      -v "${BUILD_ROOT}" \
      "${BUILD_IMAGE}"
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
    docker run -it --rm \
      --volumes-from "${PORTAGE_NAME}" \
      --volumes-from "${BUILD_NAME}" \
      --volumes-from "${NAME}" \
      -v "${ROOT}/bashrc:/bashrc:ro" \
      "${GENTOO_IMAGE}" \
      /bin/bash --rcfile /bashrc "${@:3}"
    ;;
  *)
    echo "$0 [ build | clean | create | portage | shell ]"
    ;;
esac
