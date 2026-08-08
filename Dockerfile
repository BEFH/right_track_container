FROM bellsoft/alpaquita-linux-base:stream-glibc

RUN apk add --no-cache \
    curl \
    tar \
    xz \
    bash \
    libgcc \
    libstdc++ \
    libatomic \
    mariadb \
    mariadb-client \
    openssl

WORKDIR /app

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

