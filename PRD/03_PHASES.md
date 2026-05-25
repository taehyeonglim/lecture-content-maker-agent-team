# lecture-content-maker-agent-team -- Phase 분리 계획

> 한 번에 12-13챕터를 다 만들면 시스템 버그가 12배로 증폭됩니다.
> Phase별로 나눠서 각각 "진짜 동작하는 산출물"을 만듭니다.

---

## Phase 1: MVP — 1챕터 End-to-End PoC (2-3주)

### 목표
**2026-1 학기 자료를 base로, 1주차 도입/개관 챕터를 완전 자동화된 파이프라인으로 통과**시킨다.
끝나면 그 챕터의 reveal.js 슬라이드덱(`deck.html` + `deck.pdf`)을 실제 강의에 사용 가능.

### Phase 1 첫 3-5일: 1주차 Spike (2026-05-25 ✅ 완료)

상세는 [`spike/RESULTS.md`](../spike/RESULTS.md). 본격 구현 즉시 진입 가능.

- [x] **모델 ID 매핑**: `codex exec --model gpt-5.5 -c model_reasoning_effort=<medium|high|xhigh>`로 매핑됨. 검증 완료.
- [x] **kordoc 호환성**: v2.9.0 (2026-05-24), HWP/HWPX/PDF/Office 모두 지원. `npx -y kordoc setup`으로 MCP+CLI 통합.
- [x] **decktape ↔ Reveal.js 5.x**: 4슬라이드 한국어 PDF 변환 성공. `decktape reveal <url> <out.pdf>`.
- [ ] **nexu-io/open-design 분석**: designer 에이전트 구현 시 진행 (DESIGN.md 스키마 결정).
- [ ] **Antigravity → gemini CLI 정정**: PRD_v1의 "Antigravity CLI" 표기는 부정확. 실제는 gemini 0.42.0 CLI 사용 (Phase 3). PRD 본문 정정 반영됨.

### 기능
- [ ] 5에이전트 시스템 프롬프트 정의 (`.claude/agents/{director,decomposer,composer,designer,developer}.md`)
- [ ] tmux 세션 부팅 스크립트 (`scripts/start-session.sh`) — director + 4 worker pane
- [ ] tmux send-keys 헬퍼 (`scripts/send-to-pane.sh`)
- [ ] sentinel 감지 메커니즘 (`# AGENT_DONE_SIGNAL` + `tmux capture-pane` 폴링)
- [ ] **decomposer**:
    - kordoc 통합 (`pip install` 또는 git submodule)
    - Google Slides API 인증 + 정확 파싱
    - 한국어/한자 처리
    - 출력: `content/chapters/chapter-01/decomposed.md`
- [ ] **composer**:
    - 입력: `decomposed.md` + 학지사 목차(.hwp 파싱)
    - 출력: `composed.md` (장-절-항 줄글, # / ## / ### 마크다운)
    - 12-13챕터 매핑 로직 (PoC는 1챕터만, 매핑 로직은 Phase 2 대비)
- [ ] **designer**:
    - 입력: `composed.md`
    - 출력: `DESIGN.md` (슬라이드 구조 명세)
    - Mayer 멀티미디어 원리 적용 (분할 원리, 모달리티 원리)
    - 이미지 요구사항 명세 ("ADDIE 모형 흐름도 - 가로 5단계 배치" 등)
- [ ] **developer**:
    - 입력: `DESIGN.md` + `composed.md` + `images/`
    - 출력: `deck.md` (Reveal.js source) → `deck.html` (정적 빌드)
    - HTML만 (pptx 변환 금지)
- [ ] **3회 검수 루프** (composer/designer/developer 각 단계):
    - reviewer = gpt-5.5-xhigh
    - Round 1: 오탈자, 문법, 한국어 자연스러움
    - Round 2: 내용 정확성, 인용 출처, 사실 오류
    - Round 3: 일관성, 학습 흐름, Mayer 원리(designer/developer 한정), **이미지 license 단체 점검(designer round 3)**
    - **종료 조건**: `issues_count=0`이면 조기 종료 (다음 단계로). round 3까지 미수렴 시 강제 종료 + manual override 진입
- [ ] **Retry 정책** (에이전트 실패 시):
    - 지수 백오프 3회: 1s → 10s → 100s
    - 3회 모두 실패 시 STATE.json에 `error_message` 기록 후 manual override
- [ ] **세션 복구**:
    - `start-session.sh` 재실행 시 STATE.json 읽고 마지막 `in_progress` task부터 이어서 진행
    - 완료된 task는 skip
    - idempotency 설계 필수 (중복 쓰기 방지)
- [ ] **비용 추적**:
    - 각 GPT/Sonnet 호출 시 input/output 토큰 × 단가 계산해 STATE.json `task.cost_usd`에 누적
    - 한도 없음 (PI 모니터링), 대시보드에 `cumulative_cost_usd` 실시간 표시
- [ ] **이미지 자동 수급**:
    - Wikimedia Commons API 검색 (license filter: CC BY, CC BY-SA, public domain만)
    - 없으면 gpt-image-gen으로 생성
    - 메타데이터 `{path}.meta.json`에 license + attribution 기록
- [ ] **PDF auto-export**:
    - decktape로 `deck.html` → `deck.pdf`
    - 슬라이드 애니메이션은 PDF에서 깨질 수 있음 → 정적 슬라이드만 PDF 적용
- [ ] **발표자 노트 자동 주입**:
    - composed.md의 단락별 설명문 → reveal.js `<aside class="notes">` 자동 변환
- [ ] **STATE.json atomic 업데이트** (director만 write)
- [ ] **로컬 정적 HTML 대시보드**:
    - `dashboard/index.html` (Tailwind CDN)
    - `dashboard/poll.js` (5초 폴링 fetch)
    - 챕터 진행도 바, 에이전트 상태 등불, 최근 활동 로그
    - `python3 -m http.server -d dashboard 8000` 또는 file:// 직접 열기

### 데이터
- Chapter (인스턴스 1)
- AgentTask (~ 4-12개, 챕터 1개 × 4역할 × 재시도)
- ReviewRound (최대 36개, 4단계 × 3round × 추가 retry는 별도)
- Asset (이미지 + 참고문헌, 챕터당 ~10-30개)
- SystemState (STATE.json)
- 파일 레이아웃: `content/chapters/chapter-01/...`

### 인증
- **로그인 없음** (1인 로컬 도구, OS 사용자 권한이 인증)
- 외부 API:
    - Codex CLI: OAuth (`codex auth login`)
    - Claude Code: OAuth (`/login`)
    - Google Slides API: service account JSON 또는 user OAuth
    - Wikimedia: 익명 API (User-Agent 헤더는 매너상 필수)
    - gpt-image-gen: API 키 (`.env`)

### "진짜 제품" 체크리스트
- [ ] **명령 한 줄로 end-to-end**: `bash scripts/start-session.sh chapter-01` 후 수동 개입 0
- [ ] **세션 복구**: tmux 죽었다 다시 띄워도 STATE.json 기반 작업 재개
- [ ] **검수 수렴**: 1챕터를 3회 돌렸을 때 모두 3 round 안에 수렴
- [ ] **이미지 라이선스 추적**: 모든 이미지에 `.meta.json` 존재
- [ ] **실제 강의 사용 가능 품질**: PI가 그 챕터를 OK 판정
- [ ] **모킹 없음**: 모든 API 호출은 진짜 (gpt-5.5, sonnet, Wikimedia 진짜 호출)
- [ ] **비용 추적 가능**: 1챕터 1회 실행 비용 합산 가능

### Phase 1 시작 프롬프트

```
이 PRD를 읽고 Phase 1을 구현해주세요.
@PRD/01_PRD.md
@PRD/02_DATA_MODEL.md
@PRD/04_PROJECT_SPEC.md

Phase 1 범위:
- 5에이전트 시스템 프롬프트 정의 (.claude/agents/)
- tmux 5-pane 세션 부팅 스크립트
- decomposer/composer/designer/developer 파이프라인 (1챕터만)
- 3회 검수 루프 (gpt-5.5-xhigh) + 무한루프 가드
- 이미지 자동 수급 (Wikimedia + gpt-image-gen fallback)
- PDF auto-export (decktape)
- 발표자 노트 자동 주입
- STATE.json (atomic write) + 로컬 정적 HTML 대시보드

반드시 지켜야 할 것:
- 04_PROJECT_SPEC.md의 "절대 하지 마" 목록 준수
- 1챕터 PoC 범위 지키기 (다중 챕터/학기는 Phase 2)
- 검수 루프 무한 가드 (round 3 강제 종료 + manual override)
- STATE.json은 atomic write (.tmp → mv)
- 모든 외부 API 키는 .env에 (코드에 직접 X)
- pptx 변환 금지, HTML/PDF만
- chapter 수는 1로 고정 (Phase 1)
```

### Phase 1 종료 후 정리
- 실제 1챕터를 강의에 사용해보고 회고
- 각 에이전트의 프롬프트/모델/effort 튜닝 포인트 기록
- composer의 12-13챕터 매핑 로직 검증 (Phase 2 자동화의 토대)
- 1회 실행 비용 정산 → Phase 2 월간 한도 산정 근거

---

## Phase 2: 확장 — 1개 학기 완주 (4-6주)

### 전제 조건
- Phase 1 1챕터 PoC가 안정 통과 (반복 3회 모두 성공)
- composer 프롬프트가 사람 검토에서 만족 판정
- 시스템 1회 실행 비용이 예측 가능 범위

### 목표
2026-1 자료를 base로 **12-13챕터 전체 자동 제작**, 2026-2 학기 강의에 즉시 사용 가능한 1학기분 콘텐츠 확보.

### 기능
- [ ] composer 강화:
    - 학지사 목차(.hwp) 자동 파싱
    - 4학기 자료 cross-reference로 12-13챕터 자동 추천
    - 챕터간 선후관계 그래프 작성
- [ ] **다중 챕터 병렬화**:
    - decomposer/composer: 챕터별 완전 병렬 (서로 독립)
    - designer/developer: 챕터간 직렬 (디자인 일관성 위해)
    - tmux pane 동적 생성 (1챕터당 4 pane × N챕터 → 너무 많으면 풀 기반)
- [ ] **director 강화**:
    - 챕터별 grid view 대시보드 (12-13챕터 진행도 동시 표시)
    - 챕터 의존성 그래프 시각화
- [ ] **챕터간 cross-check**:
    - 참고문헌 중복/누락 검사
    - 용어 일관성 (예: "교수 설계" vs "수업 설계" 통일)
    - 챕터간 선후관계 의존성 (1챕터에서 정의한 용어를 7챕터에서 가정)
    - Mayer 원리 일관성 (디자인 톤 통일)
- [ ] **실패 복구**:
    - retry 정책 분기 (network error vs model error vs content error)
    - manual override 모드 (특정 챕터만 손으로 수정 후 재진입)
    - 부분 재실행 (예: 7챕터 designer만 다시)
- [ ] **Course + SourceArtifact 엔티티 추가**:
    - 학기 단위 그룹핑
    - 학기별 자료 인덱싱 (Phase 3 다학기 통합 준비)
- [ ] **이미지 통합 인덱스** (`content/assets-index.json`):
    - 동일/유사 이미지 재사용 감지 (perceptual hash)
    - 라이선스 일괄 점검
    - 챕터간 이미지 출처 통일

### 추가 데이터
- Course 엔티티 (학기 단위)
- SourceArtifact 엔티티 (`Previous_lecture_content/*` 파일)
- Chapter 12-13 인스턴스
- 챕터별 디렉토리 12-13개
- `content/assets-index.json` (이미지 통합 인덱스)

### 통합 테스트
- Phase 1의 1챕터가 Phase 2 시스템에서도 정상 빌드되는지 회귀 테스트
- 12챕터 동시 진행 시 STATE.json 락 충돌 없는지 (atomic write 검증)
- tmux pane이 12배 늘었을 때 send-keys race condition 발생 여부
    - 발생 시 **Python + libtmux 마이그레이션 트리거** (Phase 2 종료 전)
- 비용: 12-13챕터 × (4 agent + 3×3 review) → 실제 누적 비용 측정 후 Phase 3 한도 결정

---

## Phase 3: 고도화 — 다학기 통합 + 제3모델 (1-2개월)

### 전제 조건
- Phase 2가 2026-2 학기 1학기분 운영을 마치고 회고 완료
- 비용/실패율/품질 지표가 stable

### 목표
4학기 자료(2023-2 ~ 2026-2) 통합 → 학기간 변화 추적 → 전공교재 export.
gemini CLI로 모델 다양성 확보 (Antigravity는 GUI IDE라 CLI 자동화 대상 아님 — PRD_v1 정정).

### 기능
- [ ] **gemini CLI 통합** (0.42.0 이미 설치):
    - OAuth 인증 + 사용 가능 모델 enumerate (`gemini -p "..." -m gemini-2.5-pro`)
    - `--output-format json`으로 구조화된 출력 수집
    - 실패 시 fallback 정책 (codex로 회귀)
- [ ] **A-B 모델 비교**:
    - composer 출력 (codex gpt-5.5 vs gemini) 자동 비교 + diff
    - 더 좋은 결과 선택 기준 rubric 정의
    - PI가 최종 선택권 (자동 결정 X, 추천만)
- [ ] **학기간 diff/merge**:
    - 같은 챕터의 2023→2025→2026 변화 추적
    - 변화 이유 자동 추론 (커리큘럼 업데이트? 새 연구? 학생 피드백?)
    - "이번 학기 추가된 내용" 자동 highlight
- [ ] **전공교재 export**:
    - `composed.md` 12-13챕터 통합 → epub
    - `composed.md` 통합 → pdf (Pandoc 또는 LaTeX 경로)
    - 표지/판권/색인 자동 생성
- [ ] **실시간 push 대시보드** (선택):
    - Supabase Realtime 또는 SSE
    - 모바일 접근 (PI가 외출 중에도 확인)
    - 또는 정적 대시보드 유지 + ngrok 정도
- [ ] **알림 연동** (선택):
    - 슬랙/디스코드 webhook
    - 챕터 완료/실패 시 push
    - 비용 한도 임박 시 알림

### 주의사항
- **gemini CLI 모델 enumerate** — Phase 3 진입 전 사용 가능한 모델 ID 확정 (gemini-2.5-pro/flash 등)
- **gpt-image-gen 누적 비용** — Phase 3에서 월간 한도 설정 (예: 200달러/월)
- **학기간 diff는 대용량 텍스트 비교** — GPT 컨텍스트 한도 주의, 챕터별로 분할 처리
- **전공교재 export는 별도 도메인** — 출판사 매뉴얼 (학지사 등)과의 정합성 확인 필요

---

## Phase 로드맵 요약

| Phase | 핵심 산출 | 기간 | 상태 |
|---|---|---|---|
| Phase 1 (MVP) | 1챕터 end-to-end PoC + 검수 + 이미지 + PDF | 2-3주 | 시작 전 |
| Phase 2 (확장) | 12-13챕터 1학기 완주 + 챕터 병렬화 + 일관성 cross-check | 4-6주 (Phase 1 후) | 대기 |
| Phase 3 (고도화) | 다학기 통합 + gemini CLI A-B 비교 + 교재 export | 1-2개월 (Phase 2 후) | 대기 |

각 Phase 끝에는 **사용 가능한 산출물**이 남습니다:
- Phase 1 끝: 1개 챕터 강의 가능
- Phase 2 끝: 1학기 강의 가능
- Phase 3 끝: 전공교재 출판 가능 (장기 자산)
