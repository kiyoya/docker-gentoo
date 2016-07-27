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
    # TODO(kiyoya): Add a command to update the portage image.
    case ${2:-} in
      down)
        docker rm "${BUILD_NAME}"
        docker rm "${PORTAGE_NAME}"
        ;;
      eclean)
        DURATION="${3:-3w}"
        docker run ${DOCKER_OPTS} --rm \
          --volumes-from "${BUILD_NAME}" \
          --volumes-from "${PORTAGE_NAME}" \
          "${GENTOO_IMAGE}" /bin/bash -x <<EOM
          emerge --quiet --buildpkg --usepkg app-portage/gentoolkit
          eclean -dq -t ${DURATION} distfiles
          eclean -dq -t ${DURATION} packages
EOM
        ;;
      pull)
        docker pull "${BUILD_IMAGE}"
        docker pull "${PORTAGE_IMAGE}"
        ;;
      shell)
        # NOTE: It requires -t option.
        docker run -it --rm \
          --volumes-from "${BUILD_NAME}" \
          --volumes-from "${PORTAGE_NAME}" \
          "${GENTOO_IMAGE}" /bin/bash
        ;;
      up)
        docker create --name "${PORTAGE_NAME}" "${PORTAGE_IMAGE}"
        docker create --name "${BUILD_NAME}" \
          -v /usr/portage/distfiles \
          -v /usr/portage/packages \
          "${BUILD_IMAGE}"
        ;;
      *)
        echo "$0 portage [ down | eclean | pull | shell | up ]"
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
