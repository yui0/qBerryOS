#!/bin/bash

# QKEY Server Startup Script
# Usage: ./qkey-server.sh {start|stop|restart|status}

PID_FILE=/var/run/qkey.pid
LOG_FILE=/var/log/qkey.log
BINARY=/usr/bin/qkey
#ARGS="server --listen-port 8080 --interface-name tun0 --key-rotation-secs 21600 --heartbeat-secs 30 --max-clients 100"
ARGS="--gateway"

start() {
    if [ -f $PID_FILE ]; then
        echo "QKEY Server is already running (PID: $(cat $PID_FILE))"
        exit 1
    fi
    echo "Starting QKEY Server..."
    RUST_LOG=info nohup $BINARY $ARGS >> $LOG_FILE 2>&1 &
    echo $! > $PID_FILE
    echo "Started with PID $(cat $PID_FILE)"
}

stop() {
    if [ ! -f $PID_FILE ]; then
        echo "QKEY Server is not running"
        exit 1
    fi
    echo "Stopping QKEY Server..."
    kill $(cat $PID_FILE)
    rm -f $PID_FILE
    echo "Stopped"
}

status() {
    if [ -f $PID_FILE ]; then
        echo "QKEY Server is running (PID: $(cat $PID_FILE))"
    else
        echo "QKEY Server is not running"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
