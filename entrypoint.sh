#!/bin/bash
log(){
	while read line ; do
		echo "`date '+%D %T'` $line"
	done
}

set -e
logfile=/home/LogFiles/entrypoint.log
test ! -f $logfile && mkdir -p /home/LogFiles && touch $logfile
exec > >(log | tee -ai $logfile)
exec 2>&1

set_var_if_null(){
	local varname="$1"
	if [ ! "${!varname:-}" ]; then
		export "$varname"="$2"
	fi
}

#update_settings(){
#	set_var_if_null "DATABASE_NAME" "www"
#	set_var_if_null "DATABASE_USERNAME" "appuser"
#	set_var_if_null "DATABASE_PASSWORD" "MS173m_QN"
#}

set -e
test ! -d "$APP_HOME" && echo "INFO: $APP_HOME not found. creating ..." && mkdir -p "$APP_HOME"
chown -R nginx:nginx $APP_HOME
# echo 'INFO: exporting variables'
# wp_env.sh
echo 'INFO: starting fpm'
php-fpm -D
echo 'INFO: starting nginx'
/usr/sbin/nginx
