# lecture-content-maker-agent-team -- PRD (Product Requirements Document)

> 생성일: 2026-05-25
> 생성 도구: Show Me The PRD (인터뷰 기반)
> 원본 아이디어: `PRD_v1`

---

## 1. 제품 개요

### 한 줄 요약
PI(임태형 교수)의 강의 콘텐츠를 **분해 → 재구성 → 디자인 → 개발**까지 자동화하는 Claude Code 기반 5-에이전트 시스템. Tmux 다중 pane에서 Claude Opus(오케스트레이션) + Codex GPT(분해/구성) + Claude Sonnet(디자인/개발)이 협업.

### 해결하는 문제
- 4학기치(2023-2 ~ 2026-1) 누적된 '교육방법 및 교육공학' 강의자료가 분산·중복·노후화된 상태로 존재
- 매학기 콘텐츠를 수작업으로 재가공하느라 교수의 시간을 잡아먹음
- 일관된 시각 디자인(Mayer 멀티미디어 원리)을 매번 수작업으로 유지하기 어려움
- 학기간 콘텐츠 변화/진화 이력 추적 불가
- 결과적으로 콘텐츠 품질의 학기간 진폭이 큼

### 핵심 가치
- **다중 모델 협업**: Claude Opus(오케스트레이션) + Codex GPT(분해/구성) + Claude Sonnet(디자인/개발)이 한 시스템에서 적재적소 활용
- **장-절-항 구조의 줄글 산출물**: 슬라이드뿐 아니라 추후 전공교재로 업그레이드 가능한 산출 형태
- **자동 검수 루프**: GPT 최신모델로 3회 round-trip 검수, 오탈자/내용 오류 자동 교정
- **이미지 자동 수급**: Wikimedia license-free 검색 + gpt-image-gen fallback으로 슬라이드 시각 자료 자동 충당
- **결정론적 핸드오프**: 파일 시스템 컨벤션 + STATE.json으로 에이전트간 인터페이스 명확화

---

## 2. 사용자

### 주요 사용자
- **누구**: 임태형 교수 1인 (PI, primary user)
- **상황**: 매 학기 '교육방법 및 교육공학' 강의 준비 시점 (학기 시작 4-6주 전)
- **목표**: 12-13챕터 강의 콘텐츠를 빠르게 생산하고 학기간 일관되게 진화시키는 것
- **기술 수준**: 시스템 운영자(개발자 아님). 명령 한 줄로 실행, 대시보드로 확인하는 수준

### 사용자 시나리오
1. PI가 `bash scripts/start-session.sh chapter-01`로 5개 에이전트 tmux 세션을 띄움
2. director pane에 "1주차 챕터: '교육방법 및 교육공학' 도입/개관"이라고 지시
3. decomposer가 `Previous_lecture_content/2026-1/1주차/` 폴더(2026-1 학기 자료)를 파싱해 `decomposed.md` 생성
4. composer가 이를 받아 12-13챕터 구조 안에서 1챕터 분량으로 재구성, 검수 루프 3회 통과
5. designer가 슬라이드 디자인을 `DESIGN.md`로 정의, Mayer 원리 적용
6. developer가 Reveal.js 정적 HTML + decktape PDF 생성
7. PI가 로컬 정적 대시보드에서 진행상황 확인
8. 완성된 `deck.html`을 강의에 사용, `deck.pdf`를 학생에게 배포

---

## 3. 핵심 기능

| 기능 | 설명 | 우선순위 | 복잡도 |
|---|---|---|---|
| Tmux 다중 pane 오케스트레이션 | 5개 에이전트를 별도 pane에 띄우고 director가 send-keys로 지시 | P1 (MVP) | 보통 |
| Decomposer: 기존 자료 파싱 | kordoc + Google Slides 파서로 .md 변환 | P1 (MVP) | 복잡 |
| Composer: 12-13챕터 재구성 | 장-절-항 줄글 .md 작성, 학지사 목차 대조 | P1 (MVP) | 보통 |
| Designer: DESIGN.md 작성 | Mayer 멀티미디어 원리 적용한 시각 설계 | P1 (MVP) | 보통 |
| Developer: Reveal.js 빌드 | deck.md → deck.html + deck.pdf | P1 (MVP) | 간단 |
| 3회 검수 루프 자동화 | composer/designer/developer 각 단계 gpt-5.5-xhigh round-trip | P1 (MVP) | 보통 |
| 이미지 자동 수급 | Wikimedia Commons API + gpt-image-gen fallback | P1 (MVP) | 복잡 |
| PDF auto-export | decktape로 deck.html → deck.pdf | P1 (MVP) | 간단 |
| 발표자 노트 자동 주입 | composed.md 설명문 → reveal.js notes | P1 (MVP) | 간단 |
| 로컬 정적 HTML 대시보드 | STATE.json 5초 폴링 기반 진행상황 시각화 | P1 (MVP) | 간단 |
| 다중 챕터 병렬화 | decomposer/composer 챕터 단위 병렬 | P2 | 복잡 |
| 챕터간 일관성 cross-check | 참고문헌/용어 통일성 검수 | P2 | 보통 |
| 실패 복구 메커니즘 | retry 정책 + manual override 진입 | P2 | 보통 |
| gemini CLI 통합 (0.42.0 이미 설치) | 제3의 모델로 A-B 비교 | P3 | 복잡 |
| 학기간 diff/merge | 2023→2025→2026 변화 추적 | P3 | 복잡 |
| 전공교재 export | .md → epub/pdf 출판물 | P3 | 보통 |
| 실시간 push 대시보드 | Supabase Realtime 또는 SSE | P3 | 복잡 |

---

## 4. 사용자 흐름 (User Flow)

### 핵심 흐름 (MVP, 1챕터 End-to-End)

```
원본 자료 폴더 (Previous_lecture_content/2026-1/1주차/)
    │
    ▼
decomposer (gpt-5.5-medium) ──> decomposed.md ──> 검수 1~3회
    │
    ▼
composer (gpt-5.5-high) ──> composed.md (장-절-항 줄글) ──> 검수 1~3회
    │
    ▼
designer (Sonnet) ──> DESIGN.md (Mayer 원리) ──> 검수 1~3회
    │              │
    │              └──> image-fetcher (Wikimedia + gpt-image-gen)
    │                       │
    ▼                       ▼
developer (Sonnet) ──> deck.md ──> deck.html (Reveal.js) ──> 검수 1~3회
    │
    ▼
decktape ──> deck.pdf
    │
    ▼
STATE.json 업데이트 ──> 로컬 정적 대시보드 표시 (PI 확인)
```

### 상세 흐름 (Phase 1)

1. **트리거**: PI가 `bash scripts/start-session.sh chapter-01` 실행 → tmux 5-pane 세션 부팅
2. **분해**: decomposer pane이 `Previous_lecture_content/2026-1/1주차/*` 읽어 `content/chapters/chapter-01/decomposed.md`로 출력
3. **분해 검수 (round 1-3)**: reviewer(gpt-5.5-xhigh)가 오탈자/내용오류 점검 → 통과해야 다음 단계
4. **재구성**: composer pane이 `decomposed.md` + 학지사 목차(.hwp) 참고해 `composed.md`(장-절-항 줄글) 생성
5. **재구성 검수 (round 1-3)**: 동일 검수 루프
6. **디자인**: designer pane이 `composed.md` 받아 `DESIGN.md`(슬라이드 구조 + 이미지 요구사항) 작성, Mayer 원리 적용
7. **이미지 수급**: image-fetcher 서브태스크가 Wikimedia Commons API 검색 → 없으면 gpt-image-gen으로 생성, `images/`에 저장 + `.meta.json`에 license/attribution 기록
8. **디자인 검수**: 동일 검수 루프 (round 3에는 Mayer 원리 체크 추가)
9. **개발**: developer pane이 `DESIGN.md` + `composed.md` + `images/`로 `deck.md`(reveal.js source) → `deck.html` 빌드
10. **PDF 익스포트**: decktape로 `deck.pdf` 자동 생성
11. **개발 검수**: 동일 검수 루프
12. **완료 보고**: director(Opus 4.7)가 STATE.json 업데이트, 정적 대시보드에 완료 표시

---

## 5. 성공 기준 (Phase 1 MVP)

- [ ] 1개 챕터를 명령 한 줄로 end-to-end 완주 (decomposer → ... → deck.pdf까지 손 안 대고)
- [ ] tmux 세션 재시작에도 STATE.json 기반으로 작업 재개 가능
- [ ] 검수 루프가 3회 안에 수렴 (무한 루프 가드 동작 검증)
- [ ] 이미지 자동 수급 성공률 ≥ 80% (수동 첨부 fallback 정상 동작)
- [ ] 완성된 `deck.html`이 Mayer 원리 체크리스트 통과 (분할 원리, 모달리티 원리)
- [ ] PI가 그 챕터를 실제 강의에 사용 가능한 품질로 판정
- [ ] PDF 출력본이 강의실 디스플레이/학생 배포에 결함 없음
- [ ] 시스템 1회 실행 비용(GPT 호출비 + gpt-image-gen)이 추적 가능

---

## 6. 로드맵

| Phase | 핵심 산출 | 기간 | 상태 |
|---|---|---|---|
| Phase 1 (MVP) | 1챕터 end-to-end PoC + 검수 + 이미지 + PDF | 2-3주 | 시작 전 |
| Phase 2 (확장) | 12-13챕터 1개 학기 완주 + 챕터 병렬화 | 4-6주 (Phase 1 후) | 대기 |
| Phase 3 (고도화) | 다학기 통합 + gemini CLI A-B 비교 + 교재 export | 1-2개월 (Phase 2 후) | 대기 |

상세는 `03_PHASES.md` 참조.

---

## 7. 안 만드는 것 (Out of Scope, Phase 1 기준)

> 이 목록은 Phase 1에서 만들지 않습니다. AI에게 코드를 시킬 때 이 목록을 함께 공유하세요.

- **pptx 산출물** — HTML만. PowerPoint 변환은 Phase 2 이후 별도 검토
- **다중 사용자/조교 협업** — 1인 도구, 인증 레이어 없음
- **외부 호스팅 대시보드** — 로컬 정적 HTML만, 외부 접속 불가
- **gemini CLI 통합 (제3 모델)** — Phase 3로 미룸. Antigravity는 GUI IDE라 CLI 자동화 대상 아님 (spike에서 정정 확인)
- **다중 챕터 병렬화** — Phase 2. PoC는 1챕터만
- **실시간 push 알림** — 폴링 5초로 충분 (Phase 3에서 Realtime 검토)
- **모바일 대시보드 최적화** — 데스크톱 우선
- **다국어 (영문 슬라이드)** — 한국어만
- **음성/영상 자동 생성** — Phase 3 후 별도 검토
- **학생 피드백 수집/분석** — 범위 밖
- **LMS 연동 (Canvas/Moodle)** — 범위 밖

---

## 8. 결정 완료 / Spike 필요 항목

### 8.1 결정 완료 (2026-05-25)
주요 결정 21개는 `README.md`의 "핵심 결정 요약" 섹션 참조. 본 문서는 그 결정사항을 전제로 작성됨.

핵심 정책 (요약):
- **검수 루프 종료**: `issues_count=0`이면 조기 종료, round 3까지 미수렴 시 강제 종료 + manual override
- **Retry 정책**: 지수 백오프 3회 (1s → 10s → 100s)
- **세션 복구**: STATE.json 기반 자동 재개
- **Pane 감지**: sentinel(`# AGENT_DONE_SIGNAL: <task_id>`) + `tmux capture-pane` 폴링
- **PoC 챕터**: 1주차 도입/개관 (2026-1 자료 base)
- **Google Slides 인증**: User OAuth (PI 계정 + refresh token)
- **citations 포맷**: CSL JSON
- **composed.md**: # 장 / ## 절 / ### 항
- **비용**: STATE.json 누적 기록, 한도 없음 (PI 모니터링)
- **Wikimedia license**: 자동 신뢰 + designer round 3 batch 점검

### 8.2 Phase 1 1주차 Spike (실험으로 검증)
- [ ] **모델 ID 매핑**: `gpt-5.5-medium/high/xhigh` ↔ 실제 Codex CLI 모델 ID
- [ ] **kordoc 호환성**: 한국어/한자 처리 범위 + 마지막 업데이트
- [ ] **decktape ↔ Reveal.js 5.x 호환성**: PDF 변환 깨짐 여부
- [x] **Antigravity CLI** ⚠️ 정정 완료 — Antigravity는 GUI IDE, CLI 없음. Phase 3 도구는 **`gemini` CLI 0.42.0** (이미 설치). spike/RESULTS.md 참조.

### 8.3 운영 중 보정 (Phase 1 종료 후)
- [ ] Wikimedia license 자동 판단의 실제 정확도 측정 → 자동/수동 비율 정책 조정
- [ ] 검수 비용 누적 데이터 기반 Phase 2 월간 한도 산정
- [ ] composer의 12-13챕터 매핑 정확도 검증
