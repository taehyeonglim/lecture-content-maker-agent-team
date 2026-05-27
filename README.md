# lecture-content-maker-agent-team

> PI(임태형 교수)의 강의 콘텐츠를 **분해 → 재구성 → 디자인 → 개발**까지 자동화하는 Claude Code 기반 5-에이전트 시스템.
>
> Tmux 다중 pane에서 Claude Opus(오케스트레이션) + Codex GPT(분해/구성) + Claude Sonnet(디자인/개발)이 협업하여 1챕터당 Reveal.js 슬라이드덱 + PDF를 자동 산출.

## 빠른 시작

```bash
# 1. 의존성 확인 (이미 설치되어 있다면 skip)
brew install tmux jq
npm install -g decktape

# 2. kordoc MCP 통합 (한국어 문서 파서)
npx -y kordoc setup

# 3. 환경변수 셋업
cp .env.example .env
# .env 편집 — Google OAuth refresh token 등

# 4. 1챕터 PoC 실행
bash scripts/start-session.sh chapter-01

# 5. 대시보드 확인 (다른 터미널)
python3 -m http.server -d dashboard 8080
open http://localhost:8080
```

## 문서 구조

| 폴더/파일 | 역할 |
|---|---|
| [PRD/](./PRD/) | 디자인 문서 5종 (요구사항/데이터 모델/Phase/스펙/README) — AI에게 작업 시킬 때 항상 첨부 |
| [PRD_v1](./PRD_v1) | 원본 아이디어 (PI의 1차 기획) |
| `Previous_lecture_content/` | PI 사적 강의 자료 (`.gitignore` — public repo 에 X). 다른 사용자는 자기 자료를 같은 경로 또는 다른 경로에 두면 됨. |
| [spike/](./spike/) | Phase 1 1주차 spike 결과 + 검증 샘플 |
| [.claude/agents/](./.claude/agents/) | 5 에이전트 시스템 프롬프트 |
| [scripts/](./scripts/) | 5 핵심 bash 자동화 스크립트 |
| [dashboard/](./dashboard/) | 로컬 정적 HTML 대시보드 |
| [prompts/](./prompts/) | 에이전트별 작업 프롬프트 템플릿 |
| `.env.example` | 환경변수 예시 (`.env`로 복사해 사용) |
| `STATE.json` | 시스템 상태 (start-session.sh가 생성/갱신) |

## 아키텍처 한 눈에 보기

```
tmux session "lecture-team"
├── pane 0: director       (Claude Opus 4.7, 오케스트레이션)
├── pane 1: decomposer     (Codex gpt-5.5 medium, kordoc 활용)
├── pane 2: composer       (Codex gpt-5.5 high, 12-13챕터 재구성)
├── pane 3: designer       (Claude Sonnet, Mayer 멀티미디어 원리)
└── pane 4: developer      (Claude Sonnet, Reveal.js 5.x + decktape PDF)

산출 흐름 (1챕터):
원본 자료 → decomposed.md → composed.md → DESIGN.md → deck.{md,html,pdf}
              ↑ 각 단계마다 reviewer(gpt-5.5 xhigh)가 3회 검수 루프
              (issues=0 조기 종료, round 3 미수렴 시 manual override)

상태 관리:
STATE.json (singleton, atomic write) ← director only writes
└── dashboard/index.html (5초 폴링) ← read only
```

## Phase 1 범위

- **PoC 챕터**: 1주차 · 도입/개관 (2026-1 학기 자료 base)
- **부가 기능**: 이미지 자동 수급 (Wikimedia + gpt-image-gen) + 3회 검수 루프 + PDF auto-export
- **목표 산출**: `content/chapters/chapter-01/slides/deck.{html,pdf}` — 실제 강의에 사용 가능한 품질

Phase 2/3는 [PRD/03_PHASES.md](./PRD/03_PHASES.md) 참고.

## 필수 도구

| 도구 | 버전 | 용도 |
|---|---|---|
| codex | 0.133.0+ | decomposer/composer/reviewer (gpt-5.5) |
| claude | 2.x | director/designer/developer (Opus/Sonnet) |
| tmux | 3.x | 멀티 pane 오케스트레이션 |
| jq | 1.x | STATE.json 조작 |
| node | 20+ | decktape, kordoc 런타임 |
| python3 | 3.x | 로컬 정적 대시보드 서버 |
| decktape | (npm 글로벌) | Reveal.js → PDF |
| kordoc | v2.9.0+ (MCP) | HWP/HWPX/PDF/Office → Markdown |

(gemini CLI는 Phase 3 진입 시 검증)

## 디자인 결정 21개 (요약)

모든 핵심 결정은 [PRD/README.md](./PRD/README.md)의 "핵심 결정 요약" 섹션에 정리되어 있습니다.

핵심만 추리면:
- 런타임: tmux 다중 pane + bash send-keys + sentinel (`# AGENT_DONE_SIGNAL: <task_id>`)
- 검수: gpt-5.5 xhigh로 3회 루프, `issues=0` 조기 종료
- Retry: 지수 백오프 3회 (1s → 10s → 100s)
- 세션 복구: STATE.json 기반 자동 재개
- composed.md 컨벤션: `# 장 / ## 절 / ### 항`
- citations: CSL JSON
- 비용: STATE.json에 누적, 한도 없음

## Phase 1 1주차 Spike (✅ 2026-05-25 완료)

[spike/RESULTS.md](./spike/RESULTS.md) — 모델 매핑 / kordoc / decktape / gemini CLI 검증 결과.

## 참고

- [chrisryugj/kordoc](https://github.com/chrisryugj/kordoc) — 한국어 문서 파서
- [nexu-io/open-design](https://github.com/nexu-io/open-design) — 디자인 시스템 참고
- Richard Mayer, "Multimedia Learning" — 슬라이드 디자인 원리
- 학지사 "교육방법 및 교육공학" 목차 — 12-13챕터 매핑 기준

---

## 🌍 다른 사용자가 자기 강의로 사용하려면

본 repo 는 임태형 교수의 "교육방법 및 교육공학" 강의에 특화돼 있지만, **시스템 자체는 모든 과목·책에 일반화 가능**. 자기 강의로 사용하려면:

### 0. 사전 준비물 (비용 안내)

| 도구 | 비용 | 필수도 |
|---|---|---|
| **Claude Code subscription** ([anthropic.com/claude-code](https://www.anthropic.com/claude-code)) | Pro $20/월 또는 Max $100+/월 | 필수 — director/designer/developer 가 Opus/Sonnet 으로 작동 |
| **codex CLI + ChatGPT subscription** ([chat.openai.com](https://chat.openai.com)) | Plus $20/월 또는 Pro $200/월 | 필수 — decomposer/composer/reviewer + image_gen.imagegen (이미지 생성) |
| OpenAI API key | 보통 불필요 | codex 가 ChatGPT auth 로 작동. fallback 시에만 |
| 기타 (tmux/jq/decktape/kordoc) | 무료 | 위 빠른 시작 참고 |

한 챕터 = 약 15-25분 자동 처리, 토큰 비용은 두 subscription 에 흡수.

### 1. Repo clone + 의존성 설치

```bash
git clone https://github.com/taehyeonglim/lecture-content-maker-agent-team.git my-lecture
cd my-lecture
brew install tmux jq           # macOS. Linux 는 apt
npm install -g decktape
npx -y kordoc setup            # 한국어 문서 파서 (영문이면 skip 가능)
codex login                    # ChatGPT 계정
claude /login                  # Anthropic 계정
```

### 2. 자기 강의/교재 자료 넣기

```bash
mkdir -p Source/my-course
# 강의 자료 (PPTX/PDF/HWP/.gslides) 를 이 폴더에 복사
cp ~/Documents/my-week-1.pdf Source/my-course/
cp ~/Documents/my-week-2.pdf Source/my-course/
# ...
```

기존 `Previous_lecture_content/` 경로는 `.gitignore` 처리되어 있으므로 그대로 써도 무방하지만, 폴더 이름은 자유.

### 3. PRD 일반화 (가장 중요)

`PRD/01_PRD.md` 와 `PRD/03_PHASES.md` 에 PI 의 강의 맥락이 박혀 있음. 자기 강의에 맞춰 갱신:

- **챕터 수**: PRD 는 12-13챕터 가정. 자기 강의가 N주차면 N챕터.
- **챕터 매핑**: `chapter-NN ↔ N주차 자료 파일명` 매핑을 director prompt 에 넣음 (현재 chapter-01 PoC 의 매핑이 참고).
- **출판 목차 cross-ref**: `composer` 가 학지사 목차와 cross-ref 함. 자기 교재 목차 PDF·HWP 가 있으면 `Source/textbook-toc.{hwp,pdf}` 에 두고 `prompts/composer/system.md` 의 cross-ref 부분 수정.

### 4. 디자인 시스템 커스터마이징 (선택)

기본 디자인: ppt-korea-policy-navy (한국 정책보고서 미감, KRDS 색 팔레트). 자기 강의 색·폰트 바꾸려면 `prompts/designer/system.md` 의 색 토큰·폰트 위계 표 + `content/chapters/chapter-01/slides/deck.html` 의 `:root { --navy:...; --blue:...; }` 변수.

[design-diversity 카탈로그](https://github.com/epoko77-ai/design-diversity) 의 50+ PPT 팩 중 다른 팩 골라 적용 가능.

### 5. 첫 챕터 PoC 실행

```bash
bash scripts/start-session.sh chapter-01
```

director pane (pane 0) 에 자연어 지시:
```
chapter-01 시작. Source/my-course/my-week-1.pdf 를 base 자료로.
```

대시보드 `http://localhost:8080/dashboard/` 에서 진행 상황 확인.

### 6. 1챕터 검증 후 다중 챕터 직렬

chapter-01 산출물 (`content/chapters/chapter-01/slides/deck.html`) 만족하면 Director 에게:
```
chapter-02 ~ chapter-NN 직렬 진행. 각 챕터 자료 매핑은 [...]
```

자세한 패턴은 [.claude/agents/director.md](./.claude/agents/director.md) 의 "Phase 2" 섹션 참고.

### 알려진 한계 / 차후 개선

- **저작권**: 자기 자료를 `Source/` 에 넣어도 산출 deck.html 에 그대로 인용된 부분의 저작권은 사용자 책임. AI 가 변형해도 fair use 보장 X.
- **챕터 자동 큐 등록**: 현재 director 가 PI 자연어 지시로 STATE.json 에 챕터 등록. 일괄 정의 파일 (`chapters.yaml` 등) 으로 일반화 가능 — PR 환영.
- **다국어**: kordoc 은 한국어 특화. 영문 자료는 일반 PDF 파서로 가능하나 검증 필요.
- **음성/영상**: 현재 정적 HTML/PDF 만. 음성 합성·영상 변환은 Phase 3 후보.

### Contributing

이슈/PR 환영. 단, PI 의 사적 강의 자료 (`Previous_lecture_content/`) 는 `.gitignore` 처리되어 있어 본인 자료를 commit 하지 않도록 주의.

---

## 라이선스

MIT License — [LICENSE](./LICENSE) 참고. 자유 사용·수정·배포 가능, 책임 없음.
