# MacMenubar Spec v1.1 — 노치 파일 액션 허브 + 외부 아이콘 숨김 선반

## 1) 요약
- 목적: 노치로 가려지는 메뉴바 아이콘 문제를 외부 아이콘 미러링/숨김 + 노치 허브로 해결하고, 드래그앤드롭 파일 작업을 실제 용량 절감 중심으로 강화한다.
- 사용자 결정 고정
  1. 용량 전략: 최적화 포함, 문서 텍스트 보존.
  2. 숨김 아이콘 노출: Hidden Shelf 유지.
  3. 핵심 기능 확장: 파일 액션 4종 추가.
  4. ZIP 후 원본 정책: 기본 휴지통 이동(Undo 8초).

## 2) 진단
- 드롭 UX: 드래그 중 액션 가이던스 약함.
- ZIP: 아카이브 생성만 하고 원본 유지라 체감 용량 확보가 낮음.
- 외부 아이콘 숨김: 스캔 미검출 시 노치 UI에서도 사라질 수 있음.
- Dock 숨김: Info.plist의 LSUIElement 불일치 가능.

## 3) 제품 동작

### 3.1 노치 드래그앤드롭 UX
- 상태: `idle -> predrag -> hovering -> targeting(action) -> processing -> success|failure`
- 동작
  1. 상단 중앙 진입 시 predrag.
  2. 파일 드래그 감지 시 허브 확장.
  3. 추천 액션 강조.
  4. 칩 위 드롭 시 해당 액션 강제.
  5. 빈 영역 드롭 시 추천 액션 즉시 실행.
- 위치
  1. 노치 화면: 노치 중심 하단 앵커.
  2. 노치 없는 화면: visibleFrame.midX 상단 앵커.
- 토스트
  1. 성공/실패 메시지.
  2. 위험 액션 Undo 8초.

### 3.2 파일 액션 카탈로그
- 기존 5종
  1. imageToPDF
  2. pdfToImages
  3. compressZip (원본 휴지통 이동 포함)
  4. sendToWorkbench
  5. moveToTrash
- 신규 4종
  1. extractZip
  2. optimizeImages
  3. optimizePDFKeepText
  4. resizeImages

### 3.3 용량 절감 정책
- compressZip: ZIP 생성 후 원본 휴지통 이동 + Undo.
- optimizeImages: 확장자/알파 고려 최적화 후 원본 휴지통 이동 + Undo.
- optimizePDFKeepText: 텍스트 레이어 유지.
- resizeImages: Long edge 2048 preset 후 원본 휴지통 이동 + Undo.
- 파일명 충돌: `_1`, `_2` suffix.
- 출력 위치: 원본 폴더.

### 3.4 외부 아이콘 미러/숨김
- 모드: `Mirror only` / `Mirror + Hide`.
- Hidden Shelf
  1. Hide 성공 아이콘이 스캔에서 사라져도 Shelf 유지.
  2. Shelf 클릭 시 AXPress 또는 마지막 frame fallback 클릭.
  3. 장시간 미복구 시 `stale-hidden` 배지.
  4. Mirror only 전환 시 Shelf에서 제거.
- UI
  1. External Overflow에 Visible/HiddenShelf/Downgraded 통계.
  2. 노치 패널 strip에 Hidden Shelf 포함.

### 3.5 애니메이션/디자인
- 모션 토큰
  1. 허브 확장: `interactiveSpring(response:0.30,dampingFraction:0.82,blendDuration:0.10)`
  2. 칩 강조: `easeOut(0.14)`
  3. 토스트: move+opacity
  4. 드롭 타깃 glow: 120ms
- 접근성: Reduce Motion 시 spring 제거.
- 색상: 고채도 블루/과포화 톤 제거, 중성 재질 중심.

## 4) Public API / 타입
- `NotchActionKind`: `extractZip`, `optimizeImages`, `optimizePDFKeepText`, `resizeImages` 추가.
- `NotchDropState`: `predrag`, `targeting(NotchActionKind)` 추가.
- `UndoToken`: `operationKind`, `replacements`, `expiresAt` 포함.
- `ActionExecutionResult`: `spaceDeltaBytes`, `warnings` 포함.
- `DropClassification`: `recommendedAction`, `secondaryActions` 포함.
- `DragSessionContext`, `StorageDelta` 추가.
- `ExternalMenuBarProviding`: `hiddenShelfPublisher`, `revealHiddenItem(_:)` 추가.

## 5) 구현 파일
- 신규
  - `/Users/river/project/mac-menubar/MacMenubar/Models/DragSessionModels.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/Views/DropTrackingView.swift`
- 수정
  - `/Users/river/project/mac-menubar/MacMenubar/Views/NotchDropZoneView.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/ViewModel.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/Services/FileActionService.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/Services/ExternalMenuBarService.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/Views/ExternalIconStripView.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/StatusBarController.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/NotchPanelView.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/App.swift`
  - `/Users/river/project/mac-menubar/MacMenubar/Info.plist`
  - `/Users/river/project/mac-menubar/project.yml`
  - `/Users/river/project/mac-menubar/README.md`

## 6) 테스트
- 단위
  1. ZIP 후 원본 휴지통 이동 + Undo 복구.
  2. extractZip 정상 해제.
  3. optimizeImages/resizeImages 용량 절감 검증.
  4. optimizePDFKeepText 후 텍스트 추출 가능.
  5. 파일명 충돌 suffix.
- 통합
  1. 드래그 상태 전이.
  2. AX denied/granted 전환.
  3. 노치/외부 모니터 앵커 전환.
  4. Reduce Motion 분기.

## 7) 수용 기준
1. 드래그 중 가능한 액션이 허브에서 명확히 노출된다.
2. ZIP 실행 후 기본적으로 원본이 휴지통으로 이동한다.
3. Mirror+Hide 성공 아이콘은 시스템 바에서 사라져도 Hidden Shelf에서 접근 가능하다.
4. 애니메이션은 과하지 않고 상태 전환이 명확하다.
5. 텍스트형 메뉴바 표시는 제거된다.
6. LSUIElement=true로 Dock 아이콘이 보이지 않는다.
7. `xcodebuild build` 및 `xcodebuild test` 성공.

## 8) 빌드/검증
```bash
cd /Users/river/project/mac-menubar
xcodegen generate
xcodebuild -project MacMenubar.xcodeproj -scheme MacMenubar -configuration Debug -destination 'platform=macOS' build
xcodebuild -project MacMenubar.xcodeproj -scheme MacMenubar -destination 'platform=macOS' test
```
