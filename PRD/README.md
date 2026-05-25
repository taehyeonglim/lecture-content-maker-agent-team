# lecture-content-maker-agent-team -- 디자인 문서

> Show Me The PRD로 생성됨 (2026-05-25)
> 원본 아이디어: 프로젝트 루트의 `PRD_v1`
> 결정 라운드 완료: 2026-05-25 (21개 항목 확정, 4개 spike 항목 남음)

## 프로젝트 한 줄 요약

PI(임태형 교수)의 강의 콘텐츠를 **분해 → 재구성 → 디자인 → 개발**까지 자동화하는 Claude Code 기반 5-에이전트 시스템. Tmux 다중 pane에서 Claude Opus(director) + Codex GPT(decomposer/composer) + Claude Sonnet(designer/developer)이 협업하여 1챕터당 reveal.js 슬라이드덱 + PDF를 자동 산출.

## 문서 구성

| 문서 | 내용 | 언제 읽나 |
|---|---|---|
| [01_PRD.md](./01_PRD.md) | 뭘 만드는지, 누가 쓰는지, 성공 기준, Out of Scope | 프로젝트 시작 전, 의사결정 시 |
| [02_DATA_MODEL.md](./02_DATA_MODEL.md) | 4엔티티(Chapter/AgentTask/ReviewRound/Asset) + STATE.json + 파일 레이아웃 | 파일/데이터 구조 설계, 핸드오프 포맷 결정 시 |
| [03_PHASES.md](./03_PHASES.md) | Phase 1(1챕터 PoC) / Phase 2(1학기 완주) / Phase 3(다학기 통합) 상세 계획 | 개발 순서 정할 때, Phase 시작 시 |
| [04_PROJECT_SPEC.md](./04_PROJECT_SPEC.md) | 기술 스택, 에이전트 행동 규약, 절대 하지 마 / 항상 해, 환경변수 | AI에게 코드 시킬 때마다 (필수 첨부) |

---

## 핵심 결정 요약 (2026-05-25 확정)

### A. 시스템/런타임

| 결정 | 값 |
|---|---|
| 오케스트레이션 | Tmux 다중 pane + 멀티 CLI |
| Director | Claude Code Opus 4.7 (max effort) |
| Decomposer | Codex CLI / gpt-5.5-medium |
| Composer | Codex CLI / gpt-5.5-high |
| Designer | Claude Code Sonnet 최신 |
| Developer | Claude Code Sonnet 최신 |
| Reviewer | Codex CLI / gpt-5.5-xhigh |
| tmux 자동화 | 순수 bash + tmux send-keys (Phase 2에서 Python+libtmux 마이그레이션 옵션) |
| **Pane 완료 감지** | **sentinel(`# AGENT_DONE_SIGNAL: <task_id>`) + `tmux capture-pane` 폴링 (2-3초)** |
| **Retry 정책** | **지수 백오프 3회 (1s → 10s → 100s), 실패 시 manual override** |
| **세션 복구** | **STATE.json 기반 자동 재개 (마지막 task부터, idempotency 설계 필수)** |
| 인증(시스템) | 없음 (로컬 1인 도구, OS 사용자 권한) |

### B. 산출물 / 컨벤션

| 결정 | 값 |
|---|---|
| 슬라이드 엔진 | Reveal.js 5.x → decktape로 PDF |
| **composed.md 컨벤션** | **# 장 / ## 절 / ### 항 (표준 마크다운 위계)** |
| **citations 포맷** | **CSL JSON (Citation Style Language) — Zotero/Pandoc 호환** |
| **DESIGN.md 스키마** | **nexu-io/open-design 분석 후 채택/각색 (1주차 spike)** |
| 상태 관리 | 파일 시스템 + STATE.json (atomic write) |
| 대시보드 | 로컬 정적 HTML + Tailwind CDN + 5초 폴링 |

### C. 외부 통합

| 결정 | 값 |
|---|---|
| **Google Slides 인증** | **User OAuth (PI 계정, refresh token `.env` 저장)** |
| **Wikimedia license** | **자동 신뢰 + designer round 3 검수 시 license 단체 점검** |
| 이미지 수급 | Wikimedia Commons API 우선 → 없으면 gpt-image-gen |

### D. Phase 1 범위 / 정책

| 결정 | 값 |
|---|---|
| **PoC 챕터** | **1주차 · 도입/개관 챕터 ('교육방법 및 교육공학' 개관)** |
| **Base 학기 자료** | **2026-1 학기 자료** |
| Phase 1 부가기능 | 이미지 자동 수급 + 3회 검수 루프 + PDF auto-export |
| **검수 루프 종료** | **`issues_count=0`이면 조기 종료, round 3까지 미수렴 시 강제 종료 + manual override** |
| **비용 추적** | **STATE.json에 task별 누적 비용 기록 (한도 없음, PI 모니터링)** |
| gemini CLI 통합 | Phase 3로 미룸 (Antigravity는 GUI IDE라 CLI 자동화 대상 아님, spike에서 정정 확인) |

---

## Phase 1 1주차 Spike 결과 (2026-05-25 ✅ 완료)

> 상세는 [`spike/RESULTS.md`](../spike/RESULTS.md) 참조.

- [x] **모델 ID 매핑** ✅ — `codex exec --model gpt-5.5 -c model_reasoning_effort=<medium|high|xhigh> "..."`로 매핑 확인. `~/.codex/config.toml`에 이미 `gpt-5.5` 명시되어 있음.
- [x] **kordoc 호환성** ✅ — v2.9.0 (2026-05-24 어제 릴리즈). HWP3/5/HWPX/HWPML/PDF/Office 모두 지원. MCP+CLI 둘 다. `npx -y kordoc setup`으로 30초 설치.
- [x] **decktape ↔ Reveal.js 5.x** ✅ — 4슬라이드 한국어 포함 PDF 정상 변환(82KB, PDF 1.7). `decktape reveal <url> <out.pdf>` 한 줄로 동작. 샘플: `spike/sample-revealjs/`.
- [x] **Antigravity CLI 검증** ⚠️ **정정** — Antigravity는 GUI IDE이고 **CLI 없음**. Phase 3에서 쓸 도구는 **`gemini` CLI 0.42.0**(이미 설치). PRD_v1의 "Antigravity CLI" 표기는 부정확, 실제는 gemini CLI.

### Phase 1 즉시 시작 가능 ✅
- 필요한 모든 도구(codex, claude, gemini, tmux, jq, node, npm, python3, gh, decktape)가 설치되어 있음.
- codex 인증 완료. 본 프로젝트 첫 codex 실행 시 trust 프롬프트만 한 번 처리하면 됨.
- 다음 단계는 spike 결과를 04_PROJECT_SPEC.md 본문에 반영하고 `.claude/agents/` + `scripts/` 구현 진입.

---

## 다음 단계

### 옵션 A: Claude Code로 Phase 1 직접 시작
새 Claude Code 세션에서 `03_PHASES.md`의 "Phase 1 시작 프롬프트"를 복사.

### 옵션 B: pumasi로 5에이전트 병렬 개발 ⭐
```
/pumasi
@PRD/01_PRD.md @PRD/02_DATA_MODEL.md @PRD/03_PHASES.md @PRD/04_PROJECT_SPEC.md

5에이전트(.claude/agents/{director,decomposer,composer,designer,developer}.md)와 핵심 스크립트(start-session.sh, send-to-pane.sh, run-review.sh, fetch-image.sh, export-pdf.sh)를 병렬 개발해주세요. Phase 1 범위 한정 (1주차 도입/개관 챕터, 2026-1 base). 04_PROJECT_SPEC.md의 DO NOT 목록 엄격 준수.
```

### 옵션 C: goaljaby로 골(goal) 기반 장기 세션 진입
```
/goaljaby PRD/
```
→ VALIDATION/RECOVERY/PLAN/PROGRESS 문서 5종 자동 생성 후 /goal 세션 시작.

---

## 추천 실행 순서

1. **0주차 (오늘)**: 본 PRD 최종 검토 완료. 다음 단계 옵션 선택.
2. **1주차 spike (3-5일)**: 위의 4개 spike 항목 실험 → 결과를 PRD에 반영.
3. **1-2주차**: pumasi로 5에이전트 + 스크립트 병렬 개발 → 1주차 도입 챕터 통과 시도.
4. **3주차**: 검수 루프 / 이미지 자동 수급 / PDF export 통합 → Phase 1 종료, 회고.

---

## 참고 자료

- [chrisryugj/kordoc](https://github.com/chrisryugj/kordoc) — 한국어 문서 파서 (PRD_v1 명시)
- [nexu-io/open-design](https://github.com/nexu-io/open-design) — 디자인 시스템 참고 (PRD_v1 명시)
- Richard Mayer, "Multimedia Learning" — 슬라이드 디자인 원리
- 학지사 "교육방법 및 교육공학" 목차 (`Previous_lecture_content/목차_학지사_교육방법및교육공학.hwp`) — 12-13챕터 매핑 기준
- [CSL JSON 스키마](https://docs.citationstyles.org/en/stable/specification.html) — 인용 포맷

## 도구

- **Claude Code (Opus 4.7)** — director, designer, developer
- **Codex CLI (gpt-5.5)** — decomposer, composer, reviewer
- **tmux** — 다중 pane 오케스트레이션
- **Reveal.js 5.x** — 슬라이드덱 빌드
- **decktape** — PDF auto-export
- **jq** — STATE.json 조작

## 라이선스

PI(임태형 교수) 본인용 도구. 라이선스 미정.
