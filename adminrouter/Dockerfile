FROM openresty/openresty:1.11.2.1-alpine

ADD conf /usr/local/openresty/nginx/conf
ADD start.sh /start.sh
ENTRYPOINT ["/start.sh"]
