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

case "$(uname -a)" in
	# Windows Subsystem for Linux
	"Linux "*"-Microsoft "*)
		function volumepath() {
			python <<-EOM
				path = '$(realpath $@)'
				path = path.replace('/mnt/', '', 1)
				path = path.replace('/', ':\\\\', 1).replace('/', '\\\\')
				print(path)
			EOM
		}
		;;
	# Minimalist GNU for Windows
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
		if builtin command -v realpath > /dev/null; then
			function volumepath() {
				realpath "$@"
			}
		else
			function volumepath() {
				perl -e "use File::Spec;say STDOUT File::Spec->rel2abs('$@');"
			}
		fi
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
	# This may not work well with ConEmu (MinGW or WSL).
	# See https://github.com/moby/moby/issues/28814#issuecomment-295629353 for
	# workarounds.
	docker exec "${NAME}" tar -cf - -C /build . | \
		docker import "${@:3}" - "${IMAGE}"

	docker stop "${NAME}"
	docker rm "${NAME}"
}

function bootstrap_create() {
	local NAME="${1}"
	# --privileged is required to build glibc.
	docker run -it -d --name "${NAME}" \
		--privileged \
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

# TODO(kiyoya): Add a command to check affected packages by GLSA.
#               glsa-check -t all && glsa-check -d affected
function bootstrap_emerge_host() {
	local NAME="${1}"
	docker exec -it "${NAME}" \
		emerge --buildpkg --usepkg --quiet "${@:2}"
}

function bootstrap_make_conf() {
	local NAME="${1}"
	bootstrap_shell "${NAME}" -c \
		"cat >> /etc/portage/make.conf"
}

function bootstrap_package_keywords() {
	local NAME="${1}"
	bootstrap_shell "${NAME}" -c \
		"cat >> /etc/portage/package.keywords/${NAME}"
}

function bootstrap_package_mask() {
	local NAME="${1}"
	bootstrap_shell "${NAME}" -c \
		"cat >> /etc/portage/package.mask/${NAME}"
}

function bootstrap_package_use() {
	local NAME="${1}"
	bootstrap_shell "${NAME}" -c \
		"cat >> /etc/portage/package.use/${NAME}"
}

function bootstrap_shell() {
	local NAME="${1}"
	if [ -t 0 ]; then
		docker exec -it "${NAME}" /bin/bash "${@:2}"
	else
		docker exec -i "${NAME}" /bin/bash "${@:2}"
	fi
}

function bootstrap_shell_chroot() {
	local NAME="${1}"
	if [ -t 0 ]; then
		docker exec -it "${NAME}" chroot /build /bin/bash "${@:2}"
	else
		docker exec -i "${NAME}" chroot /build /bin/bash "${@:2}"
	fi
}

function docker_container_exists() {
	local NAME="${1}"
	docker ps -a --filter name=^/"${NAME}"$ | tail -n +2 | grep -q "${NAME}"
}

function docker_image_exists() {
	local IMAGE="${1}"
	local REPO="$(echo "${IMAGE}" | cut -d : -f 1)"
	local TAG="$(echo "${IMAGE}" | cut -d : -f 2)"
	docker images "${REPO}" | awk '{print $2}' | tail -n +2 | grep -q ^"${TAG}"$
}

function docker_volume_exists() {
	local VOLUME="${1}"
	docker volume inspect "${VOLUME}" 1> /dev/null 2>&1
}

function docker_volume_prepare() {
	local VOLUME="${1}"
	local S="${2}"
	docker volume create "${VOLUME}"
	tar -cf - -C "${2}" . | \
		docker run --rm -i \
			-v "${VOLUME}":/volume \
			busybox tar -x -f - -C /volume
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
	if docker_image_exists "${REPO}":latest; then
		docker tag "${REPO}":latest "${REPO}":previous
		docker push "${REPO}":previous
	fi
	docker tag "${IMAGE}" "${REPO}":latest
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
			bootstrap_shell_chroot "${@:2}"
			;;
		create)
			bootstrap_create "${@:2}"
			;;
		emerge)
			bootstrap_emerge "${@:2}"
			;;
		emerge_host)
			bootstrap_emerge_host "${@:2}"
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
				webrsync)
					docker run -it --rm \
						-h "${NAME_PORTAGE}" \
						-v "${VOLUME_PORTAGE}":/usr/portage \
						-v "${VOLUME_DISTFILES}":/usr/portage/distfiles:ro \
						-v "${VOLUME_PACKAGES}":/usr/portage/packages:ro \
						"${IMAGE_GENTOO}" emerge-webrsync "${@:3}"
					;;
				up)
					docker volume create --name "${VOLUME_PORTAGE}"
					docker volume create --name "${VOLUME_DISTFILES}"
					docker volume create --name "${VOLUME_PACKAGES}"
					;;
				*)
					echo "$0 portage [ down | eclean | export | import | reload |" \
							 "shell | sync | webrsync | up ]"
					;;
			esac
			;;
		shell)
			bootstrap_shell "${@:2}"
			;;
		*)
			echo "$0 [ build | chroot | create | emerge | emerge_host | portage | " \
				"shell ]"
			;;
	esac
fi
