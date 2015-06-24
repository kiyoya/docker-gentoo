FROM fukansystem/gentoo:latest
MAINTAINER kiyoya <kiyoya@gmail.com>

RUN echo 'USE="${USE} zsh-completion"' >> /etc/portage/make.conf
RUN mkdir -p /etc/portage/package.{keywords,mask,use} && \
    echo "app-editors/vim python" > /etc/portage/package.use/gentoo
RUN emerge --quiet --newuse --update \
      app-editors/vim \
      app-misc/screen \
      app-shells/zsh \
      dev-python/pip \
      dev-util/cmake \
      dev-vcs/git \
      net-libs/nodejs && \
    rm -f '/usr/portage/distfiles/*'
RUN pip install awscli
RUN npm install -g \
      bower \
      polyserve

ADD Runfile /

ENTRYPOINT ["/Runfile"]
