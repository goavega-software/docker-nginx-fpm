FROM ubuntu:16.04
LABEL MAINTAINER Goavega Docker Maintainers
#setup environment variables
#version variables
ENV NGINX_VERSION 1.12.1-1~xenial
ENV FPM_VERSION 7.0.28-0ubuntu0.16.04.1
ENV PHP_VERSION 1:7.0+35ubuntu6
ENV DOCKER_BUILD_DIR /dockerbuild

#directories
ENV NGINX_CONF /etc/nginx/nginx.conf
ENV APP_HOME /home/site/wwwroot/
#php confs
ENV php_scan_ini_dir /etc/php/7.0/fpm/conf.d/
ENV php_conf /etc/php/7.0/fpm/php.ini
ENV fpm_conf /etc/php/7.0/fpm/php-fpm.conf
ENV fpm_pool /etc/php/7.0/fpm/pool.d/www.conf
ENV NGINX_LOG_DIR /home/LogFiles/nginx/
# ssh
ENV SSH_PASSWD "root:Docker!"


WORKDIR $DOCKER_BUILD_DIR

#---------------|
# nginx         |
#---------------|
RUN apt-get update \
	&& apt-get install --no-install-recommends --no-install-suggests -y gnupg \
	&& \
	NGINX_GPGKEY=573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62; \
	found=''; \
	for server in \
	ha.pool.sks-keyservers.net \
	hkp://keyserver.ubuntu.com:80 \
	hkp://p80.pool.sks-keyservers.net:80 \
	pgp.mit.edu \
	; do \
	echo "Fetching GPG key $NGINX_GPGKEY from $server"; \
	apt-key adv --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$NGINX_GPGKEY" && found=yes && break; \
	done; \
	test -z "$found" && echo >&2 "error: failed to fetch GPG key $NGINX_GPGKEY" && exit 1; \
	apt-get -y --purge autoremove && rm -rf /var/lib/apt/lists/* \
	&& echo "deb http://nginx.org/packages/ubuntu/ xenial nginx" >> /etc/apt/sources.list \
	&& apt-get update \
	&& apt-get install --no-install-recommends --no-install-suggests -y nginx=${NGINX_VERSION} gettext-base
#--------------|
# php-fpm + mod|
#--------------|
RUN set -e \
	&& apt-get update \
	&& apt-get install --no-install-recommends --no-install-suggests -y php7.0-fpm=${FPM_VERSION} php7.0-mysql=${FPM_VERSION} \
	## install extensions that we might need
	# Wordpress Requirements
	&& apt-get -y --no-install-recommends --no-install-suggests install php7.0-xml=${FPM_VERSION} php7.0-mbstring=${FPM_VERSION} php7.0-bcmath=${FPM_VERSION} php7.0-zip=${FPM_VERSION} php7.0-curl=${FPM_VERSION} php7.0-gd=${FPM_VERSION} php7.0-intl=${FPM_VERSION} php7.0-imap=${FPM_VERSION} php7.0-pspell=${FPM_VERSION} php7.0-recode=${FPM_VERSION} php7.0-tidy=${FPM_VERSION} php7.0-xmlrpc=${FPM_VERSION} \
	#-------------|
	# ssh         |
	#-------------|
	&& apt-get install -y --no-install-recommends openssh-server supervisor \
	&& echo "$SSH_PASSWD" | chpasswd \
	#clean up
	&& rm -rf /var/lib/apt/lists/* \
	&& apt-get purge -y \
	&& apt-get autoremove -y \
	&& echo "daemon off;" >> ${NGINX_CONF}

# Hacks Nginx and php-fpm config (docker nginx runs nginx user - change fpm to use same user)
RUN set -ex && \
	sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" ${php_conf} && \
	sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 8M/g" ${php_conf} && \
	sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 8M/g" ${php_conf} && \
	sed -i -e "s/variables_order = \"GPCS\"/variables_order = \"EGPCS\"/g" ${php_conf} && \
	sed -i -e "s/listen = 127.0.0.1:9000/listen = \/run\/php7.0-fpm.sock/g" ${fpm_pool} && \
	sed -i -e "s/listen.owner = www-data/listen.owner = nginx/g" ${fpm_pool} && \
	sed -i -e "s/listen.group = www-data/listen.group = nginx/g" ${fpm_pool} && \
	sed -i -e "s/user = www-data/user = nginx/g" ${fpm_pool} && \
	sed -i -e "s/group = www-data/group = nginx/g" ${fpm_pool} && \
	sed -i -e "s/;catch_workers_output\s*=\s*no/catch_workers_output = yes/g" ${fpm_pool} && \
	sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" ${fpm_pool}
#link log files to /home
RUN rm -rf /var/log/nginx/ \
	&& mkdir -p ${NGINX_LOG_DIR} \
	&& ln -s /home/LogFiles/nginx /var/log/nginx
#copy configs
COPY ./confs/default.conf /etc/nginx/conf.d/
COPY ./wwwroot/* /home/site/wwwroot/
COPY ./entrypoint.sh /usr/local/bin/
COPY ./confs/sshd_config /etc/ssh/
COPY ./confs/10-opcache.ini ${php_ini_scan_dir}
COPY ./wp_env.sh /usr/local/bin/

#hostname that nginx listens to
ENV NGINX_HOST "_"
ENV NGINX_PERM_REDIR "krimzen.com"

RUN chmod u+x /usr/local/bin/wp_env.sh
RUN chmod u+x /usr/local/bin/entrypoint.sh

WORKDIR ${APP_HOME}

STOPSIGNAL SIGTERM
EXPOSE 80 2222

cmd ["entrypoint.sh"]
