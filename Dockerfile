# Build stage
FROM golang:1.27-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG VERSION=dev
ARG COMMIT=none
RUN CGO_ENABLED=0 go build -ldflags "-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" -o /bin/shellfb ./cmd/shellfb

# Runtime stage
FROM alpine:3.24

RUN apk add --no-cache \
    bash \
    openssh-client \
    ca-certificates \
    libcap \
    && adduser -D -h /home/shellfb shellfb \
    && mkdir -p /var/lib/shellfb/certs \
    && chown shellfb:shellfb /var/lib/shellfb/certs

COPY --from=builder /bin/shellfb /usr/local/bin/shellfb
RUN setcap 'cap_net_bind_service=+ep' /usr/local/bin/shellfb

COPY config.example.yaml /etc/shellfb/config.yaml

USER shellfb
WORKDIR /home/shellfb

EXPOSE 4200 80 443

ENTRYPOINT ["shellfb"]
CMD ["--config", "/etc/shellfb/config.yaml"]
