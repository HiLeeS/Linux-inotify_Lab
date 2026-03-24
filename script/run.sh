#!/bin/bash

APP_DIR="$HOME/deploy"
JAR_PATH="$APP_DIR/current/app.jar"
PID_FILE="$APP_DIR/current/app.pid"
LOG_FILE="$APP_DIR/logs/app.log"
APP_PORT=8080

echo "[$(date)] run.sh 시작"

# 기존 PID 기준 종료
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "[$(date)] 기존 프로세스 종료 시도: $OLD_PID"
        kill "$OLD_PID"

        # 최대 10초 대기
        for i in {1..10}; do
            if ! ps -p "$OLD_PID" > /dev/null 2>&1; then
                echo "[$(date)] 기존 PID 종료 확인: $OLD_PID"
                break
            fi
            sleep 1
        done

        # 아직 살아있으면 강제 종료
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo "[$(date)] 기존 PID 강제 종료: $OLD_PID"
            kill -9 "$OLD_PID"
            sleep 1
        fi
    fi
    rm -f "$PID_FILE"
fi

# 포트 점유 프로세스 종료
PORT_PID=$(lsof -ti tcp:$APP_PORT)
if [ -n "$PORT_PID" ]; then
    echo "[$(date)] 포트 $APP_PORT 점유 프로세스 종료: $PORT_PID"
    kill $PORT_PID

    for i in {1..10}; do
        if ! lsof -ti tcp:$APP_PORT >/dev/null 2>&1; then
            echo "[$(date)] 포트 $APP_PORT 해제 확인"
            break
        fi
        sleep 1
    done

    if lsof -ti tcp:$APP_PORT >/dev/null 2>&1; then
        PORT_PID=$(lsof -ti tcp:$APP_PORT)
        echo "[$(date)] 포트 $APP_PORT 강제 종료: $PORT_PID"
        kill -9 $PORT_PID
        sleep 1
    fi
fi

# 최종 확인
if lsof -ti tcp:$APP_PORT >/dev/null 2>&1; then
    echo "[$(date)] 포트 $APP_PORT 가 아직 사용 중이라 실행 중단"
    exit 1
fi

if [ ! -f "$JAR_PATH" ]; then
    echo "[$(date)] jar 파일 없음: $JAR_PATH"
    exit 1
fi

echo "[$(date)] 새 app.jar 실행"
nohup java -jar "$JAR_PATH" --server.port=8080 > "$LOG_FILE" 2>&1 &

NEW_PID=$!
echo $NEW_PID > "$PID_FILE"

echo "[$(date)] 실행 완료, PID=$NEW_PID"
