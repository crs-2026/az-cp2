FROM alpine:3.20
RUN apk add --no-cache nginx && mkdir -p /run/nginx
COPY index.html /var/www/localhost/htdocs/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
