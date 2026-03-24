#!/usr/bin/env bash
set -e

# ====== 수정할 부분 ======
REMOTE_USER=ubuntu
REMOTE_HOST=127.0.0.1
REMOTE_PORT=2020
REMOTE_PATH=/home/ubuntu/deploy/incoming/app.jar

LOCAL_JAR="/c/ce6/04.SpringBoot/step06_buildGradleTest/build/libs/step06_buildGradleTest-0.0.1-SNAPSHOT.jar"
# ========================

echo "[1] jar 존재 확인"
if [ ! -f "$LOCAL_JAR" ]; then
  echo "jar 파일이 없습니다: $LOCAL_JAR"
  echo "먼저 gradle build 또는 bootJar 실행 필요"
  exit 1
fi

echo "[2] Ubuntu로 전송 시작"
scp -P "$REMOTE_PORT" "$LOCAL_JAR" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"

echo "[3] 전송 완료"
echo "Ubuntu의 inotify가 감지해서 자동 재실행할 예정"
