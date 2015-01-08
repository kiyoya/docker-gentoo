FROM fukansystem/gentoo:latest
MAINTAINER kiyoya <kiyoya@gmail.com>

RUN emerge --quiet -u dev-python/pip;\
    rm -f '/usr/portage/distfiles/*'
RUN pip install awscli
