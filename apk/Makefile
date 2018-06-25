PRIVATE_KEY = $(wildcard *.rsa)
PUBLIC_KEY = $(wildcard *.rsa.pub)

repository:
	docker build --build-arg privatekey=$(PRIVATE_KEY) --build-arg publickey=$(PUBLIC_KEY) -t digitalocean-alpine-builder .
	-docker rm digitalocean-alpine-builder
	docker run -t --name digitalocean-alpine-builder digitalocean-alpine-builder
	mkdir -p repository
	docker cp digitalocean-alpine-builder:/home/build/packages/build/x86_64 repository/

clean:
	-docker rm digitalocean-alpine-builder
	-docker rmi digitalocean-alpine-builder

.PHONY: repository clean
