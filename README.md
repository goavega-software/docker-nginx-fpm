** Docker file for PHP 7 FPM with nginx **

Primarily for linux app service Azure for Front Controller PHP sites like WordPress

* Contains SSH as per Azure App Service to enable webssh from kudu
* Writes to /home/ SMB share
* Exports few well know env variables to support APP Settings (look at wp_env.sh)
* Configurable nginx server block using ENV NGINX_HOST (TBD on 301 redirects)
