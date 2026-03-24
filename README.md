# 📦 파일 변경 감지(inotify)를 활용한 Spring Boot 자동 배포 구현
<br/>

## 🧑‍💻 팀원 소개
| ![](https://avatars.githubusercontent.com/u/72748734?v=3) | ![](https://avatars.githubusercontent.com/u/204296918?v=3) |
|:---:|:---:|
| **이승준**<br>[@HiLeeS](https://github.com/HiLeeS) | **이준호**<br>[@Junhoss](https://github.com/Junhoss) |
<br/>

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

### 7.1 📤 [deploy.sh](script/deploy.sh) (Windows)

- JAR 존재 여부 확인
- scp로 Ubuntu VM에 업로드
- 파일명을 `app.jar`로 고정하여 watcher와 연동


---

### 7.2 👁️ [watch.sh](script/watch.sh) (Ubuntu)

- `inotifywait`로 파일 변경 감지
- 변경 시 `current/app.jar`로 복사
- `run.sh` 실행



핵심 포인트:

- 감시 대상 파일: `app.jar`
- 이벤트: `close_write`, `moved_to`
- 안정성을 위해 절대경로 사용 가능 (`/usr/bin/inotifywait`)

---

### 7.3 ⚙️ [run.sh](script/run.sh) (Ubuntu)

- 기존 프로세스 종료
- 포트 점유 프로세스 정리
- 새 JAR 실행
- PID 및 로그 관리



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

