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
RUN GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8 \
	&& CONFIG="\
	--prefix=/etc/nginx \
	--sbin-path=/usr/sbin/nginx \
	--modules-path=/usr/lib/nginx/modules \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
	--pid-path=/var/run/nginx.pid \
	--lock-path=/var/run/nginx.lock \
	--http-client-body-temp-path=/var/cache/nginx/client_temp \
	--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
	--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
	--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
	--http-scgi-temp-path=/var/cache/nginx/scgi_temp \
	--user=nginx \
	--group=nginx \
	--with-http_ssl_module \
	--with-http_realip_module \
	--with-http_addition_module \
	--with-http_sub_module \
	--with-http_dav_module \
	--with-http_flv_module \
	--with-http_mp4_module \
	--with-http_gunzip_module \
	--with-http_gzip_static_module \
	--with-http_random_index_module \
	--with-http_secure_link_module \
	--with-http_stub_status_module \
	--with-http_auth_request_module \
	--with-http_xslt_module=dynamic \
	--with-http_image_filter_module=dynamic \
	--with-http_geoip_module=dynamic \
	--with-threads \
	--with-stream \
	--with-stream_ssl_module \
	--with-stream_ssl_preread_module \
	--with-stream_realip_module \
	--with-stream_geoip_module=dynamic \
	--with-http_slice_module \
	--with-mail \
	--with-mail_ssl_module \
	--with-compat \
	--with-file-aio \
	--with-http_v2_module \
	" \
	&& addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& apk add --no-cache --virtual .build-deps \
	gcc \
	libc-dev \
	make \
	openssl-dev \
	pcre-dev \
	zlib-dev \
	linux-headers \
	curl \
	gnupg \
	libxslt-dev \
	gd-dev \
	geoip-dev \
	&& curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
	&& curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc  -o nginx.tar.gz.asc \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& found=''; \
	for server in \
	ha.pool.sks-keyservers.net \
	hkp://keyserver.ubuntu.com:80 \
	hkp://p80.pool.sks-keyservers.net:80 \
	pgp.mit.edu \
	; do \
	echo "Fetching GPG key $GPG_KEYS from $server"; \
	gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
	done; \
	test -z "$found" && echo >&2 "error: failed to fetch GPG key $GPG_KEYS" && exit 1; \
	gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
	&& rm -rf "$GNUPGHOME" nginx.tar.gz.asc \
	&& mkdir -p /usr/src \
	&& tar -zxC /usr/src -f nginx.tar.gz \
	&& rm nginx.tar.gz \
	&& cd /usr/src/nginx-$NGINX_VERSION \
	&& ./configure $CONFIG --with-debug \
	&& make -j$(getconf _NPROCESSORS_ONLN) \
	&& mv objs/nginx objs/nginx-debug \
	&& mv objs/ngx_http_xslt_filter_module.so objs/ngx_http_xslt_filter_module-debug.so \
	&& mv objs/ngx_http_image_filter_module.so objs/ngx_http_image_filter_module-debug.so \
	&& mv objs/ngx_http_geoip_module.so objs/ngx_http_geoip_module-debug.so \
	&& mv objs/ngx_stream_geoip_module.so objs/ngx_stream_geoip_module-debug.so \
	&& ./configure $CONFIG \
	&& make -j$(getconf _NPROCESSORS_ONLN) \
	&& make install \
	&& rm -rf /etc/nginx/html/ \
	&& mkdir /etc/nginx/conf.d/ \
	&& mkdir -p /usr/share/nginx/html/ \
	&& install -m644 html/index.html /usr/share/nginx/html/ \
	&& install -m644 html/50x.html /usr/share/nginx/html/ \
	&& install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
	&& install -m755 objs/ngx_http_xslt_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_xslt_filter_module-debug.so \
	&& install -m755 objs/ngx_http_image_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_image_filter_module-debug.so \
	&& install -m755 objs/ngx_http_geoip_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip_module-debug.so \
	&& install -m755 objs/ngx_stream_geoip_module-debug.so /usr/lib/nginx/modules/ngx_stream_geoip_module-debug.so \
	&& ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
	&& strip /usr/sbin/nginx* \
	&& strip /usr/lib/nginx/modules/*.so \
	&& rm -rf /usr/src/nginx-$NGINX_VERSION \
	\
	# Bring in gettext so we can get `envsubst`, then throw
	# the rest away. To do this, we need to install `gettext`
	# then move `envsubst` out of the way so `gettext` can
	# be deleted completely, then move `envsubst` back.
	&& apk add --no-cache --virtual .gettext gettext \
	&& mv /usr/bin/envsubst /tmp/ \
	\
	&& runDeps="$( \
	scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
	| tr ',' '\n' \
	| sort -u \
	| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
	&& apk add --no-cache --virtual .nginx-rundeps $runDeps \
	&& apk del .build-deps \
	&& apk del .gettext \
	&& mv /tmp/envsubst /usr/local/bin/ \
	\
	# Bring in tzdata so users could set the timezones through the environment
	# variables
	&& apk add --no-cache tzdata \
	\
	# forward request and error logs to docker log collector
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

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
