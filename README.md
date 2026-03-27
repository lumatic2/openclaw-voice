# ptt-voice-app

Android 우선 PTT Voice Assistant MVP.

## 기능
- 토글 녹음 버튼(탭1 녹음 시작, 탭2 녹음 종료)
- STT 중간 결과 실시간 표시
- OpenClaw Gateway 호출(엔드포인트 순차 탐색)
- LLM 응답 텍스트 + 자동 TTS 재생
- Riverpod 기반 상태 머신

## 환경 변수 (필수)
시크릿은 코드에 넣지 말고 `--dart-define`로 전달합니다.

```bash
flutter run \
  --dart-define=OPENCLAW_BASE_URL=https://YOUR_TAILSCALE_HOST \
  --dart-define=OPENCLAW_BEARER_TOKEN=YOUR_TOKEN
```

## 권한
- Android `RECORD_AUDIO`, `INTERNET`

## 상태 머신
- Idle → Recording → Thinking → Speaking → Idle
- 에러 시 `Error` 상태 배너 표시

## 참고
현재 환경에 Flutter SDK가 없어 `flutter create`, `flutter pub get`, `flutter run` 검증은 수행하지 못했습니다.
SDK 설치 후 아래 순서로 플랫폼 파일을 보강하세요:

```bash
cd ~/projects/ptt-voice-app
flutter create .
flutter pub get
flutter run
```
