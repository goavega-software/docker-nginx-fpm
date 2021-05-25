FROM php:7.3-fpm-alpine
LABEL MAINTAINER Goavega Docker Maintainers
#setup environment variables
#version variables
ENV DOCKER_BUILD_DIR /dockerbuild
ENV PHP_UUID_VERSION 1.0.4
ENV PHP_REDIS_VERSION 4.1.0
ENV NGINX_VERSION 1.18.0-r13
#directories
ENV NGINX_CONF /etc/nginx/nginx.conf
ENV APP_HOME /app/site/
#php confs
ENV php_scan_ini_dir /usr/local/etc/php/conf.d/
ENV FPM_POOL_CONF /usr/local/etc/php-fpm.d/www.conf
# ssh
ENV SSH_PASSWD "root:Docker!"
WORKDIR $DOCKER_BUILD_DIR

#|-----------------------|
#| get bash, sed         |
#| php redis and uuid    |
#|-----------------------|
RUN apk add --no-cache bash gawk sed grep bc coreutils libuuid util-linux-dev
RUN apk add --no-cache --virtual .phpize-deps $PHPIZE_DEPS \
	&& pecl install uuid-${PHP_UUID_VERSION} \
	&& pecl install redis-${PHP_REDIS_VERSION} \
	&& docker-php-ext-enable uuid redis \
	&& apk del .phpize-deps
#|-----------------------|
#| get php gd            |
#| openssh, rc           |
#| supervisor            |
#|-----------------------|
RUN apk add --no-cache freetype-dev \
	libjpeg-turbo-dev \
	libpng-dev \
	openrc \
	openssh \
	supervisor \
	&& docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
	&& docker-php-ext-install -j$(nproc) gd \
	&& apk del freetype-dev \
	libjpeg-turbo-dev \
	libpng-dev \
	util-linux-dev \
	&& rc-update add sshd

#-----------------------|
#   nginx               |
#-----------------------|
RUN apk add --no-cache nginx 

#--------------|
# make nginx   |
# nondaemon    |
#--------------|
RUN set -e \
	echo "$SSH_PASSWD" | chpasswd \
	&& echo "daemon off;" >> ${NGINX_CONF}

# Hacks Nginx and php-fpm config (docker nginx runs nginx user - change fpm to use same user)
RUN set -ex && \
	sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 8M/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 8M/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/variables_order = \"GPCS\"/variables_order = \"EGPCS\"/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/listen = 127.0.0.1:9000/listen = \/run\/php7.0-fpm.sock/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/listen.owner = www-data/listen.owner = nginx/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/listen.group = www-data/listen.group = nginx/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/user = www-data/user = nginx/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/group = www-data/group = nginx/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/;catch_workers_output\s*=\s*no/catch_workers_output = yes/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" ${FPM_POOL_CONF}
#copy configs
COPY ./confs/default.conf /etc/nginx/conf.d/
COPY ./wwwroot/* ${APP_HOME}/
COPY ./entrypoint.sh /usr/local/bin/
COPY ./confs/sshd_config /etc/ssh/
COPY ./confs/opcache.ini ${php_scan_ini_dir}
COPY ./wp_env.sh /usr/local/bin/

RUN chmod u+x /usr/local/bin/wp_env.sh
RUN chmod u+x /usr/local/bin/entrypoint.sh

WORKDIR ${APP_HOME}

STOPSIGNAL SIGTERM
EXPOSE 80 2222

CMD ["entrypoint.sh"]
