FROM fukansystem/gentoo:latest
MAINTAINER kiyoya <kiyoya@gmail.com>

ADD package.mask /etc/portage/package.mask
ADD package.keywords /etc/portage/package.keywords/openvpn
ADD openvpn-2.3.4.ebuild \
    /usr/portage/net-misc/openvpn/openvpn-2.3.4.ebuild
RUN ebuild /usr/portage/net-misc/openvpn/openvpn-2.3.4.ebuild digest
RUN emerge --quiet -u net-misc/openvpn &&\
    rm -f '/usr/portage/distfiles/*'

COPY docker-entrypoint.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]

VOLUME ["/etc/openvpn"]

EXPOSE 1194
EXPOSE 1194/udp
