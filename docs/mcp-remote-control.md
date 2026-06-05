# NotchDock MCP Remote Control — Implementation Plan

NotchDock에 IPC 인터페이스를 추가해 Claude Desktop(MCP)에서 원격 제어할 수 있도록 하는 계획.
**현재 상태: 미구현. 이 문서는 구현 설계서.**

---

## 아키텍처

```
Claude Desktop
    ↕ MCP (stdio)
Node.js MCP Server   (mcp-server/)
    ↕ Unix domain socket
NotchDock.app        (NotchDock/IPC/)
    ↕ @MainActor
NotchDockViewModel
```

---

## IPC 프로토콜

- **소켓 경로:** `~/.notchdock/ipc.sock` (홈 경로가 104자 초과 시 `/tmp/notchdock.sock`)
- **와이어 포맷:** JSON Lines — `\n` 구분, 최대 1 MB

**요청:**
```json
{ "id": "uuid", "method": "getState", "params": { ... } }
```

**성공 응답:**
```json
{ "id": "uuid", "result": { ... } }
```

**오류 응답:**
```json
{ "id": "uuid", "error": { "code": "INVALID_PARAMS", "message": "..." } }
```

### 메서드 목록

| 메서드 | ViewModel 연결 |
|--------|---------------|
| `getState` | `overlayState`, `dropHubState`, `visibleIcons`, `toast`, `canUndoDangerousAction` 읽기 |
| `toggleExpand` | `toggleExpand()` |
| `close` | `closeOneLevel()` |
| `performAction(files, action?)` | `performDrop(inputs:target:)` |
| `undo` | `undoLastDangerousAction()` |
| `setIcon(iconID, enabled)` | `setIconEnabled(_:enabled:)` |
| `refreshIcons` | `refreshIcons()` |
| `resetPerf` | `resetPerfSnapshot()` |

---

## MCP Tools (Claude Desktop에 노출)

| Tool | 설명 |
|------|------|
| `notchdock_get_state` | 현재 상태 읽기 |
| `notchdock_toggle_expand` | 오버레이 열기/닫기 |
| `notchdock_close` | 한 단계 닫기 |
| `notchdock_perform_action(files, action?)` | 파일 액션 실행 |
| `notchdock_undo` | 마지막 위험 액션 되돌리기 |
| `notchdock_set_icon(iconID, enabled)` | 아이콘 활성/비활성 |
| `notchdock_refresh_icons` | 아이콘 목록 새로고침 |
| `notchdock_reset_perf` | 성능 스냅샷 초기화 |

---

## 파일 구조

### 새로 추가할 Swift 파일

**`NotchDock/IPC/IPCModels.swift`**
- `IPCRequest: Decodable` — `id`, `method: IPCMethod`, `params?`
- `IPCMethod: String, Decodable` — 8개 메서드 enum
- `IPCParams: Decodable` — `files?`, `action?`, `iconID?`, `enabled?`
- `IPCResponse: Encodable` — `id`, `result?`, `error?`; `.success` / `.failure` static helper
- `IPCResult: Encodable` — 모든 필드 optional, 메서드별 선택적 채움
- `IPCDockIcon`, `IPCToast` value types
- `extension DropHubState { var ipcString: String }` — `.focused(kind)` associated value 처리

**`NotchDock/IPC/IPCRequestHandler.swift`**
- `@MainActor final class IPCRequestHandler`
- `init(viewModel: NotchDockViewModel)`
- `func handle(_ request: IPCRequest) async -> IPCResponse`
- 각 메서드를 ViewModel 호출로 라우팅
- `performAction`: 경로 절대경로 검증, `action` 문자열 → `WorkActionKind` 변환, `viewModel.toast`로 결과 읽기
- `setIcon`: `IconSourceService.candidateIcons` 대조 검증

**`NotchDock/IPC/IPCServer.swift`**

소켓 I/O는 GCD 기반(blocking I/O를 Swift actor에서 수행하면 executor 블로킹 문제 발생)으로 구현:

```
@MainActor final class IPCServer        — 공개 퍼사드
    init(viewModel:) → IPCServerCore 생성
    start() / stop()

private final class IPCServerCore       — GCD + NSLock 기반 구현
    NSLock mu
    serverFD: Int32
    running: Bool
    acceptQ: DispatchQueue(.utility)
    connQ:   DispatchQueue(.utility, concurrent)

    start() → acceptQ에서 runAcceptLoop() 실행
    stop()  → running=false, FD close, unlink

    runAcceptLoop():
        mkdir ~/.notchdock/
        unlink 기존 소켓
        socket() / bind() / listen()
        while running { accept() → connQ.async serveConnection() }

    static serveConnection(_ fd):
        read until \n (max 1MB)
        JSONDecoder → IPCRequest
        Task { @MainActor in handler.handle(request) } + DispatchSemaphore
        JSONEncoder → write response + \n
```

**`NotchDock/AppDelegate.swift` 수정:**
```swift
private var ipcServer: IPCServer?

// applicationDidFinishLaunching에 추가:
let server = IPCServer(viewModel: viewModel)
ipcServer = server
server.start()

// 추가:
func applicationWillTerminate(_ notification: Notification) {
    ipcServer?.stop()
}
```

### 새로 추가할 Node.js 파일 (`mcp-server/`)

**`package.json`**
```json
{
  "name": "notchdock-mcp-server",
  "type": "module",
  "scripts": { "build": "tsc", "dev": "tsx src/index.ts" },
  "dependencies": { "@modelcontextprotocol/sdk": "^1.0.0" },
  "devDependencies": { "tsx": "^4.0.0", "typescript": "^5.0.0", "@types/node": "^20.0.0" }
}
```

**`tsconfig.json`**
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

**`src/notchdock-client.ts`**
- `sendRequest(method, params?)` — `net.createConnection(SOCKET_PATH)`, JSON+`\n` 쓰기, `\n`까지 읽기
- 500ms 연결 타임아웃 → `NotchDockNotRunningError`
- 10s 요청 타임아웃
- 호출마다 새 연결 (no persistent state)

**`src/tools.ts`**
- 8개 Tool 정의 + 8개 핸들러
- `wrapResult()` / `wrapError()` MCP content 헬퍼
- `performAction`: 절대경로 검증, 알려진 `WorkActionKind` 검증

**`src/index.ts`**
- MCP SDK `Server` + `StdioServerTransport`
- `ListToolsRequestSchema` → 8개 tool 반환
- `CallToolRequestSchema` → tool name으로 핸들러 라우팅

---

## Claude Desktop 설정

```bash
cd mcp-server && npm install && npm run build
```

```json
// ~/Library/Application Support/Claude/claude_desktop_config.json
{
  "mcpServers": {
    "notchdock": {
      "command": "node",
      "args": ["/Users/river/project/mac-menubar/mcp-server/dist/index.js"]
    }
  }
}
```

---

## 구현 시 주의사항

- 앱이 **샌드박스 없음** (`CODE_SIGN_STYLE: Automatic`, `.entitlements` 없음) → Unix 소켓 entitlement 불필요
- `NotchDockViewModel`은 `@MainActor` → IPC 핸들러도 `@MainActor`로 선언, `Task { @MainActor in ... }` + `DispatchSemaphore`로 백그라운드 스레드에서 호핑
- `performDrop` 결과는 `viewModel.toast`로 읽기 (ViewModel API 변경 불필요)
- Node.js MCP 서버는 NotchDock이 실행 중이 아니면 tool error 반환 (크래시 아님)
- `project.yml` 수정 불필요 — `sources: path: NotchDock`이 하위 디렉토리 재귀 포함, `IPC/` 자동 인식

---

## 검증 절차

1. Xcode에서 NotchDock 빌드 및 실행
2. `ls ~/.notchdock/ipc.sock` — 소켓 파일 존재 확인
3. `printf '{"id":"t1","method":"getState"}\n' | nc -U ~/.notchdock/ipc.sock` — `overlayState` 포함 JSON 반환 확인
4. `printf '{"id":"t2","method":"toggleExpand"}\n' | nc -U ~/.notchdock/ipc.sock` — 오버레이 열기/닫기 확인
5. `cd mcp-server && npm install && npm run build`
6. Claude Desktop 설정 업데이트 후 재시작
7. Claude에서 "What state is NotchDock in?" → overlay state 반환
8. Claude에서 "Toggle NotchDock open" → 오버레이 애니메이션
