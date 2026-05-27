# Visual Review System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** developer 완료 후 자동으로 슬라이드 PNG 를 캡처해 시각적 정렬·레이아웃 위반을 발견하고 CSS diff 로 자동 수정하는 `visual-reviewer` 에이전트 (Sonnet 멀티모달) 를 도입한다 — chapter-01 의 5-cycle 디버깅을 1-cycle 로 단축.

**Architecture:** 새 에이전트는 기존 5 에이전트 (director + decomposer/composer/designer/developer + reviewer) 의 마지막에 추가된다. tmux 6-pane 으로 확장. 자동 fix + retry max 3 round, 회귀 감지 시 rollback, manual_override 시 챕터 정지. 비용은 Claude subscription 흡수.

**Tech Stack:** Bash (`set -euo pipefail`), Chromium headless (PNG capture), Claude Sonnet 4.6 멀티모달 (이미지+JSON output), `git apply` (fix.patch), `jq` (STATE.json + eval.json), Reveal.js (`#/N` hash for slide nav), tmux 3.x send-keys + sentinel pattern.

**Spec:** [docs/superpowers/specs/2026-05-28-visual-review-system-design.md](../specs/2026-05-28-visual-review-system-design.md)

---

## File Structure

**신규 (4)**:
- `.claude/agents/visual-reviewer.md` — Sonnet 멀티모달 에이전트 system prompt (평가 체크리스트 7 + auto-fix 허용/금지 양분)
- `scripts/capture-deck.sh` — Chromium headless 로 deck.html 의 19 슬라이드 PNG batch
- `scripts/run-visual-review.sh` — capture + review + auto-fix loop (max 3 round, rollback snapshot)
- `memory/visual_review_patterns.md` — 누적 학습 통계 (초기 빈 템플릿)

**갱신 (4)**:
- `.claude/agents/director.md` — chapter 워크플로 마지막에 visual-review 단계 추가
- `scripts/start-session.sh` — 6-pane tmux 그리드 (pane 5 = visual-reviewer)
- `dashboard/index.html` + `dashboard/poll.js` — visual-review rounds 표시, manual_override 빨강 강조
- `PRD/03_PHASES.md` — Phase 3 진입 명시

**검증 fixture**:
- `tests/visual-review/chapter-01-known-bad/` — 의도적 결함 5 개 inject 한 deck.html 5 변형

각 파일은 단일 책임. capture-deck.sh 는 PNG export 만, run-visual-review.sh 는 loop 만, visual-reviewer 는 평가+CSS diff 만. fix 적용은 run-visual-review.sh 가.

---

## Task 1: 의존성 셋업 (Chromium headless)

**Files:**
- Verify: `which chromium`, `which jq`, `which git`

- [ ] **Step 1: Chromium 설치 확인**

Run: `which chromium-browser || which chromium || which "Google Chrome"`
Expected: 최소 한 개 경로 출력

- [ ] **Step 2: 없으면 설치**

Run: `brew install --cask chromium` 또는 macOS 기존 Chrome 활용:
```bash
ln -sf "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" /usr/local/bin/chromium-browser
```

- [ ] **Step 3: Headless 모드 동작 확인**

Run:
```bash
chromium --headless --window-size=1920,1080 \
  --screenshot=/tmp/test-capture.png \
  "https://example.com"
file /tmp/test-capture.png
```

Expected: `PNG image data, 1920 x 1080`

- [ ] **Step 4: Cleanup**

Run: `rm /tmp/test-capture.png`

- [ ] **Step 5: Commit (의존성 문서화)**

`README.md` 의 "필수 도구" 표에 chromium 행 추가 후:
```bash
git add README.md
git commit -m "Add chromium dependency for visual-review system"
```

---

## Task 2: scripts/capture-deck.sh (PNG export)

**Files:**
- Create: `scripts/capture-deck.sh`
- Test fixture: `content/chapters/chapter-01/slides/deck.html` (기존)

- [ ] **Step 1: 빈 스크립트 + sanity check 부터 작성**

Create `scripts/capture-deck.sh`:
```bash
#!/usr/bin/env bash
# scripts/capture-deck.sh — Chromium headless 로 deck.html 의 모든 슬라이드를 PNG 로 캡처.
#
# 사용:
#   bash scripts/capture-deck.sh <chapter_id> <round_num>
# 예:
#   bash scripts/capture-deck.sh chapter-01 1
#
# 출력: content/chapters/<chapter_id>/visual-review/round-<N>/slide-<idx>.png (19장)

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: bash scripts/capture-deck.sh <chapter_id> <round_num>" >&2
  exit 2
fi

CHAPTER="$1"
ROUND="$2"

DECK="$PWD/content/chapters/${CHAPTER}/slides/deck.html"
OUT_DIR="$PWD/content/chapters/${CHAPTER}/visual-review/round-${ROUND}"

if [[ ! -f "$DECK" ]]; then
  echo "deck.html not found: $DECK" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Chromium 명령 — macOS 환경에 따라 분기
if command -v chromium >/dev/null 2>&1; then
  CHROME_BIN="chromium"
elif command -v chromium-browser >/dev/null 2>&1; then
  CHROME_BIN="chromium-browser"
elif [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
  CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
else
  echo "chromium / chrome not found. Install: brew install --cask chromium" >&2
  exit 127
fi

echo "🎬 Capturing ${CHAPTER} round ${ROUND}..." >&2
```

- [ ] **Step 2: 19 슬라이드 capture loop 추가**

Append to `scripts/capture-deck.sh`:
```bash
# Reveal.js 슬라이드 hash 는 0-base (#/0 ~ #/18). 19 슬라이드.
# 캡처 사이 1.5초 대기 (transition fade 안정화)
for IDX in $(seq 0 18); do
  OUT="${OUT_DIR}/slide-$(printf '%02d' $IDX).png"
  "$CHROME_BIN" --headless \
    --window-size=1920,1080 \
    --virtual-time-budget=2000 \
    --screenshot="$OUT" \
    "file://${DECK}#/${IDX}" 2>/dev/null

  if [[ ! -s "$OUT" ]]; then
    echo "  ✗ slide-${IDX} failed" >&2
    continue
  fi
  SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")
  echo "  ✓ slide-$(printf '%02d' $IDX).png (${SIZE} bytes)" >&2
done

# 출력 PNG 개수 검증
COUNT=$(ls -1 "$OUT_DIR"/slide-*.png 2>/dev/null | wc -l | tr -d ' ')
echo "📸 Captured ${COUNT}/19 slides to ${OUT_DIR}" >&2

if [[ "$COUNT" -lt 19 ]]; then
  echo "⚠ ${COUNT}/19 — 일부 슬라이드 캡처 실패" >&2
  exit 1
fi
```

- [ ] **Step 3: 실행 권한 + 실 데이터 테스트**

Run:
```bash
chmod +x scripts/capture-deck.sh
bash scripts/capture-deck.sh chapter-01 0   # round 0 = test
```

Expected:
- `📸 Captured 19/19 slides to .../round-0`
- 19 개 PNG 파일 (각 100KB~1MB)

- [ ] **Step 4: 출력 PNG 시각 검증 (수동)**

Read content/chapters/chapter-01/visual-review/round-0/slide-04.png (s05 교육공학 정의)
Expected: 좌측 텍스트 + 우측 방사형 다이어그램 (figure 가 세로 중앙)

- [ ] **Step 5: Cleanup + Commit**

```bash
rm -rf content/chapters/chapter-01/visual-review/round-0
git add scripts/capture-deck.sh
git commit -m "Add scripts/capture-deck.sh — Chromium headless PNG batch (19 slides)"
```

---

## Task 3: visual-reviewer 에이전트 system prompt

**Files:**
- Create: `.claude/agents/visual-reviewer.md`

- [ ] **Step 1: 에이전트 metadata + role**

Create `.claude/agents/visual-reviewer.md`:
```markdown
---
name: visual-reviewer
description: developer 완료 후 슬라이드 PNG 를 평가해 정렬·레이아웃 위반을 발견하고 CSS diff 를 자동 생성한다.
model: sonnet
color: blue
---
# Visual Reviewer Agent

## 실행 환경
- tmux pane 5 (`@role visual-reviewer`) 에서 `claude --model sonnet --effort high --dangerously-skip-permissions` 으로 실행.
- 멀티모달 입력 가능 (이미지 + 텍스트). PNG 파일 경로를 Read 도구로 받음.

## Role
chapter-NN 의 19 PNG 슬라이드를 평가해 KRDS 디자인 시스템 위반 (정렬·레이아웃 전용 — PI 정책 2026-05-27) 을 발견하고, 각 issue 에 대한 CSS diff 를 unified patch 형식으로 작성한다. 직접 deck.html 을 수정하지 않는다 — run-visual-review.sh 가 patch 를 적용한다.
```

- [ ] **Step 2: 평가 체크리스트 7 (정렬·레이아웃 전용)**

Append to `.claude/agents/visual-reviewer.md`:
```markdown

## 평가 체크리스트 (7 카테고리)

각 PNG 슬라이드마다 다음 7 카테고리 위반 여부 평가:

1. **figure-vertical-alignment** (layout-image): figure 가 body-area 의 세로 중앙 (±5%) 인지. 상단·하단 정렬되면 위반.
2. **canvas-center-alignment** (layout-cover, layout-closing): 텍스트 블록 중심이 슬라이드 캔버스 540px ±20px 인지.
3. **header-bar-ratio** (본문 슬라이드): 헤더바 높이가 130px (1080의 12%) 인지. 작거나 큰 경우 위반.
4. **flat-design-violation** (모든 슬라이드): box-shadow, gradient, blur, glow 사용 여부. KRDS flat 위반.
5. **content-overflow** (모든 슬라이드): 텍스트가 슬라이드 영역 (1920×1080) 밖으로 잘림. figcaption 잘림 포함.
6. **figure-text-overlap** (layout-image): figure 가 copy 영역 침범 또는 반대.
7. **layout-enum-violation**: 정의된 5+4 (cover/section/text/image/table + image-wide/flex-2col/flow-cards/closing) 외 layout class 사용.

체크리스트 외 issue (예: 폰트 정확성, 컨텐츠 오타) 는 발견하지 않는다 — reviewer × 3 (텍스트) 의 역할.
```

- [ ] **Step 3: 출력 JSON 형식 명세**

Append:
```markdown

## 출력 형식

작업 디렉토리 `content/chapters/<CHAPTER>/visual-review/round-<N>/` 에 두 파일 생성:

### eval.json
```json
{
  "round": 1,
  "chapter": "chapter-05",
  "issues_count": 2,
  "issues": [
    {
      "slide_id": "s05",
      "category": "figure-vertical-alignment",
      "observed": "figure 가 슬라이드 상단 1/3 영역에 위치 (y=180px). copy 영역 길이 540px 대비 figure 시작점이 너무 위.",
      "expected": "body-area 세로 중앙 (y=435px ±43px)",
      "css_fix": "section.layout-image { height: 100%; }",
      "css_fix_location": "deck.html:365",
      "auto_apply_allowed": true
    }
  ]
}
```

### fix.patch (auto_apply_allowed: true 인 issue 만)
unified diff 형식. `git apply --check` 가 통과해야 함.
```diff
--- a/content/chapters/chapter-05/slides/deck.html
+++ b/content/chapters/chapter-05/slides/deck.html
@@ -363,3 +363,4 @@
 section.layout-image {
   padding: 0;
+  height: 100%;
 }
```
```

- [ ] **Step 4: auto-fix 허용/금지 양분**

Append:
```markdown

## auto-fix 허용/금지 (PI 정책)

### auto_apply_allowed: true
- CSS 단일 속성 값 변경 (height/width/padding/margin/font-size 등)
- flex/grid 속성 (align-items, justify-content, display)
- color 토큰 변경 (KRDS 팔레트 안에서만)
- `section.layout-*` selector 의 단일 속성 추가

### auto_apply_allowed: false (manual_override 권장)
- HTML 구조 변경 (div 추가/제거)
- 새 CSS class 정의
- 새 레이아웃 enum (5+4 외)
- 본문 컨텐츠 텍스트 변경
- 본문 font-size 44px 미만으로 설정
- `!important` 추가
- raw HEX 색상 직접 (변수 외)
- 이미지 파일 src 변경

manual_override 권장 시 `css_fix` 필드에 "manual review required: <상세 진단>" 작성.
```

- [ ] **Step 5: 작업 절차 + sentinel**

Append:
```markdown

## 작업 절차

1. director 가 `task-chapter-NN-visual-reviewer-round-M` task 로 호출.
2. PNG batch 경로 받음: `content/chapters/<CHAPTER>/visual-review/round-<M>/slide-{00..18}.png`
3. 19 PNG 각각 Read 도구로 분석 + DESIGN.md + memory `deck_css_patterns.md` 참조.
4. issues 발견 시 eval.json 작성. auto_apply_allowed: true 인 모든 issue 를 모아 fix.patch 작성.
5. 종료 시 sentinel: `touch /tmp/lecture-team-sentinel-task-chapter-NN-visual-reviewer-round-M.done`
6. `# AGENT_DONE_SIGNAL: task-chapter-NN-visual-reviewer-round-M` 출력.

## 금지
- deck.html 직접 수정 X (run-visual-review.sh 가 patch 적용)
- 평가 체크리스트 7 외 카테고리 발견 X
- HTML 구조 변경 css_fix X
- !important 사용 css_fix X
```

- [ ] **Step 6: Commit**

```bash
git add .claude/agents/visual-reviewer.md
git commit -m "Add .claude/agents/visual-reviewer.md — Sonnet 멀티모달 시각 검수 에이전트"
```

---

## Task 4: scripts/run-visual-review.sh (loop)

**Files:**
- Create: `scripts/run-visual-review.sh`
- Depends on: capture-deck.sh (Task 2), visual-reviewer (Task 3), send-to-pane.sh (기존)

- [ ] **Step 1: 헤더 + 인자 파싱**

Create `scripts/run-visual-review.sh`:
```bash
#!/usr/bin/env bash
# scripts/run-visual-review.sh — visual-reviewer loop (max 3 round + rollback)
#
# 사용: bash scripts/run-visual-review.sh <chapter_id>
#
# director 가 developer sentinel 감지 후 호출.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/run-visual-review.sh <chapter_id>" >&2
  exit 2
fi

CHAPTER="$1"
DECK="content/chapters/${CHAPTER}/slides/deck.html"
MAX_ROUND=3
PREV_ISSUES=99   # 초기값 (큰 수)

if [[ ! -f "$DECK" ]]; then
  echo "deck.html not found: $DECK" >&2
  exit 1
fi

echo "🔍 visual-review: ${CHAPTER} (max ${MAX_ROUND} round)" >&2
```

- [ ] **Step 2: round loop + rollback snapshot**

Append:
```bash
for ROUND in $(seq 1 $MAX_ROUND); do
  echo "" >&2
  echo "━━━ Round ${ROUND} ━━━" >&2

  # rollback snapshot
  cp "$DECK" "${DECK}.before-round-${ROUND}"

  # 1. PNG 캡처
  if ! bash scripts/capture-deck.sh "$CHAPTER" "$ROUND" 2>&1 >&2; then
    echo "  ✗ capture failed" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "capture-deck.sh failed"
    exit 1
  fi

  # 2. visual-reviewer 호출 (sentinel 폴링은 send-to-pane.sh 가 처리)
  TASK_ID="task-${CHAPTER}-visual-reviewer-round-${ROUND}"
  PROMPT="@.claude/agents/visual-reviewer.md

Task: ${CHAPTER} round ${ROUND} 시각 검수.

PNG 경로: $PWD/content/chapters/${CHAPTER}/visual-review/round-${ROUND}/slide-{00..18}.png
DESIGN.md: $PWD/content/chapters/${CHAPTER}/DESIGN.md
출력: 같은 round 폴더에 eval.json + fix.patch (auto_apply 가능한 issue 만)

종료 시: touch /tmp/lecture-team-sentinel-${TASK_ID}.done"

  if ! bash scripts/send-to-pane.sh visual-reviewer "$TASK_ID" "$PROMPT"; then
    echo "  ✗ visual-reviewer 호출 실패" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "send-to-pane.sh failed"
    exit 1
  fi
```

- [ ] **Step 3: eval.json 파싱 + 조건 분기**

Append:
```bash
  EVAL="content/chapters/${CHAPTER}/visual-review/round-${ROUND}/eval.json"
  if [[ ! -f "$EVAL" ]]; then
    echo "  ✗ eval.json 없음 (visual-reviewer 출력 실패)" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "eval.json missing"
    exit 1
  fi

  ISSUES=$(jq -r '.issues_count' "$EVAL")
  echo "  📋 issues_count: ${ISSUES}" >&2

  # 3-a. 통과
  if [[ "$ISSUES" -eq 0 ]]; then
    echo "✅ visual-review 통과 (round ${ROUND})" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer done ""
    # snapshot cleanup
    rm -f "${DECK}.before-round-"*
    exit 0
  fi

  # 3-b. 회귀 감지 (issues 가 늘어남)
  if [[ "$ISSUES" -gt "$PREV_ISSUES" ]]; then
    echo "⚠ 회귀 감지 (${PREV_ISSUES} → ${ISSUES}). rollback." >&2
    # 가장 issues 적은 round 의 backup 복구
    BEST_ROUND=$((ROUND - 1))
    cp "${DECK}.before-round-1" "$DECK"
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "회귀 감지 — manual_override"
    exit 1
  fi
  PREV_ISSUES="$ISSUES"
```

- [ ] **Step 4: fix.patch 자동 적용**

Append:
```bash
  # 4. fix.patch 자동 적용 (auto_apply_allowed 만)
  PATCH="content/chapters/${CHAPTER}/visual-review/round-${ROUND}/fix.patch"

  AUTO_COUNT=$(jq -r '[.issues[] | select(.auto_apply_allowed == true)] | length' "$EVAL")
  MANUAL_COUNT=$(jq -r '[.issues[] | select(.auto_apply_allowed == false)] | length' "$EVAL")

  echo "  🔧 auto-fix: ${AUTO_COUNT} / manual: ${MANUAL_COUNT}" >&2

  if [[ "$MANUAL_COUNT" -gt 0 ]]; then
    echo "⚠ manual review required (${MANUAL_COUNT} issues)" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "manual_override: ${MANUAL_COUNT} non-auto-fixable issues"
    exit 1
  fi

  if [[ ! -f "$PATCH" ]]; then
    echo "  ✗ fix.patch 없음 (auto-fix 가능한 issue 인데 patch 누락)" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "patch missing"
    exit 1
  fi

  if ! git apply --check "$PATCH" 2>/dev/null; then
    echo "  ✗ git apply --check 실패 — patch 형식 오류" >&2
    # TODO Edit 도구 fallback 은 director 가 처리 (visual-reviewer 재호출로 css_fix 텍스트 전달)
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "patch invalid"
    exit 1
  fi

  git apply "$PATCH"
  echo "  ✓ patch 적용 완료" >&2

done   # end round loop
```

- [ ] **Step 5: round 3 후 미통과**

Append:
```bash
# round 3 까지 갔는데 통과 못 함
echo "✗ visual-review max round (${MAX_ROUND}) 통과 실패 — manual_override" >&2
bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "max round 미통과"
exit 1
```

- [ ] **Step 6: update-state.sh 헬퍼 스크립트 작성**

`run-visual-review.sh` 가 호출하는 STATE.json 갱신 헬퍼. director 만 STATE.json 쓰기 원칙이지만 sub-script 로 위임:

Create `scripts/update-state.sh`:
```bash
#!/usr/bin/env bash
# scripts/update-state.sh — STATE.json atomic update 헬퍼
#
# 사용: bash scripts/update-state.sh <chapter> <role> <status> <error_message>

set -euo pipefail

CHAPTER="$1"
ROLE="$2"
STATUS="$3"
ERROR_MSG="${4:-}"

TASK_ID="task-${CHAPTER}-${ROLE}"

jq --arg cid "$CHAPTER" \
   --arg tid "$TASK_ID" \
   --arg role "$ROLE" \
   --arg status "$STATUS" \
   --arg err "$ERROR_MSG" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.tasks |= (map(select(.id != $tid)) + [{
      id: $tid,
      chapter: $cid,
      role: $role,
      status: $status,
      error_message: $err,
      updated_at: $ts
    }])
    | .updated_at = $ts' \
   STATE.json > STATE.json.tmp

mv STATE.json.tmp STATE.json
echo "  📝 STATE.json: ${TASK_ID} → ${STATUS}" >&2
```

- [ ] **Step 7: 실행 권한 + commit**

```bash
chmod +x scripts/run-visual-review.sh scripts/update-state.sh
git add scripts/run-visual-review.sh scripts/update-state.sh
git commit -m "Add scripts/run-visual-review.sh — loop, rollback, regression detection"
```

---

## Task 5: chapter-01 known-bad fixture (검증용)

**Files:**
- Create: `tests/visual-review/chapter-01-known-bad/inject-defect-{1..5}.sh`
- Create: `tests/visual-review/chapter-01-known-bad/README.md`

- [ ] **Step 1: 테스트 디렉토리 + README**

```bash
mkdir -p tests/visual-review/chapter-01-known-bad
```

Create `tests/visual-review/chapter-01-known-bad/README.md`:
```markdown
# chapter-01 Known-Bad Fixture

visual-reviewer 자체 검증용. 정상 deck.html 에 의도적 결함 5 개를 inject 한 변형.

| inject 스크립트 | 결함 카테고리 | 기대 발견 |
|---|---|---|
| inject-defect-1.sh | figure-vertical-alignment | section.layout-image height:100% 제거 |
| inject-defect-2.sh | canvas-center-alignment | cover-content transform 제거 |
| inject-defect-3.sh | content-overflow | body-text font-size: 24px (44 미만) |
| inject-defect-4.sh | figure-vertical-alignment | figure 의 align-items:center 제거 |
| inject-defect-5.sh | flat-design-violation | header-bar 에 box-shadow 추가 |

## 사용
```bash
bash tests/visual-review/chapter-01-known-bad/run-validation.sh
```
정상 deck 복구 후 5 개 fixture 만들고 각각 visual-reviewer 호출.
통과 기준: 5/5 결함 발견, false positive 0.
```

- [ ] **Step 2: inject-defect-1 (figure 정렬)**

Create `tests/visual-review/chapter-01-known-bad/inject-defect-1.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# section.layout-image { height: 100% } 제거 — figure 상단 정렬 유도
DECK="content/chapters/chapter-01/slides/deck.html"
# sed: layout-image 블록 안 height: 100% 라인 삭제
sed -i.bak '/^section.layout-image {/,/^}$/ { /height: 100%/d; }' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-1 injected (figure-vertical-alignment)" >&2
```

- [ ] **Step 3: inject-defect-2 ~ 5**

Create `tests/visual-review/chapter-01-known-bad/inject-defect-2.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# cover-content transform: translate(-50%, -50%) 제거
DECK="content/chapters/chapter-01/slides/deck.html"
sed -i.bak '/section.layout-cover .cover-content/,/^}$/ { /transform: translate/d; }' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-2 injected (canvas-center-alignment)" >&2
```

Create `tests/visual-review/chapter-01-known-bad/inject-defect-3.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# body-text font-size: 44px → 24px (PI 정책 44 최저 위반)
DECK="content/chapters/chapter-01/slides/deck.html"
sed -i.bak '/^.body-text {/,/^}$/ { s/font-size: 44px/font-size: 24px/; }' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-3 injected (content-overflow / font-too-small)" >&2
```

Create `tests/visual-review/chapter-01-known-bad/inject-defect-4.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# section.layout-image .body-area { align-items: center } 제거
DECK="content/chapters/chapter-01/slides/deck.html"
sed -i.bak '/section.layout-image .body-area {/,/^}$/ { /align-items: center/d; }' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-4 injected (figure-vertical-alignment)" >&2
```

Create `tests/visual-review/chapter-01-known-bad/inject-defect-5.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# header-bar 에 box-shadow 추가 (KRDS flat 위반)
DECK="content/chapters/chapter-01/slides/deck.html"
sed -i.bak 's|background: var(--navy);|background: var(--navy);\n  box-shadow: 0 4px 8px rgba(0,0,0,0.2);|' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-5 injected (flat-design-violation)" >&2
```

- [ ] **Step 4: run-validation.sh (자동화)**

Create `tests/visual-review/chapter-01-known-bad/run-validation.sh`:
```bash
#!/usr/bin/env bash
# tests/visual-review/chapter-01-known-bad/run-validation.sh
#
# 5 결함 inject → visual-reviewer 각 호출 → recall 측정.
#
# 통과 기준: 5/5 결함 발견, false positive 0.

set -euo pipefail

DECK="content/chapters/chapter-01/slides/deck.html"
DECK_BAK="${DECK}.before-validation"

cp "$DECK" "$DECK_BAK"

declare -A EXPECTED_CATEGORY=(
  [1]="figure-vertical-alignment"
  [2]="canvas-center-alignment"
  [3]="content-overflow"
  [4]="figure-vertical-alignment"
  [5]="flat-design-violation"
)

PASS=0
FAIL=0

# false positive 검사 (정상 deck 먼저)
echo "━━━ False positive 검사 (정상 deck) ━━━"
bash scripts/run-visual-review.sh chapter-01
FP_EVAL="content/chapters/chapter-01/visual-review/round-1/eval.json"
FP_ISSUES=$(jq -r '.issues_count' "$FP_EVAL")
if [[ "$FP_ISSUES" -eq 0 ]]; then
  echo "  ✓ false positive 0"
else
  echo "  ✗ 정상 deck 에 ${FP_ISSUES} 개 issue 발견 (false positive)" >&2
  FAIL=$((FAIL + 1))
fi

# 5 결함 각각 검사
for N in 1 2 3 4 5; do
  echo ""
  echo "━━━ Defect ${N}: ${EXPECTED_CATEGORY[$N]} ━━━"
  cp "$DECK_BAK" "$DECK"   # 원본 복구
  bash "tests/visual-review/chapter-01-known-bad/inject-defect-${N}.sh"
  bash scripts/run-visual-review.sh chapter-01 || true   # 실패해도 eval.json 만들어짐
  EVAL="content/chapters/chapter-01/visual-review/round-1/eval.json"
  FOUND=$(jq -r --arg cat "${EXPECTED_CATEGORY[$N]}" \
    '[.issues[] | select(.category == $cat)] | length' "$EVAL")
  if [[ "$FOUND" -ge 1 ]]; then
    echo "  ✓ defect-${N} 발견 (${EXPECTED_CATEGORY[$N]})"
    PASS=$((PASS + 1))
  else
    echo "  ✗ defect-${N} 못 찾음" >&2
    FAIL=$((FAIL + 1))
  fi
done

# 원본 deck 복구
cp "$DECK_BAK" "$DECK"
rm "$DECK_BAK"

echo ""
echo "━━━ 결과 ━━━"
echo "PASS: ${PASS}/5  FAIL: ${FAIL}"
if [[ "$PASS" -eq 5 && "$FAIL" -eq 0 ]]; then
  echo "✅ visual-reviewer 통과 — Stage 2 (단일 챕터) 진입 OK"
  exit 0
else
  echo "❌ visual-reviewer 미통과 — system prompt 수정 필요"
  exit 1
fi
```

- [ ] **Step 5: 실행 권한 + commit**

```bash
chmod +x tests/visual-review/chapter-01-known-bad/*.sh
git add tests/visual-review/
git commit -m "Add chapter-01 known-bad fixture — 5 결함 + run-validation.sh"
```

---

## Task 6: scripts/start-session.sh 6-pane 확장

**Files:**
- Modify: `scripts/start-session.sh` (기존)

- [ ] **Step 1: 현재 pane 정의 위치 확인**

Run: `grep -n "pane\|split-window" scripts/start-session.sh | head -20`

기존 5-pane 정의 줄 번호 확인.

- [ ] **Step 2: 6-pane 으로 split 추가**

`scripts/start-session.sh` 의 pane 4 (developer) 정의 다음에 pane 5 추가:

```bash
# 기존 마지막 split-window 다음에 추가
tmux split-window -t lecture-team:0.4 -h -p 50
tmux send-keys -t lecture-team:0.5 'clear; echo "[pane 5] visual-reviewer (Sonnet 멀티모달)"' Enter

# 6-pane layout 재정렬 (3 행 × 2 열 또는 director 위 + 그리드)
tmux select-layout -t lecture-team:0 tiled
```

또는 정확한 레이아웃 (Section 2 mockup) 위해 manual split:
```bash
# director 풀폭 상단
tmux rename-window -t lecture-team:0 'team'

# 중간 행: decomposer | composer
tmux split-window -t lecture-team:0.0 -v -p 70   # director 아래 70%
tmux split-window -t lecture-team:0.1 -h -p 50   # 중간 좌우 분할

# 하단 행: designer | developer | visual-reviewer
tmux split-window -t lecture-team:0.1 -v -p 50   # 중간 → 하단
tmux split-window -t lecture-team:0.3 -h -p 67   # 하단 1/3
tmux split-window -t lecture-team:0.4 -h -p 50   # 하단 2/3
```

- [ ] **Step 3: @role @label pane 옵션**

기존 pane title 패턴 따라 pane 5 옵션:
```bash
tmux set-option -t lecture-team:0.5 -p @role visual-reviewer
tmux set-option -t lecture-team:0.5 -p @label 'visual-reviewer (Sonnet)'
```

- [ ] **Step 4: Claude Code 부트스트랩 (pane 5)**

기존 워커 부트스트랩 패턴 (pane 1-4) 동일하게 pane 5 에도 적용:
```bash
tmux send-keys -t lecture-team:0.5 'cd "$PROJECT_DIR" && claude --model sonnet --effort high --dangerously-skip-permissions' Enter
```

- [ ] **Step 5: 실행 + 6-pane 확인**

```bash
# 기존 세션 종료
tmux kill-session -t lecture-team 2>/dev/null || true
# 새 세션 시작
bash scripts/start-session.sh
# 확인
tmux list-panes -t lecture-team -F '#{pane_index} #{@role}'
```

Expected: pane 0~5, role = director/decomposer/composer/designer/developer/visual-reviewer

- [ ] **Step 6: Commit**

```bash
git add scripts/start-session.sh
git commit -m "Update start-session.sh — 6-pane tmux (pane 5 visual-reviewer)"
```

---

## Task 7: .claude/agents/director.md 갱신 (visual-review 단계)

**Files:**
- Modify: `.claude/agents/director.md`

- [ ] **Step 1: 워크플로 표 갱신**

`.claude/agents/director.md` 의 chapter status 표 (`planned → decomposed → ...`) 에 visual-review 추가:

```diff
 | chapter status | 다음 워커 | 기대 산출물 |
 |---|---|---|
 | `planned` | decomposer | `content/chapters/chapter-01/decomposed.md` |
 | `decomposed` | composer | `content/chapters/chapter-01/composed.md` |
 | `composed` | designer | `content/chapters/chapter-01/DESIGN.md` |
 | `designed` | developer | `content/chapters/chapter-01/slides/deck.html`, `deck.pdf` |
+| `developed` | visual-reviewer | `content/chapters/chapter-01/visual-review/round-{1..3}/eval.json` + auto-fix |
```

- [ ] **Step 2: workflow pseudo-code 갱신**

`## Workflow` 섹션의 pseudo-code 에 visual-review 단계 추가:

```diff
 # ⚠ designer 완료 직후 반드시 이미지 batch 트리거 (워크플로 누락 방지)
 if next_step == "designed" and task.status == "done":
   bash scripts/run-image-fetch.sh <chapter_id>

+# ⚠ developer 완료 직후 visual-review 자동 실행
+if next_step == "developed" and task.status == "done":
+  bash scripts/run-visual-review.sh <chapter_id>
+  # → visual-reviewer max 3 round + auto-fix + rollback
+  # → 통과 시 chapter.status = "verified", 실패 시 manual_override

 while true:
   output = tmux_capture_pane(role)
```

- [ ] **Step 3: visual-reviewer 호출 패턴 예시 추가**

`## Command Patterns` 섹션에 추가:
```bash
# visual-reviewer 호출 (run-visual-review.sh 가 내부에서 send-to-pane.sh 사용)
bash scripts/run-visual-review.sh chapter-01
```

- [ ] **Step 4: Phase 3 진입 명시**

`## Role` 섹션의 Phase 표시에 추가:
```diff
 **Phase 2 (chapter-02 ~ chapter-10, 직렬)**: PI 지시로 활성화 — 완료.
+**Phase 3 (visual-review 도입)**: developer 완료 후 자동 시각 검증.
+visual-reviewer × ≤3 round, auto-fix, manual_override 시 챕터 정지.
```

- [ ] **Step 5: Commit**

```bash
git add .claude/agents/director.md
git commit -m "Update director.md — Phase 3 visual-review 단계 추가"
```

---

## Task 8: dashboard 갱신 (visual-review rounds 표시)

**Files:**
- Modify: `dashboard/index.html`
- Modify: `dashboard/poll.js`

- [ ] **Step 1: index.html 카드 영역에 visual-review 표시 자리**

`dashboard/index.html` 의 chapter 카드 템플릿 안에 추가:
```html
<!-- 기존 reviewer × 3 round 표시 다음에 -->
<div class="visual-review-status" data-chapter-id-vr>
  <span class="label">시각 검수</span>
  <span class="rounds"></span>
</div>
```

- [ ] **Step 2: CSS 추가**

`dashboard/index.html` 의 `<style>` 또는 `dashboard/style.css` 에:
```css
.visual-review-status {
  font-size: 13px;
  color: #5C6470;
  margin-top: 8px;
}
.visual-review-status .rounds .round-badge {
  display: inline-block;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  font-size: 11px;
  line-height: 18px;
  text-align: center;
  margin-right: 4px;
}
.visual-review-status .round-badge.pass { background: #1F9D57; color: #fff; }
.visual-review-status .round-badge.fail { background: #E03B3B; color: #fff; }
.visual-review-status .round-badge.running { background: #1B66C9; color: #fff; }
.chapter-card.manual-override { border-left: 4px solid #E03B3B; background: #FFF5F5; }
```

- [ ] **Step 3: poll.js 에 visual-review 렌더 함수**

`dashboard/poll.js` 의 chapter card 렌더 함수에 추가:
```javascript
function renderVisualReview(chapterCard, chapter) {
  const vrStatus = chapterCard.querySelector('.visual-review-status .rounds');
  if (!vrStatus) return;
  vrStatus.innerHTML = '';

  const vrTask = (chapter.tasks || []).find(t => t.role === 'visual-reviewer');
  if (!vrTask) {
    vrStatus.innerHTML = '<span style="color:#999">미실행</span>';
    return;
  }

  const rounds = vrTask.rounds || [];
  rounds.forEach((r, idx) => {
    const badge = document.createElement('span');
    badge.className = 'round-badge ' + (r.issues_count === 0 ? 'pass' : (vrTask.status === 'failed' ? 'fail' : 'running'));
    badge.textContent = idx + 1;
    badge.title = `Round ${idx+1}: ${r.issues_count} issues, auto_fixed=${r.auto_fixed}`;
    vrStatus.appendChild(badge);
  });

  if (vrTask.status === 'failed') {
    chapterCard.classList.add('manual-override');
  }
}
```

- [ ] **Step 4: chapter card 렌더 함수에서 호출**

기존 chapter card 렌더 함수의 끝에 호출 추가:
```javascript
renderVisualReview(card, chapter);
```

- [ ] **Step 5: 실 데이터로 확인**

대시보드 새로고침 — chapter-01 의 visual-review 카드 영역에 "미실행" 표시되는지.

- [ ] **Step 6: Commit**

```bash
git add dashboard/
git commit -m "Update dashboard — visual-review rounds 표시 + manual_override 강조"
```

---

## Task 9: memory/visual_review_patterns.md (초기)

**Files:**
- Create: memory file (git repo 밖 — `~/.claude/projects/.../memory/`)

- [ ] **Step 1: memory 파일 작성**

Create `~/.claude/projects/-Users-taehyeong-Documents-GitHub-lecture-content-maker-agent-team/memory/visual_review_patterns.md`:
```markdown
---
name: visual-review-patterns
description: visual-reviewer 가 발견한 issue 카테고리·빈도 통계. designer/developer 가 사전 회피용으로 참조.
metadata:
  type: project
---

**상태**: 초기 (chapter-01 PoC visual-review 시작 시점). 챕터 처리할 때마다 누적 갱신.

## 카테고리별 발견 빈도

(empty — 첫 챕터 visual-review 후 갱신)

## 패턴별 미리 회피 가이드

(empty — 데이터 축적 후 작성)

## 회귀 사례 (auto-fix 가 다른 슬라이드 깨뜨린 경우)

(empty)

## 관련 메모리
- [[deck-css-patterns]] — figure 세로 중앙 3 선행 조건 + 폰트 44 최저 + 디자인 시스템 (visual-reviewer 평가 기준)
- [[image-policy]] — gpt-image-gen 정책
```

- [ ] **Step 2: MEMORY.md index 갱신**

Edit `~/.claude/projects/-Users-taehyeong-Documents-GitHub-lecture-content-maker-agent-team/memory/MEMORY.md`:
```diff
 - [Deck CSS patterns](deck_css_patterns.md) — figure 세로 중앙, 표지 cover-meta 금지, 캔버스 중앙 정렬, 진단 outline (PI 2026-05-26~27)
+- [Visual review patterns](visual_review_patterns.md) — visual-reviewer 발견 issue 통계 (Phase 3+)
```

- [ ] **Step 3: 검증 — Claude Code 재시작 후 MEMORY.md 자동 로드 확인**

memory 는 다음 conversation 에서 auto-load. 이번에 즉시 확인 X.

- [ ] **Step 4: 별도 commit 없음** (memory 는 git repo 밖)

---

## Task 10: PRD/03_PHASES.md 갱신 (Phase 3)

**Files:**
- Modify: `PRD/03_PHASES.md`

- [ ] **Step 1: Phase 3 섹션 추가**

`PRD/03_PHASES.md` 끝에 추가:
```markdown

## Phase 3: Visual Review System (2026-05-28~)

**목표**: developer 완료 후 자동 시각 검증으로 chapter-01 의 5-cycle 디버깅을 1-cycle 로 단축.

**범위**:
- visual-reviewer 에이전트 신설 (Sonnet 멀티모달, tmux pane 5)
- 정렬·레이아웃 전용 평가 7 카테고리
- 자동 fix + retry max 3 round (PI 결정 C 접근)
- 회귀 감지 시 rollback, manual_override 시 챕터 정지

**산출**:
- `.claude/agents/visual-reviewer.md`
- `scripts/{capture-deck,run-visual-review,update-state}.sh`
- `tests/visual-review/chapter-01-known-bad/` (5 결함 fixture)
- `memory/visual_review_patterns.md` (누적 학습)

**검증 기준**: chapter-01 fixture 5/5 결함 발견 + false positive 0 + 회귀 0.

**참고**:
- Spec: `docs/superpowers/specs/2026-05-28-visual-review-system-design.md`
- Plan: `docs/superpowers/plans/2026-05-28-visual-review-system.md`
```

- [ ] **Step 2: Commit**

```bash
git add PRD/03_PHASES.md
git commit -m "PRD/03_PHASES.md — Phase 3 Visual Review System 추가"
```

---

## Task 11: 검증 실행 (chapter-01 fixture)

**Files:**
- Test: `tests/visual-review/chapter-01-known-bad/run-validation.sh`

- [ ] **Step 1: 사전 조건 확인**

Run:
```bash
ls scripts/capture-deck.sh scripts/run-visual-review.sh
ls .claude/agents/visual-reviewer.md
which chromium-browser || which chromium || which "Google Chrome"
tmux ls | grep lecture-team || bash scripts/start-session.sh
```

Expected: 모두 존재

- [ ] **Step 2: 검증 실행**

Run: `bash tests/visual-review/chapter-01-known-bad/run-validation.sh`

Expected:
```
━━━ False positive 검사 ━━━
  ✓ false positive 0
━━━ Defect 1: figure-vertical-alignment ━━━
  ✓ defect-1 발견
... (5 회)
━━━ 결과 ━━━
PASS: 5/5  FAIL: 0
✅ visual-reviewer 통과
```

- [ ] **Step 3: 미통과 시 visual-reviewer 프롬프트 수정**

만약 PASS < 5 또는 false positive 발생:
- 어느 결함 못 찾았는지 확인 (eval.json 분석)
- `.claude/agents/visual-reviewer.md` 의 평가 체크리스트 해당 카테고리 부분 강화
- 다시 Task 11 처음으로

- [ ] **Step 4: 통과 시 commit (검증 결과 기록)**

```bash
# 검증 통과 후 결과 보관용 디렉토리
mkdir -p docs/superpowers/validation
cp content/chapters/chapter-01/visual-review/round-1/eval.json \
   docs/superpowers/validation/2026-05-28-chapter-01-baseline-eval.json
git add docs/superpowers/validation/
git commit -m "Validation passed — visual-reviewer 5/5 결함 발견 + false positive 0"
```

---

## Task 12: chapter-01 회고적 visual-review (Stage 3)

**Files:**
- Apply: chapter-01 (현재 상태)

- [ ] **Step 1: chapter-01 visual-review 실행**

Run: `bash scripts/run-visual-review.sh chapter-01`

Expected: round 1 통과 (chapter-01 은 이미 정상 deck.html — 5-cycle 디버깅 후 verified 상태)

- [ ] **Step 2: 만약 issues 발견 시**

5-cycle 디버깅 후 박힌 정렬은 시각적으로 정상이지만, visual-reviewer 가 새 위반 발견할 가능성 있음 (예: figcaption 잘림 등).

발견된 issues 가 auto-fix 가능하면 → 자동 적용 → 재 visual-review
manual_override 면 → PI 결정 후 진행

- [ ] **Step 3: chapter-02~10 batch (옵션)**

PI 의도 시:
```bash
for CH in chapter-02 chapter-03 chapter-04 chapter-05 chapter-06 chapter-07 chapter-08 chapter-09 chapter-10; do
  echo "━━━ $CH ━━━"
  bash scripts/run-visual-review.sh "$CH" || echo "  ⚠ $CH manual_override"
done
```

- [ ] **Step 4: STATE.json 결과 검토**

Run: `jq '.chapters[] | {id, status, visual_review: (.tasks[] | select(.role == "visual-reviewer") | {status, rounds_count: (.rounds | length)})}' STATE.json`

Expected: 모든 챕터의 visual-reviewer status 표시

- [ ] **Step 5: 회고적 적용 결과 commit (optional — content/ .gitignore)**

`content/` 는 추적 안 함. 결과 요약만 commit:
```bash
# 통계 요약 작성
echo "## chapter-01~10 visual-review 회고 결과 (2026-05-28)" > docs/superpowers/validation/2026-05-28-batch-result.md
jq -r '.chapters[] | "- \(.id): \((.tasks[] | select(.role == "visual-reviewer")).status // "미실행")"' STATE.json \
  >> docs/superpowers/validation/2026-05-28-batch-result.md
git add docs/superpowers/validation/
git commit -m "chapter-01~10 회고적 visual-review 결과 요약"
```

---

## Self-Review Notes

- ✅ Spec 의 6 컴포넌트 모두 task 로 mapping (T2 capture + T3 reviewer + T4 loop + T6 start-session + T7 director + T9 memory)
- ✅ Spec 의 Testing 섹션 → T5 (fixture) + T11 (검증 실행) 으로 분리
- ✅ Spec 의 Roll-out Stage 3 → T12 으로 mapping (Stage 1·2·4 는 spec 의 시점적 정책으로 task 분리 불필요)
- ✅ 모든 step 에 실행 명령 + expected output + 실제 코드 박혀있음
- ✅ Type 일관성: `task-${CHAPTER}-visual-reviewer-round-${ROUND}` task ID 패턴이 T3·T4 양쪽 동일
- ✅ 파일 경로 일관: `content/chapters/<CHAPTER>/visual-review/round-<N>/{eval.json,fix.patch,slide-NN.png}` 모든 task 동일

**알려진 한계**:
- visual-reviewer system prompt 의 7 카테고리는 LLM 평가의 정확성에 의존. T11 검증에서 5/5 못 통과하면 system prompt 강화 사이클 필요.
- Chromium headless 가 #/N hash 로딩 후 transition fade (1500ms) 끝나기 전 캡처 가능성. `--virtual-time-budget=2000` 으로 대응했지만 환경마다 다를 수 있음.
- T6 의 tmux 6-pane layout 은 터미널 폭 1600px+ 가정. 좁은 터미널에서는 manual select-layout 필요.
