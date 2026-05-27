# Visual Review System — Design Spec

**Status**: Design approved by PI (임태형). Pending implementation plan.
**Date**: 2026-05-28
**Authors**: PI + Claude (Opus 4.7)
**Approach**: C (Aggressive — auto-fix + retry, max 3 round)

---

## Summary

새 에이전트 `visual-reviewer` (Sonnet 멀티모달) 를 도입해 developer 완료 후 자동으로 슬라이드 PNG 를 캡처하고, 정렬·레이아웃 위반을 자연어 평가 + CSS diff 로 자동 수정한다. 기존 5-pane tmux 가 6-pane 으로 확장되고, director 워크플로 마지막에 visual-review 단계가 삽입된다. 한 챕터당 +3-5 분, 비용은 Claude subscription 에 흡수 ($0).

기대 효과: chapter-01 PoC 의 5-cycle CSS 디버깅이 1-cycle 로 단축. PI 가 매 챕터의 시각 정렬을 수동 확인할 필요 사라짐.

---

## Background — 10주차 학습 (Why)

chapter-01 PoC 디버깅 사례:

| Cycle | 추측 fix | 실패 원인 |
|---|---|---|
| 1 | `figure align-self: center` | grid row contents-based → cell = figure → align 무력 |
| 2 | `grid-template-rows: 1fr` | Reveal scaled section implicit height 인식 의심 |
| 3 | grid → flex 전환 | 같은 implicit height 문제 |
| 4 | `.body-area { height: calc(...) }` | 부모 layout-image height 없음 |
| 5 | `align-items: center` | 효과 없음 (같은 부모 height 문제) |
| **6** | **`section.layout-image { height: 100%; }`** | **✅ 실제 root cause** |

핵심 통찰:
- 시각 확인 채널 없이는 CSS 추측이 5 cycle 까지 반복됨
- 진단 outline 박스 1 회로 root cause 즉시 발견
- AI 가 PNG 보고 자동 평가하면 같은 발견 가능

PI 명시 (2026-05-27): "시각 검증 자동화" 가 가장 시급, "AI 검수 자동화" + "정렬·레이아웃 전용" 범위, "자동 fix 적용 + retry" (C 접근).

---

## Architecture

```
chapter 워크플로 (Phase 3):

director (Opus)
  ├─ decomposer / composer / designer / developer
  ├─ reviewer × 3 round (텍스트 검수, 기존)
  └─ visual-reviewer × ≤3 round (시각 검수, 신설) ★
      1. capture-deck.sh → 19 PNG
      2. send-to-pane.sh visual-reviewer
      3. parse eval.json
      4. issues=0? done : auto-apply fix.patch → round++
```

신규 컴포넌트는 기존 sentinel + STATE.json atomic write 패턴을 그대로 따른다. director.md 만 마지막 단계 추가.

---

## Components

### 1. `.claude/agents/visual-reviewer.md` (신규)
- **모델**: Claude Sonnet 4.6 (멀티모달, 이미지 입력)
- **effort**: `--effort high --dangerously-skip-permissions`
- **입력**: 19 PNG 파일 경로 + DESIGN.md + memory `deck_css_patterns.md`
- **출력**: `visual-review/round-N/eval.json` + `fix.patch`

**평가 체크리스트 (정렬·레이아웃 전용, PI 결정 범위)**:
1. figure 세로 중앙 (layout-image): 캔버스 세로 중심 ±5%
2. 표지·마무리 캔버스 중앙 (layout-cover/closing): 540px ±20px
3. 헤더바 12% 비율 (130px) 모든 본문 슬라이드 일관
4. 그림자·그라디언트·blur 금지 (KRDS flat)
5. 텍스트 over-flow (슬라이드 영역 밖, figure 잘림)
6. 이미지·텍스트 겹침 (figure ↔ copy 영역 침범 X)
7. 레이아웃 enum 위반 (5+4 본형·변형 외)

### 2. `scripts/capture-deck.sh` (신규)
```bash
for N in 0..18:
  chromium --headless --window-size=1920,1080 \
    --screenshot=content/chapters/$CH/visual-review/round-$R/slide-$N.png \
    "file://$PWD/content/chapters/$CH/slides/deck.html#/$N"
```

### 3. `scripts/run-visual-review.sh` (신규)
```bash
# director 가 호출. max 3 round.
for round in 1..3:
  cp deck.html deck.html.before-round-$round   # rollback snapshot
  capture-deck.sh $CH $round
  send-to-pane.sh visual-reviewer "task-chapter-$CH-visual-reviewer-round-$round"
  parse eval.json
  if issues_count == 0: status="done"; break
  if round > 1 && issues_count > prev_issues_count:
    cp deck.html.before-round-1 deck.html   # 회귀 → rollback
    status="manual_override"; break
  apply fix.patch (git apply || Edit fallback)
  STATE.json round 갱신
if round == 3 && issues > 0:
  status="manual_override"
```

### 4. `.claude/agents/director.md` (갱신)
chapter 워크플로 마지막에 한 단계 추가:
```
developer 완료 → reviewer × 3 (텍스트) → visual-reviewer × ≤3 (시각) → done
```

### 5. `scripts/start-session.sh` (갱신)
기존 5-pane 그리드 → 6-pane:
- pane 0 director (Opus)
- pane 1 decomposer / pane 2 composer
- pane 3 designer / pane 4 developer
- pane 5 **visual-reviewer** (신설, Sonnet 멀티모달)

### 6. `memory/visual_review_patterns.md` (신규)
자주 발견되는 issue 카테고리 + 통계 누적. 다음 챕터 designer/developer 가 사전 회피.

---

## Data Flow

### eval.json 형식
```json
{
  "round": 1,
  "issues_count": 2,
  "issues": [
    {
      "slide_id": "s05",
      "category": "figure-vertical-alignment",
      "observed": "figure 가 슬라이드 상단 1/3 영역",
      "expected": "body-area 세로 중앙 ±5%",
      "css_fix": "section.layout-image { height: 100%; }",
      "css_fix_location": "deck.html line ~365"
    }
  ]
}
```

### STATE.json 갱신
```json
"tasks": [{
  "id": "task-chapter-05-visual-reviewer",
  "role": "visual-reviewer",
  "status": "running|review|done|failed",
  "rounds": [
    {"round": 1, "issues_count": 2, "auto_fixed": true},
    {"round": 2, "issues_count": 0, "auto_fixed": false}
  ],
  "tokens_used": 12500,
  "cost_usd": 0
}]
```

### Sentinel 패턴 (기존)
`# AGENT_DONE_SIGNAL: task-chapter-NN-visual-reviewer-round-M`

---

## Error Handling

### 자동 fix 허용 카테고리
- CSS 속성 값 변경 (height/width/padding/margin/font-size 등)
- flex/grid 속성 (align-items, justify-content, display)
- color 토큰 (KRDS 팔레트 안에서)
- `section.layout-*` selector 의 단일 속성 추가

### 자동 fix 금지 → manual_override
- HTML 구조 변경 (div 추가/제거)
- 새 CSS class 정의
- 새 레이아웃 enum (5+4 외)
- 본문 컨텐츠 텍스트 변경
- 본문 font-size 44px 미만
- `!important` 추가
- raw HEX 색상 직접 (변수 외)
- 이미지 파일 src 변경

### Retry · Rollback
- max 3 round. issues=0 도달 또는 round 3 종료.
- 회귀 감지 (round N issues > round N-1): 즉시 rollback (가장 issues 적은 round 의 deck.html 복구) + manual_override.
- 각 round 시작 시 `deck.html.before-round-N` snapshot 자동.

### 외부 실패
- Chromium 미설치: 1s→10s→100s 백오프 3 회 → skip + warning ("visual-review unavailable")
- Sonnet API 일시 오류: sentinel 폴링 5분 타임아웃 → 3 회 retry → manual_override
- fix.patch 적용 실패: visual-reviewer 에게 css_fix 텍스트 재요청 → Edit 도구 fallback
- JSON malformed: 1 회 재요청 → 실패 시 manual_override

### PI 알림
- 대시보드 `recent_events` 에 round 별 issues_count 실시간
- manual_override 시 챕터 카드 빨강 강조 + STATE.json `error_message`
- 직렬 batch 중 manual_override 발생 시 director 정지 (skip 안 함)

---

## Testing (visual-reviewer 자체 검증)

도입 전 자기 평가 필수. chapter-01 의 정상 deck.html 에 의도적 결함 5 개 injecting:

1. `section.layout-image { height: 100% }` 제거 (figure 상단 정렬)
2. cover-content transform 제거 (캔버스 중앙 X)
3. body-text `font-size: 24px` (44 미만)
4. figure 의 `align-items: center` 제거
5. headers 에 `box-shadow` 추가 (KRDS 위반)

**통과 기준**:
- 5/5 결함 발견 (recall 100%)
- false positive 0 (원본 정상 deck 에 호출 → issues_count == 0)
- auto-fix 적용 후 회귀 0 (다른 슬라이드 안 깨짐)

통과 못 하면 시스템 도입 보류, PI 결정.

---

## Roll-out

| Stage | 범위 | 검증 |
|---|---|---|
| 1 | chapter-01 known-bad fixture | 5/5 + false positive 0 |
| 2 | 새 챕터 (예: chapter-11) 만 활성화 | 실제 워크플로 첫 통과 |
| 3 | chapter-01~10 회고적 실행 | 발견된 issues PI 결정 후 fix |
| 4 | 새 챕터 default 워크플로 통합 | Phase 3 진입 |

---

## 비용

| 항목 | 한 챕터 | 9 챕터 batch |
|---|---:|---:|
| PNG capture (Chromium) | ~30 초 | ~4.5 분 |
| visual-reviewer 토큰 (round 평균 1.5) | ~15k | ~135k |
| auto-fix 적용 시간 | ~5 초 | ~45 초 |
| **전체 추가 시간** | **+3-5 분** | **+30-45 분** |
| **실 결제** | **$0** | **$0** (Claude subscription 흡수) |

기존 chapter 한 개 15-25 분 → 18-30 분 (+15-20%).

---

## 의존성

- `chromium` (`brew install --cask chromium`) 또는 Google Chrome (headless 모드)
- 기존: `tmux`, `jq`, `claude` CLI, `codex` CLI 그대로

---

## Open Questions / Deferred Decisions

1. **시각 비교 baseline**: VRT (Visual Regression Test) 는 채택 안 함 (standalone 평가). 차후 챕터 간 일관성 검증 필요시 baseline 도입 검토.
2. **이미지 내용 검수**: 현재 정렬·레이아웃 전용. 이미지 자체의 한국어 라벨 오타·내용 정확성은 검수 X. 차후 reviewer 5/6 round 분리 검토.
3. **다국어**: visual-reviewer 의 평가 체크리스트는 KRDS 한국 디자인 특화. 영문 강의 적용 시 평가 체크리스트 일반화 필요.
4. **chapter-11~13 자료**: 현재 폴더에 없음. visual-review 자체와 별개로 자료 확보 필요.

---

## References

- chapter-01 PoC 5-cycle 디버깅 (commit 6e7f078 ~ e8579b9)
- `memory/deck_css_patterns.md` — figure 정렬 3 선행 조건 + 폰트 44 최저 + 디자인 시스템
- `memory/image_policy.md` — gpt-image-gen + 인물 wiki 정책
- `memory/codex_cli_capabilities.md` — codex image_gen.imagegen tool
- PRD/03_PHASES.md — Phase 1·2 완료 기록, Phase 3 진입 후보
- ONBOARDING.md — 세션 인계, 핵심 정책 요약
