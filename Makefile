SHELL = /bin/bash

.DEFAULT_GOAL := all

APP_NAME=qomon_geo_lib
# The docker image might contain secret, it's not meant to be pushed
# IMAGE_REPOSITORY=registry.gitlab.com/quorumsco/datascience/data-libs-bakery/$(APP_NAME)
IMAGE_REPOSITORY=local-only-$(APP_NAME)

ifdef CI_JOB_ID
	DOCKER_USER_UID=2000
	DOCKER_USER_GID=2000
	APP_VERSION=$(shell git rev-parse --short HEAD)

	IMAGE_TAG=$(CI_COMMIT_REF_SLUG)-$(APP_VERSION)-test

	PYPI_GITLAB_USERNAME=gitlab-ci-token
	PYPI_GITLAB_PASSWORD=$(CI_JOB_TOKEN)
else
	DOCKER_USER_UID=$(shell id -u)
	DOCKER_USER_GID=$(shell id -g)
	APP_VERSION=latest

	IMAGE_TAG=local-test-latest

	PYPI_GITLAB_USERNAME=$(POETRY_HTTP_BASIC_GITLAB_QOMON_DATASCIENCE_USERNAME)
	PYPI_GITLAB_PASSWORD=$(POETRY_HTTP_BASIC_GITLAB_QOMON_DATASCIENCE_PASSWORD)
endif


DOCKER_RUN_DEV=docker run --rm -t \
	-e POETRY_HTTP_BASIC_GITLAB_QOMON_DATASCIENCE_USERNAME=$(PYPI_GITLAB_USERNAME) \
	-e POETRY_HTTP_BASIC_GITLAB_QOMON_DATASCIENCE_PASSWORD=$(PYPI_GITLAB_PASSWORD) \
	-v $(shell pwd):/home/$(APP_NAME)/app \
	$(IMAGE_REPOSITORY):$(IMAGE_TAG)

## help: Display list of commands
.PHONY: help
help: Makefile
	@sed -n 's|^##||p' $< | column -t -s ':' | sed -e 's|^| |'

## all: Run all targets
.PHONY: all
all: init style test

## init: Bootstrap your application.
.PHONY: init
init: build
	-pre-commit install -t pre-commit -t commit-msg --install-hooks
	poetry install --no-root --all-extras

## style: Check lint, code styling rules.
.PHONY: style
style:
	$(DOCKER_RUN_DEV) bash scripts/style.sh --style $(FILES_TO_STYLE)

## format: Check lint, code styling rules.
.PHONY: format
format:
	$(DOCKER_RUN_DEV) bash scripts/style.sh --format $(FILES_TO_STYLE)

## test: Shortcut to launch all the test tasks (unit, functional and integration).
.PHONY: test
test:
	PYPI_GITLAB_USERNAME="$(PYPI_GITLAB_USERNAME)" \
	PYPI_GITLAB_PASSWORD="$(PYPI_GITLAB_PASSWORD)" \
	QOMON_GEO_LIB__RUN_CMD="tox" \
	QOMON_GEO_LIB_TEST_DOCKER_IMAGE="$(IMAGE_REPOSITORY):$(IMAGE_TAG)" \
		docker compose -f docker-compose.test.yaml up --exit-code-from lib \
			&& ([ $$? -eq 0 ] && QOMON_GEO_LIB_TEST_DOCKER_IMAGE="$(IMAGE_REPOSITORY):$(IMAGE_TAG)" docker compose -f docker-compose.test.yaml down) \
			|| (QOMON_GEO_LIB_TEST_DOCKER_IMAGE="$(IMAGE_REPOSITORY):$(IMAGE_TAG)" docker compose -f docker-compose.test.yaml down && exit 1)

## test-debug: Shortcut to launch the db container to run tests locally
.PHONY: test-debug
test-debug:
	PYPI_GITLAB_USERNAME="$(PYPI_GITLAB_USERNAME)" \
	PYPI_GITLAB_PASSWORD="$(PYPI_GITLAB_PASSWORD)" \
	QOMON_GEO_LIB__RUN_CMD="tox" \
	QOMON_GEO_LIB_TEST_DOCKER_IMAGE="$(IMAGE_REPOSITORY):$(IMAGE_TAG)" \
		docker compose -f docker-compose.test.yaml -f docker-compose.test-debug.yaml up postgresql

## build: Shortcut to build the docker image
.PHONY: build
build:
	docker buildx build . \
		-t $(IMAGE_REPOSITORY):$(IMAGE_TAG) \
		--build-arg BUILDKIT_INLINE_CACHE=1 \
		--build-arg USER_UID=$(DOCKER_USER_UID) \
		--build-arg USER_GID=$(DOCKER_USER_GID) \
		--build-arg POETRY_HTTP_BASIC_GITLAB_QOMON_DATASCIENCE_USERNAME=$(PYPI_GITLAB_USERNAME) \
		--build-arg POETRY_HTTP_BASIC_GITLAB_QOMON_DATASCIENCE_PASSWORD=$(PYPI_GITLAB_PASSWORD) \
		--build-arg APP_VERSION=$(APP_VERSION) \
		--build-arg APP_NAME=$(APP_NAME)

## release: Shortcut to release the package on gitlab
.PHONY: release
release:
	rm -rf build
	$(DOCKER_RUN_DEV) bash scripts/release.bash

## clean: Remove temporary files
.PHONY: clean
clean:
	-pre-commit uninstall -t pre-commit -t commit-msg
	-rm -rf .mypy_cache ./**/.pytest_cache .coverage
	-poetry env remove python
	-docker image prune -a --force --filter "label=internal.app_name=$(APP_NAME)"
