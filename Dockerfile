ARG BUILD_ARCH
# Perform a multi-stage build as explained at https://docs.docker.com/v17.09/engine/userguide/eng-image/multistage-build/#name-your-build-stages
FROM biarms/qemu-bin:latest as qemu-bin-ref

# To be able to build 'arm' images on Travis (which is x64 based), it is mandatory to explicitly reference the ${BUILD_ARCH} image
FROM ${BUILD_ARCH}/alpine:3.8
# ARG BUILD_ARCH line was duplicated on purpose: "An ARG declared before a FROM is outside of a build stage, so it can’t be used in any instruction after a FROM."
# See https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact
ARG BUILD_ARCH
ARG QEMU_ARCH
# COPY tmp/qemu-arm-static /usr/bin/qemu-arm-static
# ADD https://github.com/multiarch/qemu-user-static/releases/download/v2.9.1-1/qemu-arm-static /usr/bin/qemu-arm-static
COPY --from=qemu-bin-ref /usr/bin/qemu-${QEMU_ARCH}-static /usr/bin/qemu-${QEMU_ARCH}-static

# Inspired from https://github.com/simonqbs-dockerfiles/arm-pgadmin4
ENV PYTHONDONTWRITEBYTECODE=1

RUN \
	apk add --no-cache python python-dev py-pip postgresql-dev

# Install postgresql tools for backup/restore
RUN apk add --no-cache postgresql \
 && cp /usr/bin/psql /usr/bin/pg_dump /usr/bin/pg_dumpall /usr/bin/pg_restore /usr/local/bin/ \
 && apk del postgresql

ENV VERSION=3.0

RUN apk add --no-cache alpine-sdk postgresql-dev \
 && pip install --upgrade pip \
 && echo "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v${VERSION}/pip/pgadmin4-${VERSION}-py2.py3-none-any.whl" | pip install --no-cache-dir -r /dev/stdin \
 && apk del alpine-sdk \
 && addgroup -g 50 -S pgadmin \
 && adduser -D -S -h /pgadmin -s /sbin/nologin -u 1000 -G pgadmin pgadmin \
 && mkdir -p /pgadmin/config /pgadmin/storage \
 && chown -R 1000:50 /pgadmin

EXPOSE 5050

COPY LICENSE config_local.py /usr/lib/python2.7/site-packages/pgadmin4/

USER pgadmin:pgadmin
CMD [ "python", "./usr/lib/python2.7/site-packages/pgadmin4/pgAdmin4.py" ]
VOLUME /pgadmin/

ARG BUILD_DATE
ARG VCS_REF
LABEL \
	org.label-schema.build-date=$BUILD_DATE \
	org.label-schema.vcs-ref=$VCS_REF \
	org.label-schema.vcs-url="https://github.com/biarms/pgadmin4"
