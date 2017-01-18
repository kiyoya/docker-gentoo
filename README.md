# docker-gentoo

Scripts to build and maintain gentoo-based docker images.

https://hub.docker.com/u/kiyoya/

## Initial setup

```shell
./bootstrap.sh portage pull
./bootstrap.sh portage up
```

## Biweekly update routine

```shell
./bootstrap.sh portage pull
./bootstrap.sh portage reload  # If there are updates at portage.

# kiyoya/gentoo
./gentoo/gentoo build
./gentoo/gentoo promote

# kiyoya/ml
./ml/ml build
./ml/ml promote

# kiyoya/murmur
./murmur/murmur build
./murmur/murmur promote

# kiyoya/vpn
./vpn/vpn build
./vpn/vpn promote

./bootstrap.sh portage eclean
```
