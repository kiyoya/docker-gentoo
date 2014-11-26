FROM fukansystem/gentoo:latest
MAINTAINER kiyoya <kiyoya@gmail.com>

RUN groupadd -g 1000 kiyoya
RUN useradd -u 1000 -g kiyoya -G users,wheel -s /bin/zsh kiyoya
RUN emerge --quiet -u \
      app-misc/screen \
      app-shells/zsh \
      dev-vcs/git \
      net-libs/nodejs
