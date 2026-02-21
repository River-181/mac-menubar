# MacMenubar

SwiftUI + AppKit 기반 macOS 메뉴바 전용 유틸리티 앱 예시입니다. MacBook 노치 영역을 고려해 메뉴바 아이콘 레이아웃을 재계산하고, 필요 시 Dynamic Island 스타일 패널을 표시합니다.

## 구조 (MVVM + AppKit bridge)

- `MacMenubar/App.swift`: 앱 진입점, 의존성 주입, 설정 화면
- `MacMenubar/StatusBarController.swift`: `NSStatusBar`, `NSStatusItem`, 메뉴/패널 제어
- `MacMenubar/NotchManager.swift`: 노치 안전영역 계산, 화면/활성앱 이벤트 구독
- `MacMenubar/ViewModel.swift`: 아이콘 우선순위 정책, spacing 계산, 로컬 JSON 할 일 저장
- `MacMenubar/NotchPanelView.swift`: hover 확장 패널(UI)

## 핵심 동작

1. `LSUIElement=true`로 Dock 아이콘을 숨김
2. 노치 안전영역 + 패딩을 중앙 금지 구역으로 계산
3. 가용 폭 부족 시 `Always Visible` > `Smart Hide` > `Hidden` 정책으로 표시/숨김 결정
4. 활성 앱/화면 조건에 따라 아이콘 간 spacing 동적 조정
5. hover 시 패널 확장 애니메이션 및 다크/라이트 + accent 테마 분기

## 빌드/실행

> 아래 명령은 Xcode 프로젝트(`MacMenubar.xcodeproj`)와 scheme(`MacMenubar`)가 준비된 상태를 기준으로 합니다.

```bash
xcodebuild -project MacMenubar.xcodeproj -scheme MacMenubar -configuration Debug -destination 'platform=macOS' build
```

Xcode에서 실행 시:
1. Signing 팀 선택
2. `Info.plist`의 `LSUIElement`가 `YES`인지 확인
3. Run 후 메뉴바 아이콘에서 패널 동작 확인

