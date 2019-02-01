PRIVATE_KEY = $(wildcard *.rsa)
PUBLIC_KEY = $(wildcard *.rsa.pub)
ALPINE_VERSION = 3.9

repository:
	docker build --build-arg privatekey=$(PRIVATE_KEY) --build-arg publickey=$(PUBLIC_KEY) --build-arg alpineversion=$(ALPINE_VERSION) -t digitalocean-alpine-builder .
	-docker rm digitalocean-alpine-builder
	docker run -t --name digitalocean-alpine-builder digitalocean-alpine-builder
	mkdir -p repository/$(ALPINE_VERSION)
	docker cp digitalocean-alpine-builder:/home/build/packages/build/x86_64 repository/$(ALPINE_VERSION)

clean:
	-docker rm digitalocean-alpine-builder
	-docker rmi digitalocean-alpine-builder

.PHONY: repository clean
