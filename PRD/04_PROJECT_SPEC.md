# lecture-content-maker-agent-team -- 프로젝트 스펙

> AI가 코드를 짤 때 지켜야 할 규칙과 절대 하면 안 되는 것.
> 이 문서를 AI에게 항상 함께 공유하세요. `pumasi`/`/feature-dev` 호출 시 컨텍스트로 넣을 것.

---

## 기술 스택

| 영역 | 선택 | 이유 |
|---|---|---|
| 오케스트레이션 런타임 | tmux 다중 pane + bash send-keys | PRD_v1 명시 요구, 0 설치(이미 있음), 1챕터 PoC에 충분, AI 코딩 호환성 최고 |
| Director 모델 | Claude Code Opus 4.7 (max effort) | 멀티에이전트 조율은 최강 모델, PRD_v1 명시. 자동 업그레이드(Opus 차세대 출시 시) |
| Decomposer 모델 | Codex CLI / gpt-5.5-medium | PRD_v1 명시, 한국어 파싱 강점, 속도 우선 |
| Composer 모델 | Codex CLI / gpt-5.5-high | PRD_v1 명시, 12-13챕터 재구성 품질 우선 |
| Designer 모델 | Claude Code Sonnet 최신 | PRD_v1 명시, 시각/구조 설계 강점 |
| Developer 모델 | Claude Code Sonnet 최신 | PRD_v1 명시, 코드(HTML/JS) 산출 강점 |
| Reviewer 모델 | Codex CLI / gpt-5.5-xhigh | PRD_v1 명시, 검수 라운드 전용 |
| 슬라이드 엔진 | Reveal.js 5.x | 강의 도메인 표준, PDF/단축키/줌 내장, 학습곡선 낮음 |
| 파서 (기존 자료) | chrisryugj/kordoc + Google Slides API | PRD_v1 명시(kordoc), 한국어 처리, Google Slides 정확 추출 |
| 이미지 수급 | Wikimedia Commons API + gpt-image-gen | Wiki license-free 우선, fallback GPT 이미지 |
| PDF 변환 | decktape | Reveal.js 표준 PDF 익스포터, headless Chromium 기반 |
| 상태 관리 | 파일 시스템 + STATE.json | DB 없음, atomic write로 race condition 회피 |
| 대시보드 | vanilla HTML + Tailwind CDN + 5s polling JS | zero install, 1인 도구에 적정 복잡도 |
| 데이터 처리 | bash + jq (STATE.json 조작) | 의존성 없음, 텍스트/JSON 처리 충분 |
| 환경변수 | `.env` 파일 + `dotenv` (스크립트 내 `set -a; source .env; set +a`) | 단순, GitHub 미커밋 |
| Google Slides 인증 | User OAuth (PI 계정, refresh token `.env`에 저장) | 1인 도구에 자연스러움, PI 소유 슬라이드 즉시 접근 가능 (추가 공유 불필요) |
| 인용(citations) 포맷 | CSL JSON (Citation Style Language) | Zotero/Pandoc 호환, APA/MLA 등 스타일 자동 변환, Phase 3 교재화 재사용 |
| Pane 완료 감지 | sentinel(`# AGENT_DONE_SIGNAL: <task_id>`) + `tmux capture-pane` 폴링 (2-3초) | 0 의존성, 디버깅 쉬움, 시도 실패도 sentinel 없음으로 감지 |
| Retry 정책 | 지수 백오프 3회 (1s → 10s → 100s) | 일시적 장애 자동 복구, 비용 폭주 없음 |
| 세션 복구 | STATE.json 기반 자동 재개 (마지막 task부터) | PI 개입 불필요, 비용 낭비 최소 |
| 비용 추적 | STATE.json에 task별 누적 비용 기록 (한도 없음) | PoC 관찰 용이, PI 모니터링 |

---

## 프로젝트 구조

```
lecture-content-maker-agent-team/
├── .claude/
│   └── agents/                  # 5에이전트 시스템 프롬프트
│       ├── director.md
│       ├── decomposer.md
│       ├── composer.md
│       ├── designer.md
│       └── developer.md
├── Previous_lecture_content/    # 입력 자료 (이미 존재, read-only)
├── content/                     # 산출물 디렉토리
│   └── chapters/
│       └── chapter-NN/
│           ├── decomposed.md, composed.md, DESIGN.md
│           ├── slides/{deck.md, deck.html, deck.pdf}
│           ├── images/, citations.json
│           └── reviews/
├── scripts/                     # bash 스크립트
│   ├── start-session.sh         # tmux 5-pane 세션 부팅
│   ├── send-to-pane.sh          # send-keys 헬퍼
│   ├── run-review.sh            # 검수 루프 실행기
│   ├── fetch-image.sh           # Wikimedia + gpt-image-gen
│   └── export-pdf.sh            # decktape 호출
├── dashboard/                   # 로컬 정적 대시보드
│   ├── index.html
│   ├── poll.js                  # STATE.json 5초 폴링
│   └── style.css
├── prompts/                     # 에이전트별 작업 프롬프트 템플릿
│   ├── decomposer/
│   ├── composer/
│   ├── designer/
│   ├── developer/
│   └── reviewer/                # 검수 루프 프롬프트
├── STATE.json                   # 시스템 상태
├── .env                         # 외부 API 키 (.gitignore 필수)
├── .gitignore
├── PRD/                         # 본 디자인 문서
└── README.md
```

---

## 에이전트 행동 규약

### director (Claude Code Opus 4.7)
- 다른 에이전트에게 작업 분배만 한다. **직접 콘텐츠 생성 금지**.
- 항상 STATE.json을 atomic write로 갱신 (`.tmp` → `mv`).
- 에이전트 실패 시 retry 정책에 따라 재시도, 3회 실패 시 manual override 모드 진입.
- send-keys로 명령 보낼 때 명령 끝에 sentinel(`# AGENT_DONE_SIGNAL: <task_id>`) 출력 요청.
- `tmux capture-pane`으로 sentinel 감지하여 완료 판정 (또는 output 파일 존재 + non-zero 검증).
- 다른 에이전트의 작업 디렉토리를 직접 수정 금지 — STATE.json 갱신만.

### decomposer (Codex CLI / gpt-5.5 medium effort)
- `Previous_lecture_content/{semester}/{topic}/` 폴더의 모든 파일을 파싱.
- 출력: 단일 `decomposed.md` (주제별 섹션 구조 보존).
- 한국어 처리 우선, kordoc(v2.9.0+) 활용 — `npx -y kordoc setup`으로 MCP 통합 권장.
- Google Slides는 별도 인증 흐름 거쳐 정확하게 가져옴.
- 원본 자료 수정 금지 (`Previous_lecture_content/`는 read-only).
- 분해 후 sentinel 출력 + STATE.json 업데이트 신호.

**호출 예시** (검증 완료):
```bash
codex exec --model gpt-5.5 -c model_reasoning_effort=medium \
  -c approval_policy="on-request" -c sandbox_mode="workspace-write" \
  "Previous_lecture_content/2026-1/1주차/* 를 분해하여 content/chapters/chapter-01/decomposed.md에 한국어 .md로 저장하라. ..."
```

### composer (Codex CLI / gpt-5.5 high effort)
- 입력: `decomposed.md` + 학지사 목차(.hwp 파싱 결과, kordoc 사용) + (Phase 2+) 다른 챕터의 composed.md (cross-reference).
- 출력: `composed.md` — 장-절-항 줄글, `#`/`##`/`###` 마크다운 계층.
- **챕터 수 제약**: 12개 기본, 13개 허용, 14개 이상 절대 불가.
- 표/그림을 적재적소에 배치 (`[그림 1-1] ADDIE 모형` 자리 표시).
- 추후 전공교재로 업그레이드 가능한 줄글 형태 유지 (불릿 남발 X).

**호출 예시**:
```bash
codex exec --model gpt-5.5 -c model_reasoning_effort=high \
  -c sandbox_mode="workspace-write" \
  "$(cat prompts/composer/system.md) $(cat content/chapters/chapter-01/decomposed.md)"
```

### designer (Claude Code Sonnet)
- 입력: `composed.md`.
- 출력: `DESIGN.md` — 슬라이드 구조 명세 (제목 / 학습목표 / 섹션 / 내용 / 참고문헌 슬라이드 타입).
- **DESIGN.md 스키마**: nexu-io/open-design 분석(1주차 spike) 후 채택 또는 각색.
- **Mayer 멀티미디어 원리 적용**:
    - 분할 원리: 한 슬라이드에 너무 많은 텍스트 X
    - 모달리티 원리: 그림 자료를 적극 활용
    - 추가 원리(공간/시간 근접성, 일관성, 신호 등)도 적용 권장
- 이미지 요구사항을 구체적으로 명세 ("ADDIE 모형 흐름도 - 가로 5단계 배치, 한국어 라벨").
- 직접 이미지 생성/검색은 안 함 — image-fetcher 호출 트리거만 발행.
- **이미지 라이선스 단체 점검 (Round 3 검수)**: designer round 3에서 reviewer가 모든 Asset의 `license` 필드를 표로 정리해 PI에게 확인 트리거 발행. 자동 신뢰가 기본이되, 의심 사례는 PI 수동 승인.

### developer (Claude Code Sonnet)
- 입력: `DESIGN.md` + `composed.md` + `images/`.
- 출력: `deck.md` (Reveal.js source) → `deck.html` (정적 빌드) → `deck.pdf` (decktape).
- **HTML만**. pptx 변환 금지.
- 발표자 노트는 composed.md의 단락별 설명문에서 자동 주입 (`<aside class="notes">`).
- Reveal.js **5.x** 사용 (CDN: `https://unpkg.com/reveal.js@5/...`), 옵션은 DESIGN.md 명세 따름.
- 빌드 후 `deck.html`이 단독으로 열리는지(상대 경로 깨짐 없는지) 검증.

**PDF 익스포트 (검증 완료)**:
```bash
# 로컬 정적 서버 띄우고 decktape 호출
python3 -m http.server 8765 -d content/chapters/chapter-01/slides &
SERVER_PID=$!
sleep 1
decktape reveal -s 1920x1080 --pause 1500 \
  --pdf-author "임태형" --pdf-title "교육방법 및 교육공학 — 1주차" \
  "http://localhost:8765/deck.html" \
  "content/chapters/chapter-01/slides/deck.pdf"
kill $SERVER_PID
```

Spike 검증 결과: Reveal.js 5.x 슬라이드덱(한국어 + 발표자 노트 + 참고문헌) → 82KB PDF 1.7 정상 생성 (`spike/sample-revealjs/`).

### reviewer (Codex CLI / gpt-5.5 xhigh effort, 모든 단계 공통)
- 검수 대상: composer/designer/developer 각 단계 산출물.
- 라운드 1-3 진행, 각 라운드는 다음을 점검:
    - **Round 1**: 오탈자, 문법, 한국어 자연스러움
    - **Round 2**: 내용 정확성, 인용 출처, 사실 오류
    - **Round 3**: 일관성, 학습 흐름, Mayer 원리 (designer/developer 한정), **이미지 license 단체 점검 (designer Round 3)**
- `issues_count = 0`이면 통과(조기 종료 가능).
- round 3까지도 `issues_count > 0`이면 강제 종료 후 manual override 모드.
- 검수 결과는 `reviews/{role}-round-{N}.md`에 저장 (issues 목록 + 변경 diff).

**호출 예시**:
```bash
codex exec --model gpt-5.5 -c model_reasoning_effort=xhigh \
  -c sandbox_mode="workspace-write" \
  "$(cat prompts/reviewer/round-${N}.md) $(cat ${TARGET_FILE})"
```

---

## 절대 하지 마 (DO NOT)

> AI에게 코드를 시킬 때 이 목록을 반드시 함께 공유하세요.

- [ ] **API 키/OAuth 토큰을 코드에 직접 쓰지 마** — `.env` 파일 사용. `.env`는 `.gitignore`에 반드시.
- [ ] **STATE.json을 직접 덮어쓰지 마** — 항상 `temp.json` → `mv` atomic 패턴.
- [ ] **pptx로 변환하지 마** — HTML만. PowerPoint export는 Phase 2 이후 별도 검토.
- [ ] **챕터를 14개 이상 만들지 마** — 12 기본, 13 허용, 14+ 절대 금지.
- [ ] **검수 루프를 무한 돌리지 마** — round 3에서 강제 종료 + manual override.
- [ ] **이미지를 라이선스 확인 없이 사용하지 마** — license/attribution 메타 필수.
- [ ] **send-keys로 비밀번호/토큰 보내지 마** — 절대 평문 전송 X.
- [ ] **다른 챕터의 파일을 직접 수정하지 마** — 자기 chapter 디렉토리만 read/write.
- [ ] **목업/하드코딩 데이터로 "완성"이라고 하지 마** — Phase 1도 진짜 자료/진짜 모델 호출 기반.
- [ ] **gpt-5.5-xhigh를 검수 외 다른 단계에 쓰지 마** — 비용/속도 이유. 검수 전용.
- [ ] **gemini CLI(제3 모델)를 Phase 1에 넣지 마** — Phase 3 진입 후. (Antigravity는 GUI IDE라 자동화 대상 아님, spike 결과 정정)
- [ ] **STATE.json 스키마를 임의로 바꾸지 마** — 변경 시 마이그레이션 스크립트 동반.
- [ ] **`Previous_lecture_content/` 안의 원본을 수정하지 마** — read-only.
- [ ] **다중 챕터 병렬을 Phase 1에 하지 마** — PoC는 1챕터.
- [ ] **외부 호스팅 대시보드를 Phase 1에 만들지 마** — 로컬 정적 HTML만.
- [ ] **모델 선택을 임의로 변경하지 마** — PRD_v1 명시 모델 매핑 준수. 변경 필요 시 PRD 업데이트 후.
- [ ] **검수 결과를 무시하지 마** — `passed=false`인 단계는 다음 단계로 넘기지 않음.

---

## 항상 해 (ALWAYS DO)

- [ ] 변경 전에 계획(plan)을 먼저 보여줘.
- [ ] 환경변수는 `.env`에 저장. 스크립트에서 `set -a; source .env; set +a`로 로드.
- [ ] 에이전트 명령 끝에 sentinel(`# AGENT_DONE_SIGNAL: <task_id>`) 출력 — director가 완료 감지.
- [ ] STATE.json 업데이트는 atomic write (`*.tmp` → `mv`).
- [ ] 모든 외부 API 호출은 **지수 백오프 3회** (1s → 10s → 100s). 3회 실패 시 STATE.json에 `error_message` 기록 후 manual override 진입.
- [ ] 모든 파일 경로는 절대 경로 또는 프로젝트 루트 기준 상대 경로.
- [ ] 검수 루프 결과는 `reviews/{role}-round-{N}.md`에 저장. `issues_count=0`이면 조기 종료, round 3까지 미수렴이면 강제 종료.
- [ ] 이미지 메타데이터는 `{path}.meta.json`에 함께 (license, attribution, alt_text). designer round 3에서 batch 점검.
- [ ] citations는 CSL JSON 형식으로 `citations.json` 배열에 저장.
- [ ] 한국어 텍스트는 UTF-8.
- [ ] 모든 bash 스크립트는 `set -euo pipefail` 시작.
- [ ] **각 GPT/Sonnet/이미지 API 호출 시** input/output 토큰 × 단가를 계산해 `STATE.json` 의 `task.cost_usd`에 누적, 전체 합은 `cumulative_cost_usd`로 노출.
- [ ] 세션 재시작 시 STATE.json 읽고 마지막 `in_progress` task부터 이어서 진행 (idempotent 설계).
- [ ] composed.md는 `# 장 / ## 절 / ### 항` 표준 마크다운 계층 준수.

---

## 테스트 방법

```bash
# decktape 설치 (1회)
npm install -g decktape

# kordoc 설치 (1회, Claude Code MCP 통합)
npx -y kordoc setup

# 1챕터 PoC 실행 (Phase 1 검증)
bash scripts/start-session.sh chapter-01

# 시스템 상태 확인
cat STATE.json | jq

# 대시보드 보기
open dashboard/index.html
# 또는 python3로 정적 서버
python3 -m http.server -d dashboard 8000

# 검수 루프만 단독 실행 (특정 챕터/단계)
bash scripts/run-review.sh chapter-01 composer

# PDF만 재생성
bash scripts/export-pdf.sh chapter-01

# tmux 세션 강제 종료 후 재개 테스트
tmux kill-session -t lecture-team
bash scripts/start-session.sh chapter-01  # STATE.json 기반 재개되는지 확인

# Reveal.js 슬라이드덱 단독 확인
open content/chapters/chapter-01/slides/deck.html

# 검수 루프 무한 가드 검증 (의도적 오류 주입 후 round 3 강제 종료 동작 확인)
bash scripts/test-review-guard.sh chapter-01

# 이미지 자동 수급 단위 테스트
bash scripts/fetch-image.sh "ADDIE 모형" content/test/
```

---

## 배포 방법

**Phase 1**: 로컬 1인 도구 — 별도 배포 없음. PI 본인의 macOS에서 tmux로 실행.

**Phase 3 옵션** (선택):
- 대시보드만 Vercel/Netlify에 정적 호스팅 (STATE.json은 GitHub에 push해서 fetch)
- 또는 Supabase Realtime + Next.js 풀스택 마이그레이션

---

## 환경변수

`.env` 파일 (`.gitignore`에 반드시 포함):

| 변수명 | 설명 | 어디서 발급 |
|---|---|---|
| OPENAI_API_KEY | Codex CLI fallback (OAuth 실패 시) | https://platform.openai.com/api-keys |
| GOOGLE_OAUTH_CLIENT_ID | Google Slides User OAuth Client ID | https://console.cloud.google.com/apis/credentials |
| GOOGLE_OAUTH_CLIENT_SECRET | Google Slides User OAuth Client Secret | 위와 동일 |
| GOOGLE_OAUTH_REFRESH_TOKEN | PI 계정으로 발급된 refresh token (`gcloud auth application-default login`처럼 1회 인증 후 저장) | OAuth 인증 흐름 거쳐 발급 |
| WIKIMEDIA_USER_AGENT | Wikimedia API 호출 시 User-Agent (매너 + 일부 호출 요구) | 자유 형식 (예: `lecture-content-maker/0.1 (limtaehyeong@gmail.com)`) |
| ANTHROPIC_API_KEY | Claude Code fallback (보통 불필요, OAuth 사용) | Claude Code는 `/login` OAuth 우선 |
| GPT_IMAGE_GEN_KEY | gpt-image-gen 호출용 (보통 OPENAI_API_KEY와 동일) | 동일 |

OAuth 인증 (별도 명령):
```bash
codex auth login           # Codex CLI OAuth
# Claude Code는 인스턴스 안에서 /login으로 OAuth
```

---

## Phase 1 1주차 Spike (2026-05-25 ✅ 완료)

상세는 [`../spike/RESULTS.md`](../spike/RESULTS.md). 본격 구현 진입 가능.

- [x] **모델 ID 매핑** ✅ — `codex exec --model gpt-5.5 -c model_reasoning_effort=<medium|high|xhigh>`. config.toml에 이미 `gpt-5.5` 설정.
- [x] **kordoc 호환성** ✅ — v2.9.0 (2026-05-24 어제), HWP3/5/HWPX/HWPML/PDF/Office 모두 지원. MCP+CLI. `npx -y kordoc setup`.
- [x] **decktape ↔ Reveal.js 5.x** ✅ — 4슬라이드 한국어 PDF 정상(82KB). 명령은 위 developer 섹션 참고.
- [x] **Antigravity → gemini CLI 정정** ⚠️ — Antigravity는 GUI IDE. Phase 3에서 사용할 도구는 **`gemini` CLI 0.42.0**(이미 설치). PRD 본문 정정 반영됨.

## Phase 2 진입 시 결정 보류 (지금 안 정함)

- [ ] **Google Slides API quota**: 매학기 4학기치 슬라이드 파싱 시 quota 충돌 가능성 — Phase 2 진입 전 quota 신청 또는 캐시 전략.
- [ ] **send-keys race condition 한도**: 5 pane은 안전, 50 pane(12챕터 병렬)에서도 안전한지 — Phase 2 도입 전 부하 테스트, 깨지면 Python+libtmux 마이그레이션.
- [ ] **PI의 manual override UX**: tmux에서 직접 챕터 디렉토리 수정 vs 별도 CLI 명령 — Phase 1 1주차에 시연 후 합의.
- [ ] **검수 비용 누적 데이터**: Phase 1 완주 후 실제 비용으로 Phase 2 월간 한도 산정.
- [ ] **Wikimedia license 정확도**: 운영 데이터 수집 후 자동/수동 비율 정책 조정.
