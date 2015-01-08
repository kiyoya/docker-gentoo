FROM fukansystem/gentoo:latest
MAINTAINER kiyoya <kiyoya@gmail.com>

RUN mkdir -p /etc/portage/package.keywords;\
    mkdir -p /etc/portage/package.use;\
    echo 'media-sound/murmur ~amd64' > /etc/portage/package.keywords/murmur;\
    echo 'dev-libs/Ice python' > /etc/portage/package.use/murmur
RUN emerge --quiet -u media-sound/murmur;\
    rm -f '/usr/portage/distfiles/*'
ADD https://raw.githubusercontent.com/mumble-voip/mumble-scripts/master/Helpers/mice.py \
    /usr/local/bin/mice.py
RUN chmod 755 /usr/local/bin/mice.py

ENV HOME /var/lib/murmur
EXPOSE 64738

ENTRYPOINT ["/usr/bin/murmurd"]
CMD ["-fg", "-ini", "/etc/murmur/murmur.ini"]
