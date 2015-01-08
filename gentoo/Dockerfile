FROM fukansystem/gentoo:latest
MAINTAINER kiyoya <kiyoya@gmail.com>

RUN groupadd -g 1000 kiyoya
RUN useradd -u 1000 -g kiyoya -G users,wheel -s /bin/zsh kiyoya
RUN echo 'USE="${USE} zsh-completion"' >> /etc/portage/make.conf
RUN emerge --quiet -u --deep --newuse \
      app-misc/screen \
      app-shells/zsh \
      dev-vcs/git \
      net-libs/nodejs \
      world;\
    rm -f '/usr/portage/distfiles/*'

COPY docker-init.sh /
