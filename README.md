# MacMenubar

Swift + SwiftUI + AppKit (`NSStatusBar`, `NSStatusItem`) 기반 macOS 메뉴바 전용 유틸리티 앱입니다.

## Features

- `LSUIElement=true` 메뉴바 전용 앱 (Dock 아이콘 숨김)
- 커스텀 앱 아이콘(`AppIcon`) + 브랜드 로고(`BrandLogo`) 포함
- 노치 영역 인식 후 좌/우 메뉴바 가용폭 계산
- 동적 spacing + 우선순위 표시 정책
  - `Always Visible`
  - `Smart Hide`
  - `Hidden`
- AX(Accessibility) 기반 외부 메뉴바 아이콘 미러링
  - 외부 아이콘 스캔/동기화 (폴링 + 화면 이벤트 반영)
  - 노치 가용폭 기반 `externalVisibleItems` / `externalOverflowItems` 분리
  - 외부 오버플로우 메뉴에서 아이콘 액션 전달 (`AXPress` + 좌표 클릭 fallback)
  - 아이콘별 `Mirror only` / `Mirror + Hide` 모드
  - `Mirror + Hide` 실패 시 자동 강등 + 원인 표시
- 노치 드롭 액션 허브 (Hover + Drop 즉시 실행)
  - 이미지 -> PDF
  - PDF -> 이미지(페이지별 PNG)
  - ZIP 압축(`ditto`)
  - Workbench로 모으기 (`~/Library/Application Support/MacMenubar/Workbench`)
  - 휴지통 이동 + 8초 Undo
- 노치 하단 Dynamic Island 스타일 패널
  - Hover 확장 애니메이션
  - 미디어 상태 + 재생 제어
  - 배터리 / CPU / 메모리 표시
  - 외부 아이콘 strip 표시
- 라이트/다크/시스템 + Accent 테마

## Architecture (MVVM)

- `/Users/river/project/mac-menubar/MacMenubar/App.swift`
- `/Users/river/project/mac-menubar/MacMenubar/StatusBarController.swift`
- `/Users/river/project/mac-menubar/MacMenubar/NotchManager.swift`
- `/Users/river/project/mac-menubar/MacMenubar/ViewModel.swift`
- `/Users/river/project/mac-menubar/MacMenubar/NotchPanelView.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Views/ExternalIconStripView.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Models/ExternalMenuBarItem.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Accessibility/AXPermissionManager.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Accessibility/AXMenuBarScanner.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Accessibility/AXActionBridge.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/SystemMetricsService.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/MediaService.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/ExternalMenuBarService.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/FileActionService.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/WorkbenchStore.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Views/NotchDropZoneView.swift`

## Build

1. XcodeGen 설치

```bash
brew install xcodegen
```

2. Xcode 프로젝트 생성

```bash
cd /Users/river/project/mac-menubar
xcodegen generate
```

3. 빌드

```bash
xcodebuild -project MacMenubar.xcodeproj -scheme MacMenubar -configuration Debug -destination 'platform=macOS' build
```

4. 테스트

```bash
xcodebuild -project MacMenubar.xcodeproj -scheme MacMenubar -destination 'platform=macOS' test
```

## Notes

- 캘린더/태스크 저장 기능은 포함하지 않습니다.
- 외부 아이콘 숨김은 Public API 제약으로 인해 best-effort입니다.
- App Store 배포 호환성보다 개인/사내 도구 사용을 우선합니다.
