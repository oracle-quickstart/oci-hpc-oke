FROM --platform=$BUILDPLATFORM golang:1.25-alpine AS builder

ARG TARGETOS=linux
ARG TARGETARCH

WORKDIR /src

COPY vf-config.go .

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -o /vf-config vf-config.go

FROM alpine:3.21

COPY --from=builder /vf-config /usr/local/bin/vf-config

ENTRYPOINT ["/usr/local/bin/vf-config"]

CMD ["--help"]