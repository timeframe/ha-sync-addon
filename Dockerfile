FROM alpine:3.19

RUN apk add --no-cache curl jq bash

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
