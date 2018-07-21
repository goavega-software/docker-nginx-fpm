#!/bin/bash
#setup all env variables needed
set_var_if_null(){
        local varname="$1"
        if [ ! "${!varname:-}" ]; then
                export "$varname"="$2"
        fi
}

update_settings(){
      set_var_if_null "DB_NAME" "www"
      set_var_if_null "DB_USER" "db_user"
      set_var_if_null "DB_PWD" "x"
      set_var_if_null "DB_HOST" "localhost"
      set_var_if_null "NGINX_HOST" "_"
}

set -ex
update_settings
echo "env[DB_USER]=$DB_USER" >> ${FPM_POOL_CONF}
echo "env[DB_PWD]=$DB_PWD" >> ${FPM_POOL_CONF}
echo "env[DB_HOST]=$DB_HOST" >> ${FPM_POOL_CONF}
echo "env[DB_NAME]=$DB_NAME" >> ${FPM_POOL_CONF}
