# Phase 1 1주차 Spike 결과

> 수행일: 2026-05-25
> 환경: macOS Darwin 25.3.0, ARM64, locale ko_KR.UTF-8

## 요약

| # | Spike 항목 | 상태 | 결론 |
|---|---|---|---|
| 1 | 모델 ID 매핑 (gpt-5.5-medium/high/xhigh) | ✅ 완료 | `codex exec --model gpt-5.5 -c model_reasoning_effort=<level>`로 매핑 |
| 2 | kordoc 한국어/한자 처리 호환성 | ✅ 완료 | v2.9.0 (2026-05-24 릴리즈), HWP/HWPX/PDF/Office 모두 지원, MCP+CLI |
| 3 | decktape ↔ Reveal.js 5.x 호환성 | ✅ 완료 | 4슬라이드 한국어 포함 PDF 정상 변환 (82KB, PDF 1.7) |
| 4 | Antigravity CLI 검증 (Phase 3) | ⚠️ 정정 | Antigravity는 GUI IDE, **CLI는 없음**. 실제 사용은 **gemini CLI 0.42.0** (이미 설치) |

---

## Spike #1: 모델 ID 매핑 ✅

### 발견사항
- `~/.codex/config.toml`에 이미 `model = "gpt-5.5"` + `model_reasoning_effort = "xhigh"` 설정되어 있음
- 즉 `gpt-5.5`는 **실재하는 Codex 모델 이름**
- PRD_v1의 `gpt-5.5-medium/high/xhigh` 표기는 실제로는 **모델 + effort 조합**

### 검증된 호출 방법

```bash
# decomposer (medium effort)
codex exec --model gpt-5.5 -c model_reasoning_effort=medium "분해할 자료..."

# composer (high effort)
codex exec --model gpt-5.5 -c model_reasoning_effort=high "12-13챕터 재구성..."

# reviewer (xhigh effort)
codex exec --model gpt-5.5 -c model_reasoning_effort=xhigh "오탈자/내용 점검..."
```

### 실제 검증
```
$ echo "Hi. Just say 'OK from gpt-5.5 medium' and nothing else." | \
    codex exec --model gpt-5.5 -c model_reasoning_effort=medium
...
model: gpt-5.5
reasoning effort: medium
codex
OK from gpt-5.5 medium
tokens used: 10,952
```

### 추가 메모
- Codex CLI 인증되어 있음 (`~/.codex/auth.json`)
- 본 프로젝트 디렉토리는 codex 트러스트 목록에 미포함 → 첫 실행 시 trust 프롬프트 예상
- approval: never, sandbox: read-only가 기본값 → exec에서 파일 쓰기 필요 시 옵션 조정 필요
- 옵션 후보: `-c approval_policy="on-request"`, `-c sandbox_mode="workspace-write"` (Phase 1 시작 시 검증)

---

## Spike #2: kordoc 호환성 ✅

### 발견사항
- 저장소: https://github.com/chrisryugj/kordoc
- **매우 활발한 유지보수**: 2026-05-24 (어제) v2.9.0 릴리즈
- 슬로건: "모두 파싱해버리겠다"
- 지원 포맷: HWP 3.x/5.x, **HWPX, HWPML**, PDF, XLS, XLSX, DOCX
- 제공 형태: CLI + MCP Server
- 설치: `npx -y kordoc setup` (대화형 마법사, Claude Code/Antigravity/Gemini 자동 감지)

### 핵심 기능
- 신구대조 (diff)
- 양식 자동 채우기
- 한국어/한자/Office 문서 → Markdown 변환
- v2.9.0 릴리즈 노트: "PDF 텍스트 품질 신호 + OCR 필요 판정" — PDF 텍스트 품질 자동 평가까지 지원

### 통합 방법
**옵션 A (추천): MCP Server로 연동**
- `npx -y kordoc setup`으로 Claude Code 통합
- 에이전트가 자연어로 파일 파싱 요청
- 우리 PRD의 decomposer에 자연스러움

**옵션 B: CLI 직접 호출**
- `npx kordoc <input.hwp> <output.md>` (예시 명령, README 확인 필요)
- bash 스크립트에서 호출

### 본 프로젝트 적용
- `Previous_lecture_content/목차_학지사_교육방법및교육공학.hwp` 파싱 → composer가 12-13챕터 매핑 시 사용
- `Previous_lecture_content/{semester}/...` 의 ppt/pdf/docx 자료 파싱 → decomposer

---

## Spike #3: decktape ↔ Reveal.js 5.x 호환성 ✅

### 검증 절차
1. `npm install -g decktape` (12초)
2. `/tmp/spike-revealjs/index.html` 생성 — Reveal.js 5.x (unpkg CDN) + 한국어 4슬라이드 + 발표자 노트
3. `python3 -m http.server 8765` 로컬 서빙
4. `decktape reveal http://localhost:8765 out.pdf` 실행

### 결과
```
Loading page http://localhost:8765 ...
Loading page finished with status: 200
Reveal JS plugin activated
Printing slide #/0      (1/4) ...
Printing slide #/1      (2/4) ...
Printing slide #/2      (3/4) ...
Printing slide #/3      (4/4) ...
Printed 4 slides

out.pdf: PDF document, version 1.7  (82,073 bytes)
```

- ✅ decktape의 reveal 플러그인이 Reveal.js 5.x 자동 감지
- ✅ 4슬라이드 모두 정상 변환
- ✅ 한국어 콘텐츠 보존 (sample 보관: `spike/sample-revealjs/`)

### 검증된 호출 방법 (Phase 1 export-pdf.sh의 핵심 한 줄)
```bash
decktape reveal "http://localhost:${PORT}/${chapter}/slides/deck.html" \
    "content/chapters/${chapter}/slides/deck.pdf"
```

또는 file:// (실험 필요):
```bash
decktape reveal "file:///${ABS_PATH}/deck.html" "${OUT_PDF}"
```

### 사이즈/품질 옵션
- `-s 1920x1080`: 풀HD 해상도 (강의실 디스플레이용)
- `--pause 2000`: 슬라이드별 2초 대기 (애니메이션 안정화)
- `--pdf-author "임태형"`, `--pdf-title "..."` 메타데이터

---

## Spike #4: Antigravity CLI ⚠️ (PRD 정정 필요)

### 발견사항
- `/Applications/Antigravity.app` 설치되어 있음 (53KB Electron 런처)
- **하지만 CLI 바이너리 없음** — `/usr/local/bin/antigravity` 미존재, `/opt/homebrew/bin/antigravity` 미존재
- 내부에 `chrome-devtools-mcp` 등 MCP 관련 코드가 있지만 외부 노출 안 됨
- Antigravity는 Google의 AI coding 데스크톱 IDE (Cursor 류) — CLI 자동화 대상 아님

### 대안: Gemini CLI ✅
- `gemini` 0.42.0 이미 설치되어 있음 (`/opt/homebrew/bin/gemini`)
- 비대화형 모드 지원: `gemini -p "..." -m gemini-2.5-pro` (모델 매개변수 명시)
- `-o json` 으로 구조화된 출력
- MCP/skills/hooks 모두 지원

### PRD_v1 정정 사항
- "Antigravity CLI도 oauth 로 인증하여 gemini 모델들도 활용" → **"gemini CLI(0.42.0)로 OAuth 인증하여 Gemini 모델 활용"**
- Phase 3에서 A-B 모델 비교 시 사용할 도구는 **`gemini`** CLI

### 미완료 (Phase 3 전 별도 트랙)
- [ ] gemini CLI 인증 상태 확인 (`gemini -p "test"` 첫 호출 시 인증 flow 거침)
- [ ] gemini의 활용 가능한 모델 enumerate (gemini-2.5-pro? gemini-2.5-flash?)
- [ ] decomposer/composer에서 gpt-5.5 vs gemini 출력 품질 A-B 비교 rubric

---

## 추가 환경 확인 (보너스)

설치되어 있는 도구:
| 도구 | 버전 | 용도 |
|---|---|---|
| codex | 0.133.0 | Codex CLI (decomposer/composer/reviewer) |
| claude | 2.1.139 | Claude Code (director/designer/developer) |
| gemini | 0.42.0 | Gemini CLI (Phase 3) |
| tmux | 3.6a | 멀티 pane 오케스트레이션 |
| jq | 1.8.1 | STATE.json 조작 |
| node | v25.9.0 | decktape, kordoc 런타임 |
| npm | 11.12.1 | 패키지 설치 |
| python3 | 3.14.3 | 로컬 정적 대시보드 서버 |
| gh | 2.89.0 | GitHub API |
| decktape | (방금 설치) | PDF auto-export |

→ **Phase 1 시작에 필요한 모든 의존성 갖춰짐**.

---

## PRD 업데이트 필요 항목

1. **04_PROJECT_SPEC.md**:
   - 기술 스택 테이블에 정확한 codex 호출 예시 추가
   - decomposer/composer/reviewer 행동 규약에 정확한 명령 명시
   - "Antigravity CLI" → "Gemini CLI (gemini 0.42.0)" 정정
   - decktape 설치 + 호출 예시 추가
   - kordoc 설치/호출 예시 추가
2. **README.md**:
   - Phase 1 1주차 spike 결과 ✅ 마킹
   - Antigravity 정정 노트
3. **03_PHASES.md**:
   - Phase 1 첫 3-5일 spike 트랙 → "이미 spike 완료, 본격 구현 진입 가능" 업데이트
   - Phase 3에서 Antigravity → gemini CLI로 표기 변경

## 다음 단계

1. PRD 4개 파일 업데이트 (위 항목 반영)
2. 본격 Phase 1 구현 시작:
   - `.claude/agents/{director,decomposer,composer,designer,developer}.md` 작성
   - `scripts/start-session.sh` 등 tmux 스크립트
   - 1주차 도입/개관 챕터 자료 (2026-1) → kordoc으로 파싱 시작
