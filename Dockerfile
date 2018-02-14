# Inspired from https://github.com/simonqbs-dockerfiles/arm-pgadmin4
# FROM alpine:3.7
FROM arm32v6/alpine:3.7
# FROM hypriot/rpi-alpine:3.6

COPY tmp/qemu-arm-static /usr/bin/qemu-arm-static

ENV PYTHONDONTWRITEBYTECODE=1

RUN \
	apk add --no-cache python postgresql-dev

ARG PGADMIN_VERSION

RUN \
	apk add --no-cache --virtual .build-deps python-dev py-pip alpine-sdk \
	&& echo "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v${PGADMIN_VERSION}/pip/pgadmin4-${PGADMIN_VERSION}-py2.py3-none-any.whl" > requirements.txt \
	&& pip install --no-cache-dir -r requirements.txt \
	&& rm requirements.txt \
	&& apk del .build-deps

RUN \
	addgroup -g 50 -S pgadmin \
	&& adduser -D -S -h /pgadmin -s /sbin/nologin -u 1000 -G pgadmin pgadmin \
	&& mkdir -p /pgadmin/config /pgadmin/storage \
 	&& chown -R 1000:50 /pgadmin

EXPOSE 5050

COPY LICENSE config_local.py /usr/lib/python2.7/site-packages/pgadmin4/

USER pgadmin:pgadmin
CMD [ "python", "./usr/lib/python2.7/site-packages/pgadmin4/pgAdmin4.py" ]
VOLUME /pgadmin/

ARG VCS_REF
ARG BUILD_DATE

LABEL \
	org.label-schema.build-date=$BUILD_DATE \
	org.label-schema.vcs-ref=$VCS_REF \
	org.label-schema.vcs-url="https://github.com/biarms/pgadmin4"
