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
| [Previous_lecture_content/](./Previous_lecture_content/) | 4학기치 기존 강의 자료 — **read-only** |
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

## 라이선스

PI(임태형 교수) 본인용 도구. 라이선스 미정.
