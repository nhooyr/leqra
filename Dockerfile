# syntax=docker/dockerfile:1
ARG GO_VERSION=1.26
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
COPY web ./web
# Go tests read shared movement fixtures; include these in the build stage only.
COPY tests ./tests
RUN go test ./... && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/leqra .

FROM scratch
COPY --from=build /out/leqra /leqra
USER 65532:65532
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/leqra"]
