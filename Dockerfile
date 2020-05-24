ARG BUILD_ARCH
# This code is no more needed, according to https://github.com/multiarch/qemu-user-static#multiarch-compatible-images-deprecated
# Perform a multi-stage build as explained at https://docs.docker.com/v17.09/engine/userguide/eng-image/multistage-build/#name-your-build-stages
# FROM biarms/qemu-bin:latest as qemu-bin-ref

# To be able to build 'arm' images on Travis (which is x64 based), it is mandatory to explicitly reference the ${BUILD_ARCH} image
# FROM ${BUILD_ARCH}python:2-alpine3.8
FROM ${BUILD_ARCH}python:2-alpine3.11
# FROM ${BUILD_ARCH}python:3.6.10-alpine3.11
# To find latest alpine version, see https://hub.docker.com/_/alpine?tab=description

# create a non-privileged user to use at runtime
RUN addgroup -g 50 -S pgadmin \
 && adduser -D -S -h /pgadmin -s /sbin/nologin -u 1000 -G pgadmin pgadmin \
 && mkdir -p /pgadmin/config /pgadmin/storage \
 && chown -R 1000:50 /pgadmin

# Install postgresql tools for backup/restore
RUN apk add --no-cache libedit postgresql \
 && cp /usr/bin/psql /usr/bin/pg_dump /usr/bin/pg_dumpall /usr/bin/pg_restore /usr/local/bin/ \
 && apk del postgresql

RUN apk add --no-cache postgresql-dev libffi-dev

# See https://www.pgadmin.org/download/pgadmin-4-python-wheel/
ENV PGADMIN_VERSION=4.21
ENV PYTHONDONTWRITEBYTECODE=1

RUN apk add --no-cache alpine-sdk linux-headers \
 && pip install --upgrade pip \
 && echo "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v${PGADMIN_VERSION}/pip/pgadmin4-${PGADMIN_VERSION}-py2.py3-none-any.whl" | pip install --no-cache-dir -r /dev/stdin \
 && apk del alpine-sdk linux-headers

EXPOSE 5050

COPY LICENSE config_distro.py /usr/local/lib/python2.7/site-packages/pgadmin4/

USER pgadmin:pgadmin
CMD ["python", "./usr/local/lib/python2.7/site-packages/pgadmin4/pgAdmin4.py"]
VOLUME /pgadmin/

ARG BUILD_DATE
ARG VCS_REF
LABEL \
	org.label-schema.build-date=$BUILD_DATE \
	org.label-schema.vcs-ref=$VCS_REF \
	org.label-schema.vcs-url="https://github.com/biarms/pgadmin4"
