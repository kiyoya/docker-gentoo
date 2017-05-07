# docker-gentoo

Scripts to build and maintain Gentoo-based docker images.

https://hub.docker.com/u/kiyoya/

## Initial setup

```shell
./bootstrap.sh portage pull
./bootstrap.sh portage up
./bootstrap.sh portage sync
```

If you are on Windows (MinGW or WSL) and using ConEmu, Docker may not work well
with pipes. See https://github.com/moby/moby/issues/28814 for the context and
workarounds.

## Building a new image

```shell
./bootstrap.sh portage pull
./bootstrap.sh portage sync

# Prepare a new image.
./bootstrap.sh create "${NAME}"

# Emerge in the new image.
./bootstrap.sh emerge "${NAME}" [ package atoms here ]

# Run commands in the new image.
./bootstrap.sh chroot "${NAME}"

# Finish and build the new image.
./bootstrap.sh build "${NAME}"

# Clean-up: Delete outdated files from packages/distfiles.
./bootstrap.sh portage eclean
```
