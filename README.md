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

### ❗ 재배포 시 포트 충돌로 실행 실패


- Ubuntu에서 새 JAR 파일은 정상적으로 전송되었지만 애플리케이션이 다시 실행되지 않음
- `app.log` 확인 결과 다음 에러 발생
```text
Web server failed to start. Port 8080 was already in use.
```
### 문제 원인
- 기존 Java 프로세스가 완전히 종료되기 전에 새 JAR를 바로 실행하면서 8080 포트 충돌이 발생함
- `kill` 명령 직후에도 운영체제가 즉시 포트를 해제하지 않아, 짧은 시간 동안 기존 프로세스가 포트를 계속 점유하고 있었음
- 기존 `run.sh`는 종료 후 짧은 `sleep`만 두고 바로 실행해, 종료 완료 여부와 포트 해제 여부를 확인하지 못했음

### 해결
- 기존 PID를 기준으로 먼저 프로세스를 종료하고, 실제 종료 여부를 반복 확인하도록 수정함
- 종료되지 않은 경우 강제 종료하도록 보완함
- `lsof`로 8080 포트 점유 여부를 확인한 뒤, 포트가 완전히 해제된 경우에만 새 JAR를 실행하도록 변경함

### 배운 점
- 자동 배포에서는 단순히 `kill` 후 바로 실행하는 방식만으로는 충분하지 않음
- 프로세스 종료 완료와 포트 해제 완료를 확인하는 안정적인 재시작 로직이 필요함
- 재배포 자동화에서는 실행 속도보다 안정적인 순서 보장이 더 중요하다는 점을 확인함
---

## 10. Result

다음 자동 배포 흐름 구현 완료:

- Windows에서 JAR 빌드
- Git Bash에서 배포 실행
- Ubuntu VM으로 자동 전송
- `inotify` 기반 변경 감지
- 기존 프로세스 종료
- 새 버전 자동 실행

