FROM alpine:latest

# Install minimal runtime dependencies required for Node and tarballs
RUN apk add --no-cache \
    curl \
    tar \
    xz \
    gcompat \
    bash \
    libgcc \
    libstdc++ \
    libatomic

WORKDIR /app

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
