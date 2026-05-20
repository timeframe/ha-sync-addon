ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.19
FROM ${BUILD_FROM}

RUN apk add --no-cache curl jq

COPY run.sh /
RUN chmod a+x /run.sh
