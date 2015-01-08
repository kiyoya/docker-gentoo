FROM fukansystem/gentoo:latest
MAINTAINER kiyoya <kiyoya@gmail.com>

RUN mkdir -p /etc/portage/package.keywords;\
    echo 'media-sound/murmur ~amd64' > /etc/portage/package.keywords/murmur
RUN emerge --quiet -u media-sound/murmur;\
    rm -f '/usr/portage/distfiles/*'

ENV HOME /var/lib/murmur
EXPOSE 64738

ENTRYPOINT ["/usr/bin/murmurd"]
CMD ["-fg", "-ini", "/etc/murmur/murmur.ini"]
