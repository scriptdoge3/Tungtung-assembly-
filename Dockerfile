# Stage 1: assemble + link (needs only binutils)
FROM debian:stable-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends binutils \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY build.sh server.s ./
RUN ./build.sh

# Stage 2: ship the bare static binary — no OS, no shell, no libc, nothing
FROM scratch
COPY --from=build /src/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
