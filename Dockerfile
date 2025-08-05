FROM alpine:3.22.1

COPY . /dybatpho
WORKDIR /dybatpho

RUN /dybatpho/scripts/prerequisite_alpine.sh
ENTRYPOINT ["/dybatpho/scripts/entrypoint.sh"]
