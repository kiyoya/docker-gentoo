#!/bin/bash
# @(#) Script to build and maintain gentoo-based docker images.

ROOT="${ROOT:-$(dirname $0)}"
source "${ROOT}"/lib/common.sh


case ${1:-} in
  build)
    bootstrap_build "${@:2}"
    ;;
  clean)
    bootstrap_clean "${@:2}"
    ;;
  create)
    bootstrap_create "${@:2}"
    ;;
  emerge)
    bootstrap_emerge "${@:2}"
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
    bootstrap_shell "${@:2}"
    ;;
  *)
    echo "$0 [ build | clean | create | emerge | portage | shell ]"
    ;;
esac
