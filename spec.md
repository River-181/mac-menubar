# NotchDock (Working Title) — Spec

## Output Rubric

이 문서가 “잘 된 스펙”이려면 아래를 만족해야 한다.

* **제품 목표가 한 문장으로 고정**되어 있고, 무엇을 **하지 않는지(Non-goals)**가 명확하다.
* “섹시/유려/디자이너가 좋아할”을 **구현 가능한 애니메이션/인터랙션 규격**으로 번역한다.
* **노치와 연결되는 오버레이 UI**의 레이아웃/상태/전환/입력(마우스·키보드) 규칙이 구체적이다.
* 메뉴바 아이콘의 **정리/노출/접근**이 사용자 관점에서 일관되고, 실패 케이스/제약이 기록돼 있다.
* v0(프로토타입)에서 v1(유료급 품질)까지의 **단계별 범위**가 분리돼 있다.

---

## 1. One-liner

노치 주변을 “만지고 싶은” 상단 오버레이로 바꿔서, **메뉴바 아이콘을 아름답게 정렬·수납·노출**하고 메뉴바를 심플하게 만든다.

## 2. Goals

* 노치와 시각적으로 **연결되는 Dynamic Island급 모션**으로 상단 경험을 재정의
* 메뉴바에 난립한 아이콘을 **정돈된 ‘아이콘 도크’로 재구성**(빠른 접근 + 미학)
* 사용자가 “계속 켜두고 싶은” **감정적 만족(Delight)** 제공

## 3. Non-goals

* 태스크/할 일/캘린더/일정/노트 기능
* 시스템 모니터링(온도/CPU/RAM) 위젯 경쟁
* 타 앱 메뉴바 아이콘을 “완전히” 숨기는 것을 OS 레벨로 보장하는 것(제약 명시)

---

## 4. Product Pillars (디자이너가 사랑할 기준)

1. **Continuity**: 노치와 UI가 끊기지 않는다(형상·그림자·블러·모션의 연속성)
2. **Tactility**: 마우스가 닿는 순간 “물성”이 느껴진다(탄성/저항/미세 반응)
3. **Restraint**: 과장하지 않는다. 정보는 최소, 움직임은 정확
4. **Legibility**: 어떤 배경에서도 읽히고, 산만하지 않다
5. **Predictability**: 한 번 배우면 손이 간다(제스처/단축키/상태 규칙)

---

## 5. UX Overview

### 5.1 기본 구성

* **Overlay (NotchDock)**: 상단 중앙, 노치 아래에 붙는 캡슐형 UI
* **Tray (Icon Strip)**: 좌/우 아이콘을 “정렬된 스트립”으로 보여주는 영역
* **Peek / Expand**: hover/gesture로 순간 확장되는 2단계 인터랙션

### 5.2 사용자가 얻는 핵심 가치

* 메뉴바가 복잡해질수록 NotchDock이 **더 아름답게 정리**해준다
* 아이콘은 “숨김”이 아니라 **수납 + 필요 시 노출**

---

## 6. Visual Language

### 6.1 Shape

* 기본 형태: **Capsule**(노치 하단과 매끈하게 이어지는 곡률)
* Corner radius: 높이의 0.5 (완전 캡슐)
* 노치와의 간격: 6–10pt(기기별 자동 보정)

### 6.2 Material

* 배경: macOS 소재 기반(ultraThinMaterial 유사) + 미세한 톤 보정
* 외곽선: 1px hairline(환경에 따라 alpha 자동 조절)
* 그림자: 2-layer(ambient + contact)로 깊이감

### 6.3 Color

* 기본: neutral(배경에 녹는 회색 계열)
* Accent: 사용자가 지정한 1색(강조는 10–20%만 사용)

---

## 7. Interaction Model

### 7.1 States (상태 머신)

* **Idle**: 최소 폭(노치와 연결된 작은 캡슐, 아이콘 0–3개만)
* **Peek**: 마우스가 근접하면 폭이 늘며 대표 아이콘 스트립 표시
* **Expand**: 아이콘 전체/그룹/검색/정렬 옵션 노출
* **Grab**: 드래그로 아이콘 재배치/핀/그룹링
* **Focus**: 특정 아이콘 hover 시 프리뷰/서브액션
* **Workspace**: 노치에서 시작해 **전체 폭(또는 화면 큰 비중)**으로 확장되는 ‘작업 데스크’ 모드

상태 전이(예시)

* Idle → Peek: pointer가 상단 16px zone 진입
* Peek → Expand: 캡슐 클릭
* Peek/Expand → Workspace: **2단 확장(Pressure)** 트리거
* Expand → Grab: 아이콘 long-press 250ms
* Expand/Workspace → Idle: pointer 이탈 + 600ms grace (Workspace는 명시적 닫기 포함)

### 7.2 Motion Spec (핵심)

* 기본 easing: **spring** (response 0.28–0.38, damping 0.78–0.88)
* micro motion:

  * hover highlight: 120ms
  * width expansion: 220–320ms
  * content fade/slide: 160–240ms
* “애플 변태” 포인트:

  * pointer가 캡슐에 닿기 직전 **pre-hover swell**(1.00→1.02)
  * 확장 시 내부 아이콘이 **지연 등장(stagger 20–35ms)**
  * 축소 시 텍스트는 먼저 사라지고 형태가 늦게 줄어든다(2-phase)

### 7.3 Pressure 느낌의 2단 확장 (추가)

다이나믹 아일랜드처럼 ‘한 단계 더’ 들어가는 감각을 제공한다.

* **Stage 1**: Peek (가벼운 확장)
* **Stage 2**: Deep Expand 또는 Workspace (깊은 확장)

트리거(우선순위)

* 트랙패드 Force Click 지원 시: Force Click → Stage 2
* Force Click 미지원 시: Hover Dwell 300ms 또는 더블클릭/⌥Space → Stage 2
* 드래그 중에는: 노치 위에 250ms 머무르면 Stage 2 (Drop Targets 확대)

피드백

* Stage 2 진입 순간 미세한 ‘저항’ 모션(0.98→1.00) + 그림자 변화
* 사운드/햅틱은 옵션(기본 Off)

### 7.4 Hit Testing

* 캡슐의 실제 hit-area는 시각 영역보다 6–10pt 크게
* 아이콘은 28–32pt hit target 유지

---

## 8. Menu Bar Icon Experience

### 8.1 아이콘 “수납” 모델

* **Pinned**: 항상 보이는 핵심 아이콘(예: 배터리/와이파이 등)
* **Shelf**: 평소에는 숨김, Peek/Expand에서 보임
* **Overflow**: 공간 부족 시 자동으로 Shelf로 이동

### 8.2 정렬/그룹

* 기본: 좌→우 사용 빈도(최근 클릭 시간 + pinned 가중)
* 그룹: 사용자 정의(예: Network, Audio, Dev)
* 그룹은 캡슐 내부에서 **폴더처럼 수축/확장**

### 8.3 “심플한 메뉴바”가 되는 조건

* 메뉴바에는 최소만 남기고(예: 시스템 기본 + NotchDock),
* 나머지 접근은 NotchDock에서 한다.

### 8.4 현실적 제약

* 타 앱의 메뉴바 아이콘을 OS가 공식적으로 제어하는 범위는 제한적이다.
* 따라서 v0/v1은 “정리된 대체 도크 UI”에 집중하고,
* 가능한 경우에만(권한/접근성) 숨김/정렬을 옵션으로 제공한다. [UNCERTAIN: 구현 범위는 macOS 버전/권한에 따라 달라짐]

---

## 9. Core Features

### 9.1 반드시 (MVP)

* 상단 중앙 **오버레이 캡슐**(노치 연동 위치 계산)
* Idle/Peek/Expand 상태 + 스프링 모션
* 아이콘 스트립: Pinned/Shelf/Overflow
* 아이콘 드래그 재정렬 + 그룹링(Grab)
* 단축키:

  * Toggle Expand: ⌥Space (기본)
  * Next/Prev group: ⌥←/→
  * Search focus: ⌥/

#### 9.2 Work Hub (Drag & Drop) — 반드시 포함

노치 상단을 **드래그 앤 드롭 Work Hub**로 사용한다. 사용자는 파일을 노치 위/아래로 끌어다 놓아 즉시 변환·정리 작업을 실행한다.

#### UX

* **Hover Expand**: 포인터가 상단 중앙(노치 영역)으로 접근하면 캡슐이 확장되며 Drop Targets가 나타난다.
* **Drag Expand**: 드래그가 시작되면(드래그 세션 감지) 자동으로 Expand 상태로 전환, 타겟 영역이 더 커진다.
* **Drop → Instant Action**: 드롭 즉시 작업 실행.
* **Result Toast**: 완료 시 1–2줄 토스트(결과 파일 개수/저장 위치/용량 변화) 표시.
* **Undo 8s**: 위험 작업(이동/삭제/압축 후 원본 처리)은 8초간 Undo 가능. Undo는 토스트 내 버튼 + ⌘Z(가능하면)로 제공.

#### Supported Actions (9)

1. 이미지 → PDF
2. PDF → 이미지
3. ZIP 압축 (기본: 원본 휴지통 이동)
4. ZIP 해제
5. 이미지 최적화
6. PDF 최적화(텍스트 보존)
7. 이미지 리사이즈(Long edge 2048)
8. Workbench로 모으기(임시 작업 폴더로 집결)
9. 휴지통 이동

#### Output / Storage Rules

* 기본 출력 위치: `~/Downloads/NotchDock/` 하위에 `YYYY-MM-DD/` 폴더 생성
* Workbench: `~/Downloads/NotchDock/Workbench/` (사용자 변경 가능)
* 파일명 규칙: `원본이름__action__v1.ext` (충돌 시 `-2`, `-3`)

#### Safety Rules

* “원본 휴지통 이동”은 기본 ON이지만, 첫 실행 시 명시적 안내(1회) 제공.
* 휴지통 이동/원본 처리 작업은 반드시 Undo 가능하도록 설계.
* 변환 실패 시: 토스트에 실패 사유(짧게) + 로그 보기.

#### Interaction Spec

* Drop Target는 3열 또는 2열(화면 폭 따라)로 배치
* 타겟 hover 시 미세 확대(1.00→1.03) + 하이라이트 링
* Drag 중에는 hit-area를 크게(각 타겟 최소 44pt)

---

### 9.3 Workspace (Workbench Desktop) — ‘노치를 작업 데스크로’

사용자가 평소 Desktop/Downloads를 임시 작업 데스크로 쓰는 행동을 대체한다. NotchDock의 Workspace는 **노치에서 시작해 큰 화면으로 확장되는 카드 기반 작업면**이다.

#### 핵심 컨셉

* **Card Pile + Magnet**: 카드 뭉치가 흩어져 있지만 ‘자석’처럼 프로젝트 단위로 자연스럽게 붙는다.
* **Project Cluster**: 사용자는 주제/프로젝트(예: “인지심리학/의사결정”)를 하나의 클러스터로 만들고 자료를 모은다.
* **Mixed Media**: 이미지(그래프), PDF(논문), 링크, 짧은 메모가 한 화면에 공존.

#### Workspace 진입

* Stage 2(Pressure) 트리거로 Workspace로 확장
* 단축키: ⌥⏎ (기본)
* 드래그 중 Stage 2에서 ‘Workbench로 모으기’ 타겟을 길게 hover하면 자동 진입

#### 레이아웃

* 배경: 미세한 그레인 + 소재 블러(과하지 않게)
* 카드: 2가지 밀도 모드

  * **Scatter**(기본): 자연스럽게 흩어진 카드 + 가벼운 overlap
  * **Grid**(옵션): 정렬된 그리드(정리 모드)

#### 카드 타입

* **File Card**: 이미지/PDF/기타 파일(아이콘 + 미리보기)
* **Link Card**: 파비콘 + 제목 + 도메인
* **Note Card**: 1–6줄 텍스트(빠른 메모)

#### 카드 인터랙션

* Hover: 살짝 떠오름(1.00→1.02) + shadow 강화 + 핵심 메타(파일명/페이지수/해상도) 표시
* Peek: 카드 위에서 300ms dwell 시 **Quick Look 스타일 프리뷰**(이미지 확대, PDF 1페이지)
* Drag: 카드 이동/정렬, 클러스터에 가까워지면 자석 스냅
* Pin: 즐겨찾기(클러스터 상단에 고정)

#### 클러스터(프로젝트) 규칙

* 클러스터는 ‘라벨 캡슐’로 표시(이름 + 색)
* 자석 반경: 80–140pt(확대/축소 가능)
* 스냅 시 애니: 살짝 끌려가며 정착(0.22–0.32s spring)

#### 데이터/저장

* Workspace는 **파일을 이동시키지 않는다(기본)**.
* 카드 구성은 메타데이터로 저장(경로/북마크/좌표/클러스터)
* 파일 접근은 보안북마크를 사용 [UNCERTAIN: 샌드박스/권한 구성에 따라]

#### 범위 제한(초기)

* v0: Workbench(임시 폴더) 기반 카드만 지원
* v1: 임의 위치 파일/링크/메모 혼합 지원

### 9.4 있으면 강력 (v1)

* 아이콘 검색(타이핑 즉시 필터)
* “최근 사용” 자동 정렬
* 테마 프리셋(Glass / Matte / Dark Ink)
* 애니메이션 강도 슬라이더(Delight ↔ Minimal)
* Work Hub 커스텀 액션(순서 변경/숨김)

### 9.4 나중에 (v2)

* 앱별 프로필(업무/게임/발표 모드)
* 단축키/제스처 커스터마이징

## 9.5 Workspace Physics & Motion (SDD 핵심)

### 9.5.1 Magnet Physics Model

Workspace의 ‘자석 느낌’은 파라미터화된 물리 규칙으로 정의한다.

* **Magnet Radius (R)**: 80–140pt (기본 110pt)
* **Snap Threshold (S)**: R의 0.55 (기본 60pt)
* **Attraction Curve**: 거리 d에 대해 힘은 부드럽게 증가

  * d > R: 0
  * S < d ≤ R: (1 - (d-S)/(R-S))^2 로 가속
  * d ≤ S: 스냅 후보(결정 로직으로 전환)
* **Snap Resolve**: 스냅 발생 시 카드 중심이 클러스터 앵커로 0.22–0.32s spring

### 9.5.2 Inertia / Drag Feel

* Drag 시작: 카드가 0.98→1.00으로 ‘저항’ 후 따라온다(Pressure 감각)
* Drag 중: 포인터 속도에 따라 1–3프레임 지연(미세한 관성)
* Drop 후: 0.18–0.26s settle + shadow 복귀

### 9.5.3 Collision & Overlap Rules

* 기본 모드(Scatter): **겹침 허용**(최대 18%)
* 충돌 방지: 카드 중심 간 최소 거리 46pt 유지(겹침 허용 범위 내)
* 정리 제스처(Shake/Arrange): 겹침 0%로 정렬(부드러운 재배치)
* Z-index:

  * Hover 카드가 최상단
  * Drag 카드가 최상단
  * 같은 클러스터 내에서는 최근 상호작용 순

### 9.5.4 Cluster Layout

* 클러스터는 ‘라벨 캡슐’ + 카드의 약한 오비트 형태
* 앵커(Anchor): 클러스터 라벨 중심
* 카드 배치: 앵커 주변 2–3개의 링(거리 72/112/152pt)
* 새 카드 드롭: 가장 빈 공간이 큰 링 위치로 자동 배치

---

## 9.6 Workspace Transitions (Notch → Full)

### 9.6.1 Expansion Stages

Workspace 전환은 3단계로 나눈다.

1. **Notch Capsule**: 기본 캡슐
2. **Wide Capsule**: 화면 중앙 가로 확장(0.22–0.32s)
3. **Workspace Canvas**: 캔버스가 아래로 펼쳐짐(0.28–0.38s)

### 9.6.2 Timing & Easing

* Stage 1→2: spring response 0.30, damping 0.84
* Stage 2→3: spring response 0.34, damping 0.82
* 내용 전환은 형태보다 40–80ms 늦게 시작(형태 우선)

### 9.6.3 Visual Continuity

* 노치와의 연결이 끊기지 않도록:

  * 캡슐 상단 라인은 고정
  * 확장 시 라운드 곡률은 유지, 두께만 변화
  * 블러/그림자 레이어는 단계적으로 강화

### 9.6.4 Exit

* 닫기 제스처:

  * Esc: Workspace → Expand
  * Esc 한 번 더: Expand → Idle
  * 캔버스 빈 공간 클릭(옵션): Workspace → Expand
* Exit 애니메이션은 Enter의 역순, 텍스트/프리뷰가 먼저 사라진다.

---

## 9.7 Idle Micro-Interactions (가만히 두기 싫은 느낌)

### 9.7.1 Breathing

* Idle에서 3.2–4.8s 주기로 미세한 호흡(스케일 1.000↔1.008)
* Reduce Motion 설정 시 비활성

### 9.7.2 Parallax

* 포인터가 캡슐 근처를 지나가면 하이라이트가 따라오는 미세 파라락스
* 최대 이동량: 6–10pt

### 9.7.3 Gloss / Light Sweep

* 12–18s 간격으로 얕은 라이트 스윕(아주 약하게)
* 사용자가 움직이면 즉시 멈추고 인터랙션에 집중

---

## 9.8 Gesture Set (Minimal but Addictive)

* Hover: Peek
* Click: Expand
* Pressure Stage 2: Deep Expand / Workspace
* Drag files: Work Hub
* Drag cards: Workspace 편집
* ⌥Space: 토글 Expand
* ⌥⏎: 토글 Workspace
* Esc: 단계적 닫기

---

## 10. Layout & Geometry

* 기준 스크린: NSScreen.main
* 노치 영역 추정: safeAreaInsets 기반 + 추가 패딩
* 캡슐 위치:

  * x: (screenWidth - capsuleWidth)/2
  * y: screenMaxY - capsuleHeight - topMargin(6–10)
* Expand 시 최대 폭: screenWidth * 0.72 (상한)
* 아이콘 스트립 간격: 8–10pt(밀도에 따라 6까지 축소)

---

## 11. Accessibility

* 키보드만으로 Expand 탐색 가능
* VoiceOver 라벨 제공(아이콘 이름/그룹)
* 모션 감소 설정 존중(“Reduce Motion” 시 fade 중심)

---

## 12. Performance Budgets

* Idle 상태 CPU wake 최소화
* 애니메이션 프레임 드랍 방지(복잡한 blur/gradient 남용 금지)
* 60fps 목표(가능하면 120Hz 대응)

---

## 13. Implementation Notes (High-level)

* UI 레이어: borderless NSWindow/NSPanel + SwiftUI HostingView
* 상태 머신: enum + reducer(단순)
* 입력: tracking area + global hotkey
* 아이콘 데이터:

  * v0: 사용자 수동 등록(아이콘 set)
  * v1: 시스템/앱 아이콘 소스 탐색(권한 필요한 경우 안내)

---

## 14. Milestones

### v0 (Delight Prototype)

* Overlay 캡슐 + Idle/Peek/Expand
* 아이콘 스트립(더미 데이터) + 드래그 재정렬
* 기본 단축키

### v0.1 (Real Icons)

* 최소한의 실제 아이콘 소스 연결
* 설정 UI

### v1 (Daily Driver)

* 안정화 + 검색 + 그룹 + 테마
* 권한 기반 옵션(가능한 범위의 아이콘 숨김/정리)

## 14.1 Execution Phases (A -> E, 반복 루프)

* **Phase A**: 필수 패키지/인프라 준비 (GitHub 패키지, 핫키/입력 베이스)
* **Phase B**: 상단 트리거/드래그 안정화 + idle 전력 최적화
* **Phase C**: 아이콘 도크 UX 폴리시 (Pinned/Shelf/Overflow, 그룹 순환/필터)
* **Phase D**: Work Hub 액션 엔진 완성도(실행/Undo/오류 복구/메시지)
* **Phase E**: 테스트/문서/수동 검증 정리 후 A로 되돌아가 반복 개선

---

## 15. Open Questions

* [UNCERTAIN] macOS 버전별 safeAreaInsets/노치 계산 정확도
* [UNCERTAIN] 타 앱 메뉴바 아이콘 제어의 실현 가능 범위(권한/접근성/정책)
* 아이콘 소스 수집 방식(사용자 지정 vs 자동 탐지)

---

## 16. Deep Work vNext Baseline (2026-02-23)

### 16.1 Implemented Interfaces

* `PointerSamplingMode` (`idle`, `armed`, `drag`)
* `TriggerState` (`outside`, `entering`, `inside`, `exiting`)
* `DragTelemetry` (`point`, `velocity`, `timestamp`)
* `OverlayPerfSnapshot` (`idleCPU`, `triggerFlaps`, `avgDragFrameMs`, `stateTransitions`)
* `NotchGeometryCalculating` 확장:
  * `capsuleFrame(screen:visualState:policy:compactOverride:)`
  * `hitMaskRect(for:panelFrame:)`

### 16.2 Runtime Policy (A/B/C 반영)

* 샘플링 주기:
  * `idle`: 180ms
  * `armed`: 60ms
  * `drag`: 30ms
* 트리거 히스테리시스:
  * enter delay `50ms`
  * exit delay `120ms`
* 아이콘 노출 기본:
  * Running Apps 기본값 `OFF` 유지
* 레이아웃 정책:
  * 캡슐 hit mask는 visual bounds + 8pt
  * 아이콘 스트립은 중앙 정렬 + overflow 시 수평 스크롤
* 입력 패스스루 정책:
  * 패널 기본은 mouse passthrough(ignoresMouseEvents=true)로 시작
  * 캡슐 내부 또는 top trigger 내부일 때만 interaction enable
  * idle 조기 종료 경로에서도 강제로 passthrough 복귀
* 드래그 타깃 정책:
  * 드래그 중 `targetedDropAction`을 계산해 칩 하이라이트에 반영
  * 세션 종료 시 타깃 상태를 즉시 정리

### 16.3 Performance Counters

* `triggerFlaps`: 안정 상태(inside/outside)가 0.8s 이내 반복 전환되면 증가
* `stateTransitions`: 오버레이 시각 상태 변경 횟수 카운트
* `avgDragFrameMs`: 드래그 샘플 간 평균 간격(ms)
* `OSLog signpost`: 샘플링 모드 변경 이벤트 기록

### 16.4 Verification Notes

* 목표 KPI:
  * Idle CPU `<= 1.5%`
  * 드래그 체감 60fps 근접
  * 트리거 오탐 50회 중 0~1회
* 테스트 게이트:
  * `OverlayStateMachineTests`: 히스테리시스 + 중복 전이 방지
  * `NotchGeometryCalculatorTests`: hit mask/spacing 정합성

### 16.5 Manual Capture Procedure (Finder 30회)

1. 상태바 메뉴에서 `Reset Perf Counters` 실행.
2. Finder 파일 드래그를 상단 트리거 구간으로 30회 반복.
3. 상태바 메뉴에서 `Copy Perf Snapshot` 실행.
4. 캡처 문자열(`idleCPU / flaps / drag ms / transitions`)을 Deep Work 로그에 기록.
