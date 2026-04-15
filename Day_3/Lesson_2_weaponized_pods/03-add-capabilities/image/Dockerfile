FROM ubuntu:questing AS module-builder
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential \
  linux-headers-$(uname -r)
COPY Makefile .
COPY Totally_Legit_Module.c .
RUN make

FROM nginx:stable-alpine3.23
COPY --from=module-builder /Totally_Legit_Module.ko /docker-entrypoint.d/Totally_Legit_Module.ko
COPY entrypoint.sh /docker-entrypoint.d/entrypoint.sh
RUN chmod +x /docker-entrypoint.d/entrypoint.sh
COPY index.html /usr/share/nginx/html/
