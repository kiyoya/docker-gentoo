# docker-gentoo

Scripts to build and maintain Gentoo-based docker images.

https://hub.docker.com/u/kiyoya/

## Initial setup

```shell
./bootstrap.sh portage pull
./bootstrap.sh portage up
./bootstrap.sh portage sync
```

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
