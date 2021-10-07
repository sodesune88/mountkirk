# ref:
# https://github.com/googleforgames/agones/blob/release-1.17.0/examples/xonotic/Dockerfile

FROM debian:stretch

RUN useradd -u 1000 -m xonotic
WORKDIR /home/xonotic

COPY Xonotic Xonotic
COPY wrapper wrapper
COPY server.cfg .xonotic/data/server.cfg

RUN rm -rf Xonotic/{xonotic-linux64-glx,xonotic-linux64-sdl,xonotic-linux-glx.sh,xonotic-linux-sdl.sh,.xonotic-*,data/xonotic-20170401-music.pk3}

RUN chown -R xonotic:xonotic .


USER 1000
ENTRYPOINT /home/xonotic/wrapper -i /home/xonotic/Xonotic/server_linux.sh
