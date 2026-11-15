FROM alpine:3.24.4

COPY . /dybatpho
WORKDIR /dybatpho

RUN /dybatpho/scripts/prerequisite_alpine.sh
ENTRYPOINT ["/dybatpho/scripts/entrypoint.sh"]
