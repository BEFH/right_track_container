FROM bellsoft/alpaquita-linux-base:stream-glibc

RUN apk add --no-cache curl tar xz bash

WORKDIR /app

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
