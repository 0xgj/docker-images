#!/bin/sh

(crontab -l ; echo "*	*	*	*	*	/usr/local/openresty/bin/openresty -s reload") |  sort - | uniq - | crontab -

RESOLVER=${RESOLVER:-127.0.0.1};
MESOS=${MESOS:-leader.mesos:5050};
MARATHON=${MARATHON:-master.mesos:8080};
DCOS_HISTORY_SERVICE=${DCOS_HISTORY_SERVICE:-master.mesos:15055};
MESOS_DNS=${MESOS_DNS:-master.mesos:8123};
EXHIBITOR=${EXHIBITOR:-localhost:8181};
COSMOS=${COSMOS:-localhost:7070};
AUTH=${AUTH:-localhost:8101};
DDDT=${DDDT:-localhost:1050};
KEYSTONE=${KEYSTONE:-localhost:35357};
REGISTRY=${REGISTRY:-localhost:9090};
TASC=${TASC:-localhost:9092};
LOGS=${LOGS:-localhost:9200};
ALERT=${ALERT:-localhost:9093};
MONITOR=${MONITOR:-localhost:9090};

cat >/usr/local/openresty/nginx/conf/nginx.conf <<-EOF
# Log notice level and higher (e.g. state cache
# emits useful log messages on notice level).
error_log stderr notice;
daemon off;

events {
    worker_connections 1024;
}

http {
    access_log logs/access.log;
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    client_max_body_size 1024M;
    keepalive_timeout 65;

    # Without this, cosocket-based code in worker
    # initialization cannot resolve leader.mesos.
    resolver $RESOLVER;

    upstream mesos {
        server $MESOS;
    }

    upstream marathon {
        server $MARATHON;
    }

    upstream dcos_history_service {
        server $DCOS_HISTORY_SERVICE;
    }

    upstream mesos_dns {
        server $MESOS_DNS;
    }

    upstream exhibitor {
        server $EXHIBITOR;
    }

    upstream cosmos {
        server $COSMOS;
    }

    upstream auth {
        server $AUTH;
    }

    upstream dddt {
        server $DDDT;
    }

    upstream keystone {
        server $KEYSTONE;
    }

    upstream registry {
        server $REGISTRY;
    }

    upstream tasc {
        server $TASC;
    }

    upstream logs {
        server $LOGS;
    }

    upstream alert {
        server $ALERT;
    }

    upstream monitor {
        server $MONITOR;
    }

    proxy_cache_path /tmp/nginx-mesos-cache levels=1:2 keys_zone=mesos:1m inactive=10m;

    lua_package_path '\$prefix/conf/?.lua;;';
    lua_shared_dict mesos_state_cache 100m;
    lua_shared_dict shmlocks 100k;

    init_worker_by_lua '
        local statecache = require "mesosstatecache"
        statecache.periodically_poll_mesos_state()
    ';

    # Loading the auth module in the global Lua VM in the master process is a
    # requirement, so that code is executed under the user that spawns the
    # master process instead of 'nobody' (which workers operate under).
    init_by_lua '
        common = require "common"
        local use_auth = os.getenv("ADMINROUTER_ACTIVATE_AUTH_MODULE")
        if use_auth ~= "true" then
            ngx.log(
                ngx.NOTICE,
                "ADMINROUTER_ACTIVATE_AUTH_MODULE not `true`. " ..
                "Use dummy module."
                )
            auth = {}
            auth.validate_jwt_or_exit = function() return end
        else
            ngx.log(ngx.NOTICE, "Use auth module.")
            auth = require "auth"
        end
    ';

    server {
        listen 80 default_server;

        server_name dcos.*;
        root /dcos/dcos-ui/platform;

        location /acs/api/v1/auth/ {
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_pass http://auth;
        }

        location /acs/api/v1 {
            # Enforce access restriction to Auth API.
            access_by_lua 'auth.validate_jwt_or_exit()';
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_pass http://auth;
            # Instruct user agent to not cache the response.
            # Ref: http://stackoverflow.com/a/2068407/145400
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            add_header Pragma no-cache;
            add_header Expires 0;
        }

        location /system/health/v1 {
            access_by_lua 'auth.validate_jwt_or_exit()';
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$host;
            proxy_pass http://dddt;
        }

        location = /mesos {
            rewrite ^/mesos$ \$scheme://\$http_host/mesos/ permanent;
        }

        location /mesos/ {
            access_by_lua 'auth.validate_jwt_or_exit()';
            proxy_set_header Host \$http_host;
            proxy_pass http://mesos/;
        }

        location /cache/master/ {
            add_header X-Cache-Status \$upstream_cache_status;
            proxy_pass http://mesos/master/;
            proxy_cache mesos;
            proxy_cache_bypass  \$http_cache_control;
            proxy_cache_lock on;
            proxy_cache_valid 200 5s;
        }

        location = /exhibitor {
            rewrite ^/exhibitor$ \$scheme://\$http_host/exhibitor/ permanent;
        }

        location /exhibitor/ {
            access_by_lua 'auth.validate_jwt_or_exit()';
            proxy_pass http://exhibitor/;
            proxy_redirect http://\$proxy_host/ \$scheme://\$http_host/exhibitor/;
        }

        location ~ ^/slave/(?<slaveid>[0-9a-zA-Z-]+)(?<url>.*)$ {
            access_by_lua 'auth.validate_jwt_or_exit()';
            set \$slaveaddr '';

            more_clear_input_headers Accept-Encoding;
            rewrite ^/slave/[0-9a-zA-Z-]+/.*$ \$url break;
            rewrite_by_lua_file conf/slave.lua;

            proxy_set_header        Host \$http_host;
            proxy_set_header        X-Real-IP \$remote_addr;
            proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto \$scheme;

            proxy_pass http://\$slaveaddr;
        }

        location /marathon/ {
            proxy_pass http://marathon/;
        }

        location ^~ /service/marathon/v2/ {
            proxy_pass http://marathon/v2/;
        }

        location ^~ /service/marathon/ {
            alias /dcos/dcos-ui/asc/;
        }

        # Delete once customized marathon is completed.
        location ^~ /service/marathon/marathon/v2/ {
            proxy_pass http://marathon/v2/;
        }

        location ~ ^/service/(?<serviceid>[0-9a-zA-Z-.]+)$ {
            # Append slash and 301-redirect.
            rewrite ^/service/(.*)$ /service/\$1/ permanent;
        }

        location ~ ^/service/(?<serviceid>[0-9a-zA-Z-.]+)/(?<url>.*) {
            set \$serviceurl '';
            set \$servicescheme '';

            access_by_lua 'auth.validate_jwt_or_exit()';

            more_clear_input_headers Accept-Encoding;
            rewrite ^/service/[0-9a-zA-Z-.]+/?.*$ /\$url break;
            rewrite_by_lua_file conf/service.lua;

            proxy_set_header        Host \$http_host;
            proxy_set_header        X-Real-IP \$remote_addr;
            proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto \$scheme;

            proxy_pass \$serviceurl;
            proxy_redirect \$servicescheme://\$host/service/\$serviceid/ /service/\$serviceid/;
            proxy_redirect \$servicescheme://\$host/ /service/\$serviceid/;
            proxy_redirect / /service/\$serviceid/;

            # Disable buffering to allow real-time protocols
            proxy_buffering off;

            # Support web sockets and SPDY upgrades
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        location /dcos-history-service/ {
            access_by_lua 'auth.validate_jwt_or_exit()';
            proxy_pass http://dcos_history_service/;
        }

        location = /mesos_dns {
            rewrite ^/mesos_dns$ \$scheme://\$http_host/mesos_dns/ permanent;
        }

        location /mesos_dns/ {
            access_by_lua 'auth.validate_jwt_or_exit()';
            proxy_set_header Host \$http_host;
            proxy_pass http://mesos_dns/;
        }

        location /tasc/api/v1/ {
            proxy_set_header Host \$http_host;
            proxy_pass http://tasc/tasc/api/v1/;
        }

        location /dcos-metadata/dcos-hosts.json {
            # mapping /etc/hosts to this endpoint,
            # used by platform to display agents'name with real hostname
            alias /dcos/dcos-ui/dcos-hosts.json;
        }

        location /acs/api/v2.0/ {
            proxy_set_header Host \$http_host;
            proxy_pass http://keystone/v2.0/;
        }

        location /acs/api/v3/ {
            proxy_set_header Host \$http_host;
            proxy_pass http://keystone/v3/;
        }

        location /logs/ {
            proxy_set_header Host \$http_host;
            proxy_pass http://logs/;
        }

        location /alert/ {
            proxy_set_header Host \$http_host;
            proxy_pass http://alert/;
        }

        location /monitor/ {
            proxy_set_header Host \$http_host;
            proxy_pass http://monitor/;
        }

        location /registry/api/v1/ {
            proxy_set_header Host \$http_host;
            proxy_pass http://registry/registry/api/v1/;
        }
    }
}
EOF

[ -d /dcos ] && /usr/local/openresty/bin/openresty
