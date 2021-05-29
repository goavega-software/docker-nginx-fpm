FROM php:7.3-fpm-alpine
LABEL MAINTAINER Goavega Docker Maintainers
#setup environment variables
#version variables
ENV DOCKER_BUILD_DIR /dockerbuild
ENV PHP_UUID_VERSION 1.0.4
ENV PHP_REDIS_VERSION 4.1.0
ENV NGINX_VERSION 1.15.1
#directories
ENV NGINX_CONF /etc/nginx/nginx.conf
ENV APP_HOME /home/site/wwwroot/
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
ENV NGINX_VERSION 1.21.0
ENV NJS_VERSION   0.5.3
ENV PKG_RELEASE   1

RUN set -x \
# create nginx user/group first, to be consistent throughout docker variants
    && addgroup -g 101 -S nginx \
    && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    && apkArch="$(cat /etc/apk/arch)" \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${PKG_RELEASE} \
    " \
    && case "$apkArch" in \
        x86_64|aarch64) \
# arches officially built by upstream
            set -x \
            && KEY_SHA512="e7fa8303923d9b95db37a77ad46c68fd4755ff935d0a534d26eba83de193c76166c68bfe7f65471bf8881004ef4aa6df3e34689c305662750c0172fca5d8552a *stdin" \
            && apk add --no-cache --virtual .cert-deps \
                openssl \
            && wget -O /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
            && if [ "$(openssl rsa -pubin -in /tmp/nginx_signing.rsa.pub -text -noout | openssl sha512 -r)" = "$KEY_SHA512" ]; then \
                echo "key verification succeeded!"; \
                mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/; \
            else \
                echo "key verification failed!"; \
                exit 1; \
            fi \
            && apk del .cert-deps \
            && apk add -X "https://nginx.org/packages/mainline/alpine/v$(egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release)/main" --no-cache $nginxPackages \
            ;; \
        *) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from the published packaging sources
            set -x \
            && tempDir="$(mktemp -d)" \
            && chown nobody:nobody $tempDir \
            && apk add --no-cache --virtual .build-deps \
                gcc \
                libc-dev \
                make \
                openssl-dev \
                pcre-dev \
                zlib-dev \
                linux-headers \
                libxslt-dev \
                gd-dev \
                geoip-dev \
                perl-dev \
                libedit-dev \
                mercurial \
                bash \
                alpine-sdk \
                findutils \
            && su nobody -s /bin/sh -c " \
                export HOME=${tempDir} \
                && cd ${tempDir} \
                && hg clone https://hg.nginx.org/pkg-oss \
                && cd pkg-oss \
                && hg up ${NGINX_VERSION}-${PKG_RELEASE} \
                && cd alpine \
                && make all \
                && apk index -o ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz ${tempDir}/packages/alpine/${apkArch}/*.apk \
                && abuild-sign -k ${tempDir}/.abuild/abuild-key.rsa ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz \
                " \
            && cp ${tempDir}/.abuild/abuild-key.rsa.pub /etc/apk/keys/ \
            && apk del .build-deps \
            && apk add -X ${tempDir}/packages/alpine/ --no-cache $nginxPackages \
            ;; \
    esac \
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    && if [ -n "$tempDir" ]; then rm -rf "$tempDir"; fi \
    && if [ -n "/etc/apk/keys/abuild-key.rsa.pub" ]; then rm -f /etc/apk/keys/abuild-key.rsa.pub; fi \
    && if [ -n "/etc/apk/keys/nginx_signing.rsa.pub" ]; then rm -f /etc/apk/keys/nginx_signing.rsa.pub; fi \
# Bring in gettext so we can get `envsubst`, then throw
# the rest away. To do this, we need to install `gettext`
# then move `envsubst` out of the way so `gettext` can
# be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
        scanelf --needed --nobanner /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
# Bring in tzdata so users could set the timezones through the environment
# variables
    && apk add --no-cache tzdata \
# Bring in curl and ca-certificates to make registering on DNS SD easier
    && apk add --no-cache curl ca-certificates \
# forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
# create a docker-entrypoint.d directory
    && mkdir /docker-entrypoint.d
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
	sed -i -e "s/;listen.owner = www-data/listen.owner = nginx/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/;listen.group = www-data/listen.group = nginx/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/user = www-data/user = nginx/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/group = www-data/group = nginx/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/;catch_workers_output\s*=\s*no/catch_workers_output = yes/g" ${FPM_POOL_CONF} && \
	sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" ${FPM_POOL_CONF} && \
    sed -i -e "s/;clear_env\s*=\s*no/clear_env=no/g" ${FPM_POOL_CONF}
#copy configs
COPY ./confs/default.conf /etc/nginx/conf.d/
ENV APP_HOME /app/site/
COPY ./wwwroot/* ${APP_HOME}
COPY ./entrypoint.sh /usr/local/bin/
COPY ./confs/sshd_config /etc/ssh/
COPY ./confs/opcache.ini ${php_scan_ini_dir}
COPY ./wp_env.sh /usr/local/bin/

RUN chmod u+x /usr/local/bin/wp_env.sh
RUN set -eux && \
	chmod u+x /usr/local/bin/entrypoint.sh && \
	rm /usr/local/etc/php-fpm.d/docker.conf && \
	rm /usr/local/etc/php-fpm.d/zz-docker.conf

WORKDIR ${APP_HOME}

STOPSIGNAL SIGTERM
EXPOSE 80 2222

CMD ["entrypoint.sh"]
