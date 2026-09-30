FROM nickblah/lua:5.1-luarocks-alpine
RUN apk add --no-cache build-base unzip curl git python3 && luarocks install busted 2.2.0-1
WORKDIR /work
