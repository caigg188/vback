.PHONY: all web test test-ui-e2e test-minio-e2e build clean

all: test build

web:
	cd web && npm ci && npm run build

test:
	go test ./...
	bash tests/test_v1.sh
	cd web && npm run build

test-ui-e2e:
	cd web && npm run test:e2e

test-minio-e2e:
	bash tests/e2e_minio.sh

build: web
	mkdir -p dist
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o dist/vback ./cmd/vback

clean:
	rm -rf dist web/node_modules
