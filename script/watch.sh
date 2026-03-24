#!/bin/bash

WATCH_DIR="$HOME/deploy/incoming"
TARGET_FILE="app.jar"
CURRENT_JAR="$HOME/deploy/current/app.jar"
RUN_SCRIPT="$HOME/deploy/bin/run.sh"
WATCH_LOG="$HOME/deploy/logs/watch.log"

COOLDOWN=10
LAST_RUN=0

echo "[$(date)] watch.sh 시작 - $WATCH_DIR 감시 중" | tee -a "$WATCH_LOG"

inotifywait -m -e close_write,create,moved_to "$WATCH_DIR" |
while read -r directory events filename; do
    if [ "$filename" != "$TARGET_FILE" ]; then
        continue
    fi

    CURRENT_TIME=$(date +%s)

    if (( CURRENT_TIME - LAST_RUN <= COOLDOWN )); then
        echo "[$(date)] 쿨다운 기간 중 - 재실행 생략" | tee -a "$WATCH_LOG"
        continue
    fi

    LAST_RUN=$CURRENT_TIME

    echo "[$(date)] $filename 변경 감지 ($events)" | tee -a "$WATCH_LOG"

    # 파일이 완전히 들어왔는지 잠깐 대기
    sleep 1

    # 실제 실행용 위치로 복사
    cp "$WATCH_DIR/$TARGET_FILE" "$CURRENT_JAR"

    echo "[$(date)] current/app.jar 갱신 완료" | tee -a "$WATCH_LOG"

    # 앱 재실행
    bash "$RUN_SCRIPT" | tee -a "$WATCH_LOG"
done
