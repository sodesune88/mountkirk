#!/bin/sh

SERVER=${1-$SERVER}
RANDOM=`tr -dc 0-9 < /dev/urandom | head -c 8 ; echo`

# random session duration: 20 - 30 seconds (inclusive)
SESSION_DURATION=`shuf -i 20-30 -n 1`

PLAYER=player-$RANDOM
USER_DIR=.xonotic-$PLAYER

XONOTIC_HOME=../dev/Xonotic
LOG=$USER_DIR/log

die() {
    echo $@
    exit 1
}

PID=
cleanup() {
    [ -n "$PID" ] && kill -9 $PID
    rm -rf $USER_DIR
    echo $PLAYER ended
}

[ "$SERVER" != "" ] || die "$0: missing SERVER"
[ ! -d $XONOTIC/$USER_DIR ] || die "$0: collision - $XONOTIC/$USER_DIR exists!"

cp -r .xonotic-template $XONOTIC_HOME/$USER_DIR
cd $XONOTIC_HOME

echo $PLAYER starting [session: $SESSION_DURATION seconds] ...

./xonotic-linux-sdl.sh +connect $SERVER \
    +_cl_name $PLAYER -userdir $USER_DIR \
    +vid_fullscreen 0 +vid_width 640 +vid_height 480 +mastervolume 0 \
    >$LOG 2>&1 & PID=$!

(sleep $SESSION_DURATION && cleanup) &
