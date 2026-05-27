# lecture-content-maker-agent-team — 세션 인계 (2026-05-27)

> Claude Code 5-에이전트 시스템이 PI(임태형 교수) 의 강의 자료를 자동으로
> Reveal.js 슬라이드 + PDF 로 변환. **chapter-01~10 모두 `developed` 도달**.
> Phase 2 (다중 챕터 직렬) 완료, 다음 사람·세션이 이어받을 수 있음.

---

## 1. 현재 상태 한 눈에

```
chapter-01 [developed] ✅ — PoC (1주차 도입/개관), 6 이미지 + 19 슬라이드
chapter-02 [developed] ✅ — 2주차 교육과 기술의 관계
chapter-03 [developed] ✅ — 3주차 2022 개정 교육과정 + AI디지털교육
chapter-04 [developed] ✅ — 4주차 체제적 교수설계
chapter-05 [developed] ✅ — 5주차 수업의 구성과 절차
chapter-06 [developed] ✅ — 6주차 협동학습전략
chapter-07 [developed] ✅ — 7주차 동기유발전략
chapter-08 [developed] ✅ — 8주차 멀티미디어설계원리
chapter-09 [developed] ✅ — 9주차 AI디지털교과서의 시대
chapter-10 [developed] ✅ — 10주차 AI와 교육이 만나는 방법
```

8시간 자동 가동 후 도달. 산출물은 `content/chapters/chapter-NN/` 로컬 (`.gitignore`).

---

## 2. PI 의 핵심 정책 (반드시 따라야 함)

이번 세션 동안 PI 가 명시한 결정들 — `memory/` 에 박혀 있어 자동 학습되지만 빠른 참조용:

### 2.1 이미지 정책
- **모든 이미지는 codex `image_gen.imagegen` 으로 생성** (ChatGPT subscription auth, OPENAI_API_KEY 별도 발급/결제 불필요).
- **인물 사진만 Wikimedia** 검색 우선 (실패 시 codex 폴백).
- inline SVG 사용 금지 (이전 세션에서 시도했다가 폐기).
- 표지 사진은 `cover-photo` 우상단 ornament 또는 생략.

### 2.2 디자인 시스템 (ppt-korea-policy-navy)
- 색 토큰: navy `#0B2C5C` / blue `#1B66C9` / red `#E03B3B` / green `#1F9D57` / surface `#E8F1FB` / border `#C5D2E3`
- 폰트: Pretendard 단일.
- **본문 44px 최저** (강의실 뒷자리 가독성 — PI 가 32→40→44 두 번 키우라 요청).
- 헤더는 그대로: 표지 120 / 절제목 100 / 마무리 68 / 슬라이드 헤딩 48.
- 표지 `.cover-meta` (강의자 이름/소속) 박스 **금지** ("의미 없다" PI 명시).

### 2.3 레이아웃 — 5 본형 + 4 변형 (이외 금지)
**본형**:
- `layout-cover` — 표지
- `layout-section` — 절 구분
- `layout-text` — 본문 텍스트 위주
- `layout-image` — 좌 텍스트 + 우 이미지 (변형 `layout-image-wide` 풀폭)
- `layout-table` — 비교표

**변형 (text 변형)**:
- `layout-flex-2col` — 좌·우 2열 비교
- `layout-flow-cards` — 가로 4단계 흐름 카드
- `layout-closing` — 마무리 인용 (cover 변형)

### 2.4 figure 세로 중앙 정렬 ⚠️
PI 명시: "이미지는 항상 정렬이 중요해. 높이적으로 중앙에 위치하도록 항상 해야해."

**3 가지 선행 조건 모두 필수** (chapter-01 PoC 5-cycle 디버깅 학습):
```css
1. section.layout-image { height: 100%; }           /* 부모 명시 */
2. .body-area { height: calc(100% - 헤더 - 패딩); }  /* Reveal scaled section 안 implicit 인식 실패 회피 */
3. section.layout-image .body-area { display: flex; align-items: center; }
   section.layout-image .body-area .copy { align-self: stretch; }
```

### 2.5 표지·마무리는 캔버스 정확 중앙
본문 슬라이드는 헤더 아래 영역 중앙, **표지/마무리는 캔버스 전체(1920×1080) 정확 중앙**.

```css
/* layout-cover */
.cover-content { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); }

/* layout-closing */
.body-area { position: absolute; top: 0; left: 0; right: 0; bottom: 0; display: flex; justify-content: center; align-items: center; }
```

### 2.6 디버깅 절차
시각 확인 채널(스크린샷 등) 없을 때 **추측 fix 반복 금지**. 진단 outline 박스로 ground truth 우선:
```css
section.layout-image .body-area { outline: 4px dashed red; }
section.layout-image .body-area .copy { outline: 3px dashed orange; }
section.layout-image .body-area figure { outline: 3px dashed blue; }
```
chapter-01 의 5-cycle 디버깅 후 1 회 진단으로 해결한 실증 사례.

---

## 3. 5 에이전트 시스템 가동

### tmux 세션 시작 (PI 터미널에서)
```bash
bash scripts/start-session.sh
```

5-pane 그리드:
- pane 0: **director** (Claude Opus 4.7 — PI 가 자연어 지시)
- pane 1: **decomposer** (Sonnet — kordoc 로 .gslides 파싱)
- pane 2: **composer** (Sonnet — 학지사 목차 cross-ref)
- pane 3: **designer** (Sonnet — DESIGN.md 작성)
- pane 4: **developer** (Sonnet — deck.html 작성)

각 워커는 `--dangerously-skip-permissions --effort high`.

### Director 에게 지시 (예시)
```
chapter-01 진행 상태 확인.

chapter-NN 부터 chapter-MM 까지 직렬 진행. 자료 매핑은 [...]

특정 챕터 다시 처음부터.
```

### 자동 워크플로 (한 챕터 = 약 15-25분)
```
STATE.json 에 chapter 등록 (atomic write)
  → decomposer → content/chapters/chapter-NN/decomposed.md
  → composer → composed.md
  → designer → DESIGN.md + image_fetch_requests 표
  → bash scripts/run-image-fetch.sh chapter-NN (codex image_gen.imagegen batch)
  → developer → slides/deck.html (chapter-01 패턴 참조)
  → bash scripts/run-review.sh chapter-NN <role> 3 회 (issues=0 조기 종료)
  → STATE.json done 갱신, 다음 챕터
```

---

## 4. 대시보드

```bash
python3 -m http.server -d . 8080
```

`http://localhost:8080/dashboard/` — chapters 진행 상태 카드 + 토큰/비용 chart + deck.html 라이브 미리보기 iframe (5초 polling).

---

## 5. 다음 단계 옵션 (PI 결정 대기)

### A. 검증·배포
- [ ] 10 챕터 deck.html 시각 검수 (대시보드 iframe 또는 새창)
- [ ] `bash scripts/export-pdf.sh chapter-NN` 로 PDF batch 변환 (decktape 1920×1080)
- [ ] Reveal.js notes 채우기 — `<aside class="notes">` 발표자 노트 자동 생성

### B. 자료 확장
- [ ] chapter-11~13 자료 추가 (현재 자료 폴더에 없음 — PRD 의 12-13 챕터 목표 달성)
- [ ] 학지사 목차 cross-ref 강화 — composer 의 chapter-내용 ↔ 학지사 책 mapping

### C. 시스템 개선
- [ ] history rewrite (`git filter-repo`) — Previous_lecture_content 가 history 에 남음
- [ ] `chapters.yaml` 같은 일괄 정의 파일 — 현재 director 가 PI 자연어로 매핑
- [ ] 음성 합성·영상 변환 (Phase 3 후보)
- [ ] 다국어 지원 (kordoc 은 한국어 특화)

### D. 새 강의로 일반화
- [ ] 다른 사용자가 자기 강의로 사용 — README "다른 사용자용" 섹션 참고
- [ ] `Source/` 폴더에 자기 자료 → director 자연어 지시 → 동일 파이프라인

---

## 6. 핵심 파일·디렉토리

| 위치 | 역할 |
|---|---|
| `.claude/agents/{director,decomposer,composer,designer,developer}.md` | 5 에이전트 시스템 프롬프트 |
| `prompts/{designer,developer}/system.md` | 워커 작업 가이드 (디자인 시스템, CSS 규칙 박힘) |
| `scripts/start-session.sh` | tmux 5-pane 세션 부팅 |
| `scripts/send-to-pane.sh` | tmux send-keys + sentinel |
| `scripts/run-review.sh` | reviewer 3 회 검수 루프 |
| `scripts/fetch-image.sh` | codex image_gen.imagegen + Wikimedia fetch |
| `scripts/run-image-fetch.sh` | DESIGN.md image_fetch_requests 표 batch 처리 |
| `scripts/export-pdf.sh` | decktape Reveal.js → PDF |
| `STATE.json` | 시스템 상태 (atomic write, director only) |
| `dashboard/index.html` | 정적 대시보드 (5초 polling) |
| `content/chapters/chapter-NN/` | 산출물 (`.gitignore` — local only) |
| `~/.claude/projects/.../memory/*.md` | 자동 학습 memory (image-policy, codex-cli-capabilities, deck-css-patterns 등) |

---

## 7. 의존성

| 도구 | 버전 | 셋업 |
|---|---|---|
| codex CLI | 0.133.0+ | `codex login` (ChatGPT subscription) — `image_gen.imagegen` tool 포함 |
| claude (Claude Code) | 2.x | `claude /login` (Anthropic subscription) |
| tmux | 3.x | `brew install tmux` |
| jq | 1.x | `brew install jq` |
| node | 20+ | `brew install node` |
| python3 | 3.x | macOS 기본 |
| decktape | npm 글로벌 | `npm install -g decktape` |
| kordoc | v2.9.0+ MCP | `npx -y kordoc setup` |

**비용**: ChatGPT Pro $200/월 (codex + image_gen) + Claude Max $100+/월 (director/워커). 두 subscription 으로 모든 토큰·이미지 비용 흡수, 별도 API key 결제 X.

---

## 8. 알려진 함정 (PI 와 함께 발견)

1. **codex `image_gen.imagegen`** prompt 에 `"Use image_gen.imagegen tool (not Python/PIL)"` 명시 안 하면 codex agent 가 PIL/Pillow Python 코드로 처리. 진짜 이미지 생성 강제 필요.
2. **Reveal.js `theme/white.css`** 가 `section img` 에 `4px border + 15px margin + shadow` 강제. KRDS 디자인과 충돌 — `<style>` 최상단에 reset 블록 박을 것.
3. **figure 세로 중앙 정렬**의 3 가지 선행 조건 (Section 2.4) 중 하나라도 빠지면 무력. chapter-01 에서 5-cycle 디버깅 후 발견.
4. **iframe cache** — 대시보드 5초 mtime polling 이 일부 webkit/proxy 에서 stale. 시크릿 창 또는 Cmd+Shift+R 로 검증.
5. **STATE.json atomic write** — `STATE.json.tmp → mv STATE.json` 필수. 직접 덮어쓰기 금지 (race condition).
6. **chapter-01 산출물을 reference template** — 다음 챕터의 designer/developer 가 학습. 큰 변경은 신중히.

---

## 9. 이번 세션 commits (참고)

```
53462fd 공개 repo 정리 — PI 사적 자료 제거 + MIT LICENSE + 다른 사용자 가이드
8b9b707 Phase 2 진입 — chapter-02~10 직렬 모드 활성화
2efb9ef 본문 폰트 +4px 추가 상향 — 44px 최저 (헤더는 그대로)
9e15c69 폰트 전체 1.25x 상향 — 본문 40px 최저
ef76357 표지 cover-meta 금지 + memory 패턴 박음
e8579b9 fix 완료 — section.layout-image height: 100% (5-cycle 디버깅 학습)
04da98e .body-area 명시 height 필수 — Reveal scaled section flex 인식 실패 fix
61b6df8 이미지 세로 중앙: grid → flex 변경
22e496c grid-template-rows: 1fr 추가
6e7f078 이미지 figure 세로 중앙 정렬 + developer 규칙 D 추가
4b987b4 S1·S18 캔버스 중앙 정렬 fix + developer 규칙 C 추가
9bd2894 deck.html 정렬 fix + developer 프롬프트 selector-parity 규칙
abb017a fetch-image.sh: codex image_gen.imagegen 기반 (OPENAI_API_KEY 불필요)
f0fd77d Image policy: gpt-image-gen first + 인물 wiki 한정
0757f68 Image policy: vector-first (inline SVG) — Designer 갱신
```

다음 세션은 이 결정들 위에서 작업 — memory 자동 학습으로 같은 mistake 반복 X.
