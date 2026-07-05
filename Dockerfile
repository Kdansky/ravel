FROM alpine:3.21 AS lovejs

ARG LOVEJS_REF=main
ARG LOVEJS_VERSION=11.5

RUN apk add --no-cache curl tar

RUN mkdir -p /tmp/lovejs /out/lovejs \
	&& curl -fsSL "https://codeload.github.com/2dengine/love.js/tar.gz/refs/heads/${LOVEJS_REF}" -o /tmp/lovejs.tar.gz \
	&& tar -xzf /tmp/lovejs.tar.gz -C /tmp/lovejs --strip-components=1 \
	&& cp /tmp/lovejs/player.js /tmp/lovejs/style.css /out/lovejs/ \
	&& cp -R /tmp/lovejs/lua /out/lua \
	&& cp -R "/tmp/lovejs/${LOVEJS_VERSION}" "/out/lovejs/${LOVEJS_VERSION}"

FROM nginx:1.27-alpine

RUN apk add --no-cache zip inotify-tools

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY --from=lovejs /out/lovejs /usr/share/nginx/html/lovejs
COPY --from=lovejs /out/lovejs/11.5 /usr/share/nginx/html/11.5
COPY --from=lovejs /out/lua /usr/share/nginx/html/lua
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh

# game/ is expected at /workspace/game via a volume mount (see docker-compose.yml).
# The entrypoint packs it into game.love on startup and repacks on every file change.
WORKDIR /workspace

EXPOSE 8080

CMD ["/docker-entrypoint.sh"]
