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
- `Adaptive Auto` 메뉴바 compaction
  - 노치 화면 기본 `Compact`
  - 외부 모니터 기본 `Respect`
  - 강제 정책 `Always Compact / Always Respect`
- AX(Accessibility) 기반 외부 메뉴바 아이콘 미러링
  - 외부 아이콘 스캔/동기화 (폴링 + 화면 이벤트 반영)
  - 노치 가용폭 기반 `externalVisibleItems` / `externalOverflowItems` 분리
  - 아이콘별 `Mirror only` / `Mirror + Hide` 모드
  - `Mirror + Hide` 성공 후 스캔에서 사라진 아이콘은 `Hidden Shelf`에서 계속 노출
  - `stale-hidden` 상태 배지 표시
- 노치 드롭 액션 허브 (Hover + Drop 즉시 실행)
  - 2.0 `Magnetic Chip Dock` 모션 (preheat/magnetFocus/dropCommit)
  - 이미지 -> PDF
  - PDF -> 이미지(페이지별 PNG)
  - ZIP 압축(생성 후 원본 휴지통 이동 + Undo)
  - ZIP 해제
  - 이미지 최적화
  - PDF 최적화(텍스트 보존)
  - 이미지 리사이즈(Long edge 2048)
  - Workbench로 모으기 (`~/Library/Application Support/MacMenubar/Workbench`)
  - 휴지통 이동 + 8초 Undo
- 노치 하단 Dynamic Island 스타일 패널
  - Hover 확장 애니메이션 (Apple subtle, Reduce Motion 대응)
  - 미디어 상태 + 재생 제어
  - 배터리 / CPU / 메모리 표시
  - 외부 아이콘 strip + Hidden Shelf 표시
- 라이트/다크/시스템 + Accent 테마

## Architecture (MVVM)

- `/Users/river/project/mac-menubar/MacMenubar/App.swift`
- `/Users/river/project/mac-menubar/MacMenubar/StatusBarController.swift`
- `/Users/river/project/mac-menubar/MacMenubar/NotchManager.swift`
- `/Users/river/project/mac-menubar/MacMenubar/ViewModel.swift`
- `/Users/river/project/mac-menubar/MacMenubar/NotchPanelView.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Views/ExternalIconStripView.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Views/NotchDropZoneView.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Views/DropTrackingView.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Models/ExternalMenuBarItem.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Models/NotchActionModels.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Models/DragSessionModels.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Accessibility/AXPermissionManager.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Accessibility/AXMenuBarScanner.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Accessibility/AXActionBridge.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/SystemMetricsService.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/MediaService.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/ExternalMenuBarService.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/FileActionService.swift`
- `/Users/river/project/mac-menubar/MacMenubar/Services/WorkbenchStore.swift`

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

- 외부 아이콘 숨김은 AX 제약으로 인해 best-effort입니다.
- OS 레벨의 노치 마스킹은 앱이 제어하지 않으며, 필요 시 BetterDisplay 같은 외부 도구를 사용해야 합니다.
- App Store 배포 호환성보다 개인/사내 도구 사용을 우선합니다.
