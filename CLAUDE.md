# ptt-voice-app

> Flutter + Wear OS + Express 브릿지 기반 Jamie/OpenClaw 음성 비서 앱.

## 기술 스택

- Flutter/Dart (`pubspec.yaml`, SDK `>=3.3.0 <4.0.0`)
- Flutter 주요 패키지: `flutter_riverpod`, `speech_to_text`, `flutter_tts`, `http`, `permission_handler`, `shared_preferences`
- Wear companion Flutter 패키지: `flutter_wear_os_connectivity`
- Node.js 브릿지 (`bridge/package.json`): Express (`express`)
- Android/Wear OS 네이티브 모듈 (`watch/`, `android/`)

## 프로젝트 구조

- `lib/`: Flutter 폰 앱 소스
- `assets/`: 폰트/아이콘 등 에셋
- `bridge/`: Node.js Express 브릿지 서버 (`server.js`)
- `watch/`: Wear OS 네이티브 앱 모듈
- `watch_companion/`: 보조 Flutter 앱
- `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`: 플랫폼 런너
- `test/`: Flutter 테스트
- `pubspec.yaml`: 메인 앱 의존성/에셋 정의
- `README.md`: 빌드/실행/네트워크 구성 가이드

## 개발 명령어

```bash
# Flutter app
flutter pub get
flutter run
flutter build apk --debug

# Watch app
cd watch
./gradlew assembleDebug

# Bridge
cd bridge
npm install
npm start
```

## 작업 방식

- 새 기능 -> 항상 계획 먼저, 구현 나중
- 50줄+ 코드 작성 -> Codex 위임
- 복잡 리서치 -> Gemini 위임
- 브릿지 토큰/URL 변경 시 `bridge`, `phone`, `watch` 3개 경로 설정을 동시에 검증