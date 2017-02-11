#!/bin/bash
# @(#) Script to build and maintain gentoo-based docker images.

set -eu

IMAGE_GENTOO="${IMAGE_GENTOO:-gentoo/stage3-amd64}"
NAME_PORTAGE="${NAME_PORTAGE:-portage}"
VOLUME_PORTAGE="${VOLUME_PORTAGE:-portage}"
VOLUME_DISTFILES="${VOLUME_DISTFILES:-portage-distfiles}"
VOLUME_PACKAGES="${VOLUME_PACKAGES:-portage-packages}"

# Fundamental packages
BASE_PACKAGES="
	app-shells/bash
	sys-apps/baselayout
	sys-apps/busybox
	sys-libs/glibc"

LOG_INFO="\033[1;31m"

if builtin command -v journalctl > /dev/null; then
	LOG_DRIVER='journald'
else
	LOG_DRIVER='json-file'
fi

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
	bootstrap_shell "${NAME}" <<-EOM
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
		bootstrap_shell "${NAME}" <<-EOM
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
	#	 | docker import "${@:3}" - "${IMAGE}"
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
		--volumes-from "${NAME_PORTAGE}":ro \
		-v "${VOLUME_PORTAGE}":/usr/portage:ro \
		-v "${VOLUME_DISTFILES}":/usr/portage/distfiles \
		-v "${VOLUME_PACKAGES}":/usr/portage/packages \
		"${@:2}" \
		"${IMAGE_GENTOO}" /bin/bash
	docker exec -i "${NAME}" \
		mkdir -p /etc/portage/package.keywords \
						 /etc/portage/package.mask \
						 /etc/portage/package.use
	bootstrap_emerge "${NAME}" ${BASE_PACKAGES}
	bootstrap_shell "${NAME}" <<-EOM
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
	docker exec -it "${NAME}" \
		emerge --buildpkg --usepkg --onlydeps --with-bdeps=y --quiet "${@:2}"
	docker exec -it "${NAME}" \
		emerge --buildpkg --usepkg --root=/build --root-deps=rdeps \
		--quiet "${@:2}"
}

function bootstrap_package_keywords() {
	local NAME="${1}"
	local FILEPATH="${2}"
	docker cp "${FILEPATH}" "${NAME}":/etc/portage/package.keywords/"${NAME}"
}

function bootstrap_package_mask() {
	local NAME="${1}"
	local FILEPATH="${2}"
	docker cp "${FILEPATH}" "${NAME}":/etc/portage/package.mask/"${NAME}"
}

function bootstrap_package_use() {
	local NAME="${1}"
	local FILEPATH="${2}"
	docker cp "${FILEPATH}" "${NAME}":/etc/portage/package.use/"${NAME}"
}

function bootstrap_shell() {
	local NAME="${1}"
	if [ -t 0 ]; then
		docker exec -it "${NAME}" /bin/bash "${@:2}"
	else
		docker exec -i "${NAME}" /bin/bash "${@:2}" -c "$(cat -)"
	fi
}

function bootstrap_shell_chroot() {
	local NAME="${1}"
	if [ -t 0 ]; then
		docker exec -it "${NAME}" chroot /build /bin/bash "${@:2}"
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

function docker_logs() {
	case "${LOG_DRIVER}" in
		journald)
			sudo journalctl CONTAINER_NAME="${NAME}" -f
			;;
		*)
			docker logs "${NAME}"
			;;
	esac
}

function docker_promote() {
	local IMAGE="${1}"
	local REPO="$(echo ${IMAGE} | cut -d : -f 1)"
	log "Promoting ${IMAGE} ..."
	docker tag "${IMAGE}" "${REPO}":latest
	docker push "${IMAGE}"
	docker push "${REPO}":latest
}

function die() {
	printf "${LOG_INFO}$@\033[0m\n" >&2
	exit 1
}

function log() {
	printf "${LOG_INFO}$@\033[0m\n"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	case ${1:-} in
		build)
			bootstrap_build "${@:2}"
			;;
		chroot)
			bootstrap_shell_chroot "${NAME}"
			;;
		create)
			bootstrap_create "${@:2}"
			;;
		emerge)
			bootstrap_emerge "${@:2}"
			;;
		portage)
			case ${2:-} in
				down)
					docker volume rm "${VOLUME_PORTAGE}"
					docker volume rm "${VOLUME_DISTFILES}"
					docker volume rm "${VOLUME_PACKAGES}"
					;;
				eclean)
					DURATION="${3:-3w}"
					docker run -i --rm \
						-h "${NAME_PORTAGE}" \
						-v "${VOLUME_PORTAGE}":/usr/portage:ro \
						-v "${VOLUME_DISTFILES}":/usr/portage/distfiles \
						-v "${VOLUME_PACKAGES}":/usr/portage/packages \
						"${IMAGE_GENTOO}" /bin/bash <<-EOM
							set -eu
							emerge --quiet --buildpkg --usepkg app-portage/gentoolkit
							eclean -dq -t ${DURATION} distfiles
							eclean -dq -t ${DURATION} packages
					EOM
					;;
				export)
					docker run -i --rm \
						-v "${VOLUME_PACKAGES}":/usr/portage/packages:ro \
						"${IMAGE_GENTOO}" tar -cf - /usr/portage/packages
					;;
				import)
					docker run -i --rm \
						-v "${VOLUME_PACKAGES}":/usr/portage/packages \
						"${IMAGE_GENTOO}" tar -xf - -C /
					;;
				pull)
					docker pull "${IMAGE_GENTOO}"
					;;
				shell)
					docker run -it --rm \
						-h "${NAME_PORTAGE}" \
						-v "${VOLUME_PORTAGE}":/usr/portage:ro \
						-v "${VOLUME_DISTFILES}":/usr/portage/distfiles \
						-v "${VOLUME_PACKAGES}":/usr/portage/packages \
						"${IMAGE_GENTOO}" /bin/bash
					;;
				sync)
					docker run -it --rm \
						-h "${NAME_PORTAGE}" \
						-v "${VOLUME_PORTAGE}":/usr/portage \
						-v "${VOLUME_DISTFILES}":/usr/portage/distfiles:ro \
						-v "${VOLUME_PACKAGES}":/usr/portage/packages:ro \
						"${IMAGE_GENTOO}" emerge --sync "${@:3}"
					;;
				up)
					docker volume create --name "${VOLUME_PORTAGE}"
					docker volume create --name "${VOLUME_DISTFILES}"
					docker volume create --name "${VOLUME_PACKAGES}"
					;;
				*)
					echo "$0 portage [ down | eclean | export | import | reload |" \
							 "shell | sync | up ]"
					;;
			esac
			;;
		shell)
			bootstrap_shell "${@:2}"
			;;
		*)
			echo "$0 [ build | chroot | create | emerge | portage | shell ]"
			;;
	esac
fi
