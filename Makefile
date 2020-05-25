SHELL = bash
# .ONESHELL:
# .SHELLFLAGS = -e
# See https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html

# DOCKER_REGISTRY: Nothing, or 'registry:5000/'
DOCKER_REGISTRY ?= docker.io/
# DOCKER_USERNAME: Nothing, or 'biarms'
DOCKER_USERNAME ?=
# DOCKER_PASSWORD: Nothing, or '********'
DOCKER_PASSWORD ?=
# BETA_VERSION: Nothing, or '-beta-123'
BETA_VERSION ?=
DOCKER_IMAGE_NAME = biarms/pgadmin4
DOCKER_IMAGE_VERSION = $(shell grep "ENV PGADMIN_VERSION" Dockerfile | sed 's/.*=//';)
PYTHON_VERSION = $(shell grep "ARG PYTHON_VERSION" Dockerfile | sed 's/.*=//';)
DOCKER_IMAGE_VERSION = 4.21
# GITHUB_TAG = REL-4_21
# PYTHON_VERSION = 3.6
DOCKER_IMAGE_TAGNAME = ${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}${BETA_VERSION}
# See https://www.gnu.org/software/make/manual/html_node/Shell-Function.html
# BUILD_DATE=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_DATE=$(shell date -u +"%Y-%m-%d") # rerunning builds are faster with this settings ;)
# See https://microbadger.com/labels
VCS_REF=$(shell git rev-parse --short HEAD)

PLATFORM ?= linux/arm/v6,linux/arm/v7,linux/arm64/v8,linux/amd64

.PHONY: default
default: all

# 2 builds are implemented: build and buildx (for the fun)
.PHONY: all
all: all-build

.PHONY: all-buildx
all-buildx: check-docker-login buildx uninstall-qemu

.PHONY: all-build
all-build: check-docker-login test build create-and-push-manifests uninstall-qemu

.PHONY: build
build: build-all-images

.PHONY: test
test: test-all-images

# Launch a local build as on circleci, that will call the default target, but inside the 'circleci build and test env'
.PHONY: circleci-local-build
circleci-local-build: check-docker-login
	@ circleci local execute -e DOCKER_USERNAME="${DOCKER_USERNAME}" -e DOCKER_PASSWORD="${DOCKER_PASSWORD}"

.PHONY: check-binaries
check-binaries:
	@ which docker > /dev/null || (echo "Please install docker before using this script" && exit 1)
	@ which git > /dev/null || (echo "Please install git before using this script" && exit 2)
	@ # deprecated: which manifest-tool > /dev/null || (echo "Ensure that you've got the manifest-tool utility in your path. Could be downloaded from  https://github.com/estesp/manifest-tool/releases/" && exit 3)
	@ DOCKER_CLI_EXPERIMENTAL=enabled docker manifest --help | grep "docker manifest COMMAND" > /dev/null || (echo "docker manifest is needed. Consider upgrading docker" && exit 4)
	@ DOCKER_CLI_EXPERIMENTAL=enabled docker version -f '{{.Client.Experimental}}' | grep "true" > /dev/null || (echo "docker experimental mode is not enabled" && exit 5)
	# Debug info
	@ echo "DOCKER_REGISTRY: ${DOCKER_REGISTRY}"
	@ echo "BUILD_DATE: ${BUILD_DATE}"
	@ echo "VCS_REF: ${VCS_REF}"
	# Next line will fail if docker server can't be contacted
	docker version

.PHONY: check-docker-login
check-docker-login: check-binaries
	@ if [[ "${DOCKER_USERNAME}" == "" ]]; then \
	    echo "DOCKER_USERNAME and DOCKER_PASSWORD env variables are mandatory for this kind of build"; \
	    echo "Consider one of these alternatives: "; \
	    echo "  - make build"; \
	    echo "  - DOCKER_USERNAME=biarms DOCKER_PASSWORD=******** BETA_VERSION='-local-test-pushed-on-docker-io' make"; \
	    echo "  - DOCKER_USERNAME=biarms DOCKER_PASSWORD=******** make circleci-local-build"; \
	    exit -1; \
	  fi

.PHONY: docker-login-if-possible
docker-login-if-possible: check-binaries
	if [[ ! "${DOCKER_USERNAME}" == "" ]]; then echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USERNAME}" --password-stdin; fi

# Test are qemu based. SHOULD_DO: use `docker buildx bake`. See https://github.com/docker/buildx#buildx-bake-options-target
.PHONY: install-qemu
install-qemu: check-binaries
	# @ # From https://github.com/multiarch/qemu-user-static:
	docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

.PHONY: install-qemu
uninstall-qemu: uninstall-qemu
	docker run --rm --privileged multiarch/qemu-user-static:register --reset

# See https://docs.docker.com/buildx/working-with-buildx/
.PHONY: check-buildx
check-buildx: check-binaries
	DOCKER_CLI_EXPERIMENTAL=enabled docker buildx version

.PHONY: buildx-prepare
buildx-prepare: install-qemu check-buildx
	DOCKER_CLI_EXPERIMENTAL=enabled docker context create buildx-multi-arch-context || true
	DOCKER_CLI_EXPERIMENTAL=enabled docker buildx create buildx-multi-arch-context --name=buildx-multi-arch || true
	DOCKER_CLI_EXPERIMENTAL=enabled docker buildx use buildx-multi-arch
	# Debug info
	@ echo "DOCKER_IMAGE_TAGNAME: ${DOCKER_IMAGE_TAGNAME}"

#.PHONY: checkout
checkout: check-binaries
#	git clone https://github.com/postgres/pgadmin4 git-src || true
#	cd git-src && git checkout tags/$(GITHUB_TAG)

.PHONY: buildx
buildx: docker-login-if-possible buildx-prepare checkout
	# cd git-src && \
	DOCKER_CLI_EXPERIMENTAL=enabled docker buildx build --progress plain -f Dockerfile --push --platform "${PLATFORM}" --tag "$(DOCKER_REGISTRY)${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}${BETA_VERSION}" --build-arg VERSION="${DOCKER_IMAGE_VERSION}" --build-arg VCS_REF="${VCS_REF}" --build-arg BUILD_DATE="${BUILD_DATE}" .
	# cd git-src && \
	DOCKER_CLI_EXPERIMENTAL=enabled docker buildx build --progress plain -f Dockerfile --push --platform "${PLATFORM}" --tag "$(DOCKER_REGISTRY)${DOCKER_IMAGE_NAME}:latest${BETA_VERSION}" --build-arg VERSION="${DOCKER_IMAGE_VERSION}" --build-arg VCS_REF="${VCS_REF}" --build-arg BUILD_DATE="${BUILD_DATE}" .

# build-all-one-image-arm32v6 => manifest for arm32v6/php:7.4-apache not found
.PHONY: build-all-images
build-all-images: build-all-one-image-amd64 build-all-one-image-arm64v8 build-all-one-image-arm32v7 build-all-one-image-arm32v6

.PHONY: build-all-one-image-arm32v6
build-all-one-image-arm32v6:
	ARCH=arm32v6 LINUX_ARCH=armv6l  make build-all-one-image

.PHONY: build-all-one-image-arm32v7
build-all-one-image-arm32v7:
	ARCH=arm32v7 LINUX_ARCH=armv7l  make build-all-one-image

.PHONY: build-all-one-image-arm64v8
build-all-one-image-arm64v8:
	ARCH=arm64v8 LINUX_ARCH=aarch64 make build-all-one-image

.PHONY: build-all-one-image-amd64
build-all-one-image-amd64:
	ARCH=amd64   LINUX_ARCH=x86_64  make build-all-one-image

.PHONY: create-and-push-manifests
create-and-push-manifests: #ideally, should reference 'build-all-images', but that's boring when we test this script...
	# biarms/phpmyadmin:x.y.z
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create --amend "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm32v7${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm64v8${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-amd64${BETA_VERSION}"
	# DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm32v6${BETA_VERSION}" --os linux --arch arm --variant v6
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm32v7${BETA_VERSION}" --os linux --arch arm --variant v7
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm64v8${BETA_VERSION}" --os linux --arch arm64 --variant v8
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-amd64${BETA_VERSION}" --os linux --arch amd64
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}${BETA_VERSION}"
	# biarms/phpmyadmin:latest
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create --amend "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:latest${BETA_VERSION}"            "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm32v7${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm64v8${BETA_VERSION}" "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-amd64${BETA_VERSION}"
	# DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:latest${BETA_VERSION}"                  "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm32v6${BETA_VERSION}" --os linux --arch arm --variant v6
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:latest${BETA_VERSION}"                  "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm32v7${BETA_VERSION}" --os linux --arch arm --variant v7
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:latest${BETA_VERSION}"                  "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-arm64v8${BETA_VERSION}" --os linux --arch arm64 --variant v8
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:latest${BETA_VERSION}"                  "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-amd64${BETA_VERSION}" --os linux --arch amd64
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push "${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:latest${BETA_VERSION}"

# Fails with: "standard_init_linux.go:211: exec user process caused "no such file or directory"" if qemu is not installed...
.PHONY: test-all-images
test-all-images: test-arm32v6 test-arm32v7 test-arm64v8 test-amd64
	echo "All tests are OK :)"

.PHONY: test-arm32v6
test-arm32v6:
	ARCH=arm32v6 LINUX_ARCH=armv6l DOCKER_IMAGE_VERSION=$(DOCKER_IMAGE_VERSION) make test-one-image

.PHONY: test-arm32v7
test-arm32v7:
	ARCH=arm32v7 LINUX_ARCH=armv7l DOCKER_IMAGE_VERSION=$(DOCKER_IMAGE_VERSION) make test-one-image

.PHONY: test-arm64v8
test-arm64v8:
	ARCH=arm64v8 LINUX_ARCH=aarch64 DOCKER_IMAGE_VERSION=$(DOCKER_IMAGE_VERSION) make test-one-image

.PHONY: test-amd64
test-amd64:
	ARCH=amd64 LINUX_ARCH=x86_64 DOCKER_IMAGE_VERSION=$(DOCKER_IMAGE_VERSION) make test-one-image

## Caution: this Makefile has 'multiple entries', which means that it is 'calling himself'.
# For instance, if you call 'make circleci-local-build':
# 1. CircleCi cli is invoked
# 2. After have installed a build environment (inside a docker container), CircleCI will call "make" without parameter, which correspond to a 'make all' build (because of default target)
# 3. And the 'all' target will run 4 times the "make test-one-image" for 3 different architecture (arm32v7, arm64v8 and amd64), via the 'test-all-images' target.
# See https://github.com/docker-library/official-images#architectures-other-than-amd64
# |---------|------------|
# |  ARCH   | LINUX_ARCH |
# |---------|------------|
# |  amd64  |   x86_64   |
# | arm32v6 |   armv6l   |
# | arm32v7 |   armv7l   |
# | arm64v8 |   aarch64  |
# |---------|------------|
ARCH ?=
LINUX_ARCH ?=
BUILD_ARCH = $(ARCH)/
MULTI_ARCH_DOCKER_IMAGE_TAGNAME = ${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}-linux-${ARCH}${BETA_VERSION}

## Multi-arch targets

# Actually, the 'push' will only be done is DOCKER_USERNAME is set and not empty !
.PHONY: build-all-one-image
build-all-one-image: build-one-image test-one-image push-one-image

.PHONY: check
check: check-binaries
	@ if [[ "$(ARCH)" == "" ]]; then \
	    echo 'ARCH is $(ARCH) (MUST BE SET !)' && \
	    echo 'Correct usage sample: ' && \
        echo '    ARCH=arm64v8 LINUX_ARCH=aarch64 DOCKER_IMAGE_VERSION=1.2.3 make test-one-image' && \
	    echo '    or ' && \
        echo '    ARCH=arm64v8 LINUX_ARCH=aarch64 DOCKER_IMAGE_VERSION=1.2.3 make test-one-image' && \
        exit -1; \
	fi
	@ if [[ "$(LINUX_ARCH)" == "" ]]; then \
	    echo 'LINUX_ARCH is $(LINUX_ARCH) (MUST BE SET !)' && \
	    echo 'Correct usage sample: ' && \
	    echo '    ARCH=arm32v7 LINUX_ARCH=armv7l DOCKER_IMAGE_VERSION=1.2.3 make test-one-image' && \
	    echo '    or ' && \
        echo '    ARCH=arm64v8 LINUX_ARCH=aarch64 DOCKER_IMAGE_VERSION=1.2.3 make test-one-image' && \
        exit -2; \
	fi
	# Debug info
	@ echo "MULTI_ARCH_DOCKER_IMAGE_TAGNAME: ${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}"

.PHONY: prepare
prepare: check install-qemu

.PHONY: build-one-image
build-one-image: prepare #checkout prepare
	#cp git-src/Dockerfile git-src/Dockerfile-orig
	#cp .dockerignore git-src/.
	#cp Dockerfile git-src/.
	#cd git-src && \
	docker build -t "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" --build-arg VERSION="${DOCKER_IMAGE_VERSION}" --build-arg VCS_REF="${VCS_REF}" --build-arg BUILD_DATE="${BUILD_DATE}" --build-arg BUILD_ARCH="${BUILD_ARCH}" ${DOCKER_FILE} .

# Won't be OK with official images
.PHONY: run-smoke-tests
run-smoke-tests: prepare
	# Smoke tests:
	docker run --rm "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" /bin/echo "Success." | grep "Success"
	docker run --rm "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" uname -a
	docker run --rm "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" cat /etc/os-release
	docker run --rm "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" cat /etc/os-release | grep 'VERSION_ID=3.11'
	# docker run --rm "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" cat /etc/os-release | grep 'VERSION_ID=3.11.6'
	docker run --rm "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" python --version
	# Mandatory: Dockerfile expect this:
	docker run --rm "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" python 2>&1 --version | grep "${PYTHON_VERSION}"
	echo "Nice to have"
	# Just for doc purposes ;)
 	# | grep '3.6.10'
	docker run --rm "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}" pip --version
 	# | grep 'pip 20.1.1'

.PHONY: pgadmin4-tc-01
pgadmin4-tc-01: prepare
	# Search for 'Starting pgAdmin 4. Please navigate to http://0.0.0.0:5050 in your browser.' in the logs
	# Test Case 1: test that the server starts
	docker stop pgadmin4-tc-01 || true
	docker rm pgadmin4-tc-01 || true
	# # With the 'official images', PGADMIN_DEFAULT_EMAIL and PGADMIN_DEFAULT_PASSWORD params are mandatory
	# docker create --name pgadmin4-tc-01 -e PGADMIN_DEFAULT_EMAIL=a -e PGADMIN_DEFAULT_PASSWORD=b ${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}
	docker create --name pgadmin4-tc-01 ${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}
	docker start pgadmin4-tc-01
	# This TC implements a fail fast algorithm: the container as 10 seconds to start and 120 seconds to be ready:
	# 1. Search for a message similar to "NOTE: Configuring authentication for [SERVER-DESKTOP] mode" that must come in less than 10 seconds
	# 2. Search for a "Starting pgAdmin 4. Please navigate...5050" like message that must come in less than 120 seconds
	###  2. Search for a "[INFO] Listening at: http://[::]:80" like message that must come in less than 120 seconds
	i=0 ;\
	timeout=10 ;\
	while ! (docker logs pgadmin4-tc-01 2>&1 | grep 'Starting pgAdmin 4. Please navigate' | grep '5050') ; do \
       i=$$[$$i+1] ;\
       if (docker logs pgadmin4-tc-01 2>&1 | grep -q 'Configuring authentication for') ; then \
		  timeout=120 ;\
       fi ;\
       if [ $$i -gt $$timeout ]; then \
         docker logs pgadmin4-tc-01 ;\
         echo "TC-01 failed" ;\
         exit -101 ;\
       fi ;\
       sleep 1 ;\
	done
	# docker run --rm -it --link mysql-test ${DOCKER_IMAGE_NAME} bash -c 'sleep 1 && mysql -h mysql-test -u testuser -ptestpassword -e "show variables;" testdb'
	docker stop pgadmin4-tc-01
	docker rm pgadmin4-tc-01

.PHONY: test-one-image
test-one-image: build-one-image run-smoke-tests pgadmin4-tc-01

.PHONY: push-one-image
push-one-image: check docker-login-if-possible
	# push only is 'DOCKER_USERNAME' (and hopefully DOCKER_PASSWORD) are set:
	if [[ ! "${DOCKER_USERNAME}" == "" ]]; then docker push "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}"; fi

# Helper targets
.PHONY: rmi-one-image
rmi-one-image: check
	docker rmi -f "${MULTI_ARCH_DOCKER_IMAGE_TAGNAME}"

.PHONY: rebuild-one-image
rebuild-one-image: rmi-one-image build-one-image