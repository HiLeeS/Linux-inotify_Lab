# 📦 파일 변경 감지(inotify)를 활용한 Spring Boot 자동 배포 구현
## 1. Overview

Windows host 환경에서 Spring Boot 애플리케이션을 JAR로 빌드한 뒤, Git Bash의 배포 스크립트를 통해 Ubuntu VM으로 파일을 전송하고, Ubuntu에서는 `inotify`를 사용해 파일 변경을 감지하여 애플리케이션을 자동 재실행하는 흐름을 구성했다.

단순 파일 복사에 그치지 않고, 새로운 JAR가 도착하면 기존 프로세스를 종료하고 최신 버전으로 서비스를 다시 실행하도록 자동화한 것이 핵심이다.

---

## 2. Why This Setup

개발은 Windows 환경에서 진행하지만, 실제 실행 환경은 Ubuntu VM이다.  
따라서 매번 직접 접속해서 파일을 복사하고 실행하는 과정을 반복하기보다, 다음 흐름이 자동으로 이어지도록 구성했다.

- Windows에서 JAR 빌드
- 배포 스크립트 실행
- Ubuntu VM으로 파일 전송
- 변경 감지 후 자동 재실행

이 구조를 통해 배포 과정을 단순화하고, 반복 작업을 줄일 수 있었다.

---

## 3. Architecture

```text
[Windows Host]
  └─ build JAR
  └─ deploy.sh 실행
        └─ scp 전송
             ↓
[Ubuntu VM]
  └─ ~/deploy/incoming/app.jar 저장
  └─ watch.sh 가 파일 변경 감지
  └─ current/app.jar 로 복사
  └─ run.sh 실행
        ├─ 기존 java 프로세스 종료
        └─ 새 app.jar 실행
```

## 4. Environment

### Host

- Windows
- Git Bash

### Guest

- Ubuntu VM

### Network

- NAT Network
- Port Forwarding

### Port Forwarding 설정

- Host IP: `0.0.0.0`
- Host Port: `2020`
- Guest IP: `10.0.2.20`
- Guest Port: `22`

Windows에서 Ubuntu VM SSH 접속:

```
ssh-p2020 ubuntu@127.0.0.1
```

---

## 5. Directory Structure

Ubuntu VM에서 배포 및 실행을 위한 디렉토리 구조:

```
~/deploy/
├── incoming/# 새 JAR 업로드 위치
├── current/# 실제 실행 JAR
├── logs/# 로그 파일
└── bin/# 실행/감시 스크립트
```

디렉토리 생성:

```
mkdir-p ~/deploy/incoming ~/deploy/current ~/deploy/logs ~/deploy/bin
```

---

## 6. Deployment Flow

```
1. Windows에서 Spring Boot JAR 빌드
2. deploy.sh 실행
3. scp로 Ubuntu VM에 파일 전송
4. ~/deploy/incoming/app.jar 저장
5. watch.sh가 변경 감지
6. current/app.jar로 복사
7. run.sh 실행
8. 기존 프로세스 종료
9. 새 JAR 실행
```

---

## 7. Scripts

### 7.1 📤 deploy.sh (Windows)

- JAR 존재 여부 확인
- scp로 Ubuntu VM에 업로드
- 파일명을 `app.jar`로 고정하여 watcher와 연동

```
REMOTE_USER=ubuntu
REMOTE_HOST=127.0.0.1
REMOTE_PORT=2020
REMOTE_PATH=/home/ubuntu/deploy/incoming/app.jar

LOCAL_JAR="/c/ce6/04.SpringBoot/step06_buildGradleTest/build/libs/step06_buildGradleTest-0.0.1-SNAPSHOT.jar"

scp-P"$REMOTE_PORT""$LOCAL_JAR""${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
```

---

### 7.2 👁️ watch.sh (Ubuntu)

- `inotifywait`로 파일 변경 감지
- 변경 시 `current/app.jar`로 복사
- `run.sh` 실행

```
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
```

핵심 포인트:

- 감시 대상 파일: `app.jar`
- 이벤트: `close_write`, `moved_to`
- 안정성을 위해 절대경로 사용 가능 (`/usr/bin/inotifywait`)

---

### 7.3 ⚙️ run.sh (Ubuntu)

- 기존 프로세스 종료
- 포트 점유 프로세스 정리
- 새 JAR 실행
- PID 및 로그 관리


```
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

```

---

## 8. How to Run

### 8.1 🔧 Ubuntu 패키지 설치

```
sudo apt-get update
sudo apt-get install inotify-tools lsof openssh-server-y
```

확인:

```
which inotifywait
sudo systemctl statusssh
```

---

### 8.2 🚀 watcher 실행

포그라운드 실행 (디버깅용):

```
bash ~/deploy/bin/watch.sh
```

백그라운드 실행:

```
nohup ~/deploy/bin/watch.sh > ~/deploy/logs/watch_stdout.log2>&1 &
```

---

### 8.3 📡 배포 실행 (Windows)

```
sh deploy.sh
```

---

## 9. Troubleshooting

### ❗ Issue 1. SCP 성공했지만 실행되지 않음

### 원인

- `watch.sh` 실행 당시 `inotifywait` 미설치
- watcher 프로세스 즉시 종료

### 확인

```
ps-ef |grep watch.sh
cat ~/deploy/logs/watch_stdout.log
```

### 해결

```
sudo apt-get install inotify-tools
bash ~/deploy/bin/watch.sh
```

---

### ❗ Issue 2. 파일 감지 안됨

### 원인

- 파일명이 `app.jar`가 아님

### 해결

```
scp ... /home/ubuntu/deploy/incoming/app.jar
```

---

### ❗ Issue 3. watcher 실행 중 아님

```
ps-ef |grep watch.sh
```

없으면 재실행:

```
bash ~/deploy/bin/watch.sh
```

---

## 10. Result

다음 자동 배포 흐름 구현 완료:

- Windows에서 JAR 빌드
- Git Bash에서 배포 실행
- Ubuntu VM으로 자동 전송
- `inotify` 기반 변경 감지
- 기존 프로세스 종료
- 새 버전 자동 실행

