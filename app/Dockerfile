FROM nginx:1.27-alpine

ARG BUILD_SHA=unknown

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html

RUN sed -i "s|__BUILD_SHA__|${BUILD_SHA}|g" /etc/nginx/nginx.conf \
    && sed -i "s|__BUILD_SHA__|${BUILD_SHA}|g" /usr/share/nginx/html/index.html \
    && mkdir -p /tmp/nginx \
    && chown -R nginx:nginx /tmp/nginx /var/cache/nginx /usr/share/nginx/html \
    && nginx -t

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
