SHELL = bash
# .ONESHELL:
# .SHELLFLAGS = -e
# See https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html
.PHONY: init check build *

#DOCKER_REGISTRY="synology:5000/"
#DOCKER_REGISTRY=
DOCKER_IMAGE_NAME=biarms/pgadmin4
DOCKER_IMAGE_TAGNAME=${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:linux-${BUILD_ARCH}-${DOCKER_IMAGE_VERSION}

default: build test tag push

# See https://www.gnu.org/software/make/manual/html_node/Shell-Function.html
BUILD_DATE=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF=$(shell git rev-parse --short HEAD)
DOCKER_IMAGE_VERSION=$(shell if [[ "${IMAGE_VERSION}" == "" ]]; then grep "ENV VERSION" Dockerfile | sed 's/.*=//'; else echo "${IMAGE_VERSION}"; fi)

check:
	# Check env variables
	@if [[ "${BUILD_ARCH}" == "" ]]; then \
		echo 'BUILD_ARCH is unset (MUST BE SET !)' && \
		echo 'Sample usage: QEMU_ARCH=arm BUILD_ARCH=arm32v7 make' && \
        exit 1; \
	fi
	@if [[ "${QEMU_ARCH}" == "" ]]; then \
		echo 'QEMU_ARCH is unset (MUST BE SET !)' && \
		echo 'Sample usage: QEMU_ARCH=arm BUILD_ARCH=arm32v7 make' && \
		exit 2; \
	fi
	@if [[ "${DOCKER_IMAGE_VERSION}" == "" ]]; then \
		echo 'DOCKER_IMAGE_VERSION is unset (MUST BE SET !)' && \
		echo 'Are you sure to have a ENV VERSION entry in your docker file ?' && \
		exit 3; \
	fi
	@which manifest-tool > /dev/null || (echo "Ensure that you've got the manifest-tool utility in your path. Could be downloaded from  https://github.com/estesp/manifest-tool/releases/download/" && exit 2)
	# Next line will fail if docker server can't be contacted
	@docker version > /dev/null
	# Debug
	@echo "DOCKER_REGISTRY: ${DOCKER_REGISTRY}"
	@echo "BUILD_DATE: ${BUILD_DATE}"
	@echo "DOCKER_IMAGE_VERSION: ${DOCKER_IMAGE_VERSION}"
	@echo "VCS_REF: ${VCS_REF}"

build: check
	docker build \
			--build-arg VCS_REF=${VCS_REF} \
			--build-arg BUILD_DATE=${BUILD_DATE} \
			--build-arg BUILD_ARCH=${BUILD_ARCH} \
			--build-arg QEMU_ARCH=${QEMU_ARCH} \
			-t ${DOCKER_IMAGE_NAME}:build .

test: check
	uname -a
	docker run --rm $(DOCKER_IMAGE_NAME):build
	docker run --rm $(DOCKER_IMAGE_NAME):build uname -a

tag: check
	docker tag $(DOCKER_IMAGE_NAME):build $(DOCKER_IMAGE_TAGNAME)

push-image: check
	docker push $(DOCKER_IMAGE_TAGNAME)

# When https://github.com/docker/cli/pull/138 merged branch will be part of an official release:
# docker manifest create biarms/mysql biarms/mysql-arm
# docker manifest annotate biarms/mysql biarms/mysql-arm --os linux --arch arm
# docker manifest push new-list-ref-name
#
# In the mean time, we use: https://github.com/estesp/manifest-tool
# https://github.com/estesp/manifest-tool/releases/download/v0.7.0/manifest-tool-linux-arm64 &&
#
# See also:
# 1. https://github.com/justincormack/cross-docker
# 2. https://docs.docker.com/docker-for-mac/multi-arch/
# 3. https://docs.docker.com/registry/spec/manifest-v2-2/#example-manifest-list
# 4. https://github.com/docker-library/official-images#architectures-other-than-amd64
# 5. https://github.com/docker-library/official-images/blob/a7ad3081aa5f51584653073424217e461b72670a/bashbrew/go/vendor/src/github.com/docker-library/go-dockerlibrary/architecture/oci-platform.go#L14-L25
#  "amd64":   {OS: "linux", Architecture: "amd64"},
#  "arm32v5": {OS: "linux", Architecture: "arm", Variant: "v5"},
#  "arm32v6": {OS: "linux", Architecture: "arm", Variant: "v6"},
#  "arm32v7": {OS: "linux", Architecture: "arm", Variant: "v7"},
#  "arm64v8": {OS: "linux", Architecture: "arm64", Variant: "v8"},
#  "i386":    {OS: "linux", Architecture: "386"},
#  "ppc64le": {OS: "linux", Architecture: "ppc64le"},
#  "s390x": {OS: "linux", Architecture: "s390x"},
#  "windows-amd64": {OS: "windows", Architecture: "amd64"},
push-manifest-core: check
	# When https://github.com/docker/cli/pull/138 merged branch will be part of an official release:
	# docker manifest create biarms/mysql biarms/mysql-arm
	# docker manifest annotate biarms/mysql biarms/mysql-arm --os linux --arch arm
	# docker manifest push new-list-ref-name
	#
	# In the mean time, I use: https://github.com/estesp/manifest-tool
	# sudo wget -O /usr/local/bin manifest-tool https://github.com/estesp/manifest-tool/releases/download/v0.7.0/manifest-tool-linux-armv7
	# sudo chmod +x /usr/local/bin/manifest-tool
	echo "manifests:" >> manifest.yaml
	echo "  - image: ${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:linux-arm32v6-${DOCKER_IMAGE_VERSION}" >> manifest.yaml
	echo "    platform:" >> manifest.yaml
	echo "      architecture: arm" >> manifest.yaml
	echo "      os: linux" >> manifest.yaml
	echo "      variant: xxx" >> manifest.yaml
	echo "  - image: ${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:linux-arm32v7-${DOCKER_IMAGE_VERSION}" >> manifest.yaml
	echo "    platform:" >> manifest.yaml
	echo "      architecture: arm" >> manifest.yaml
	echo "      os: linux" >> manifest.yaml
	echo "      variant: yyy" >> manifest.yaml
	echo "  - image: ${DOCKER_REGISTRY}${DOCKER_IMAGE_NAME}:linux-arm64v8-${DOCKER_IMAGE_VERSION}" >> manifest.yaml
	echo "    platform:" >> manifest.yaml
	echo "      architecture: arm64" >> manifest.yaml
	echo "      os: linux" >> manifest.yaml
	echo "      variant: zzz" >> manifest.yaml
	manifest-tool push from-spec manifest.yaml

push-manifest-first-line: check
	echo "image: $(DOCKER_REGISTRY)$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_VERSION)" > manifest.yaml

push-manifest-latest-first-line: check
	echo "image: $(DOCKER_REGISTRY)$(DOCKER_IMAGE_NAME):latest" > manifest.yaml

push-manifest: push-manifest-first-line push-manifest-core

push: push-image push-manifest

push-manifest-latest: push-manifest-latest-first-line push-manifest-core

push-latest: push-manifest-latest
	echo "Done"

rmi: check
	docker rmi -f $(DOCKER_IMAGE_NAME):build
	docker rmi -f $(DOCKER_IMAGE_TAGNAME)

rebuild: rmi build


