FROM php:5-fpm
MAINTAINER kiyoya <kiyoya@gmail.com>

RUN apt-get update &&\
    apt-get install -y libjpeg-dev libpng-dev
RUN docker-php-ext-configure gd \
      --with-jpeg-dir=/usr --with-png-dir=/usr &&\
    docker-php-ext-install gd mbstring pdo_mysql
