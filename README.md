# docker-gentoo

Scripts to build and maintain gentoo-based docker images.

https://hub.docker.com/u/kiyoya/

## Biweekly update routine

```shell
./bootstrap.sh portage pull
./ml/ml build
./murmur/murmur build
./openvpn/openvpn build
./ml/ml promote
./murmur/murmur promote
./openvpn/openvpn promote
docker push kiyoya/ml
docker push kiyoya/murmur
docker push kiyoya/openvpn
./bootstrap.sh portage eclean
```
