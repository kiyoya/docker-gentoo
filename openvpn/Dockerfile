FROM fukansystem/gentoo:latest
MAINTAINER kiyoya <kiyoya@gmail.com>

RUN emerge --quiet -u \
      app-crypt/easy-rsa net-misc/openvpn &&\
    rm -f '/usr/portage/distfiles/*'

COPY docker-entrypoint.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]

VOLUME ["/etc/openvpn"]

EXPOSE 1194
EXPOSE 1194/udp
