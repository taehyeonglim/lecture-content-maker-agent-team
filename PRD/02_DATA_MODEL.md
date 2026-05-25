# lecture-content-maker-agent-team -- 데이터 모델

> 이 시스템의 "데이터"는 RDB row가 아니라 **파일 시스템 레이아웃 + STATE.json 스키마 + 4개 엔티티 추상**으로 구성됩니다.
> 각 에이전트는 명시적인 input/output 경로 컨벤션으로 핸드오프 — 컨벤션이 곧 스키마입니다.

---

## 전체 구조

```
  [Chapter]
     │
     ├─ 1:N ─> [AgentTask] ─ 1:N ─> [ReviewRound]
     │           (4개 role)              (round 1~3)
     │
     └─ 1:N ─> [Asset]  (image | citation, type 필드 구분)

  [SystemState]  (singleton — STATE.json, 대시보드용)
```

---

## 엔티티 상세

### Chapter
1개의 강의 챕터(주차 단위). Phase 1 MVP에서는 인스턴스 1개만, Phase 2부터 12-13개.

| 필드 | 설명 | 예시 | 필수 |
|---|---|---|---|
| id | 챕터 식별자 (`chapter-NN`) | chapter-01 | O |
| num | 챕터 번호 (1-13) | 1 | O |
| title | 챕터 제목 | "수업 설계의 기초" | O |
| status | 현재 단계 enum | designing | O |
| source_paths | 원본 자료 경로 리스트 | ["Previous_lecture_content/2026-1/1주차/"] | O |
| target_audience | 대상 학습자 | "교직과목 수강 학부생" | X |
| learning_objectives | 학습 목표 리스트 | ["수업 설계 핵심 요소 5가지 설명"] | X |
| created_at, updated_at | 타임스탬프 (ISO 8601) | 2026-05-25T10:00:00Z | O |

`status` enum: `planned → decomposed → composed → designed → developed → done`

### AgentTask
한 챕터 안에서 한 에이전트가 수행하는 작업 단위.

| 필드 | 설명 | 예시 | 필수 |
|---|---|---|---|
| id | 작업 식별자 | task-chapter-01-composer | O |
| chapter_id | 소속 챕터 | chapter-01 | O |
| role | 에이전트 역할 enum | composer | O |
| model | 사용한 모델 | gpt-5.5-high | O |
| status | 작업 상태 | running | O |
| input_paths | 입력 파일 리스트 | ["content/chapters/chapter-01/decomposed.md"] | O |
| output_path | 출력 파일 | content/chapters/chapter-01/composed.md | O |
| started_at | 시작 시각 | 2026-05-25T10:00:00Z | O |
| finished_at | 종료 시각 (null이면 진행 중) | 2026-05-25T10:15:00Z | X |
| retry_count | 재시도 횟수 | 0 | O |
| error_message | 실패 시 메시지 | null | X |

`role` enum: `decomposer | composer | designer | developer`
`model` enum: `opus-4-7 | gpt-5.5-medium | gpt-5.5-high | sonnet-latest`
`status` enum: `queued | running | review | done | failed`

### ReviewRound
한 AgentTask 산출물에 대한 한 라운드의 검수. 최대 3회.

| 필드 | 설명 | 예시 | 필수 |
|---|---|---|---|
| id | 검수 식별자 | review-task-chapter-01-composer-1 | O |
| agent_task_id | 검수 대상 작업 | task-chapter-01-composer | O |
| round | 라운드 번호 | 1 | O |
| reviewer_model | 검수자 모델 | gpt-5.5-xhigh | O |
| issues_count | 발견 이슈 수 | 3 | O |
| diff_path | 변경사항 diff 파일 | content/chapters/chapter-01/reviews/composer-round-1.diff | X |
| issues_summary | 이슈 요약 | "오탈자 2, 인용 오류 1" | X |
| passed | 통과 여부 (issues_count=0이면 true) | true | O |
| reviewed_at | 시각 | 2026-05-25T10:20:00Z | O |

`round`: 1, 2, 3 (3회까지)

### Asset
챕터에 부착되는 외부 자산. `type` 필드로 image와 citation 구분.

| 필드 | 설명 | 예시 | 필수 |
|---|---|---|---|
| id | 자산 식별자 | asset-chapter-01-img-001 | O |
| chapter_id | 소속 챕터 | chapter-01 | O |
| type | 자산 타입 | image | O |
| source | 출처 | wiki | O |
| path | 파일 경로 (image) | content/chapters/chapter-01/images/addie-diagram.png | X |
| url | 외부 URL (citation 또는 wiki source) | https://en.wikipedia.org/... | X |
| license | 라이선스 (image) | CC BY-SA 4.0 | X |
| attribution | 출처 표기 | "Wikimedia Commons / John Smith" | X |
| alt_text | 대체 텍스트 (image) | "ADDIE 모형의 5단계 흐름도" | X |
| citation_text | 참고문헌 표기 (citation, CSL JSON 필드 매핑 가능) | "Mayer, R. E. (2009). Multimedia learning..." | X |
| csl_json | CSL JSON 원본 (citation, Pandoc 변환용) | `{"type":"book","author":[{"family":"Mayer"...}],"issued":{"date-parts":[[2009]]},...}` | X |

`type` enum: `image | citation`
`source` enum: `wiki | gpt-image-gen | manual | book | paper | web | video`

**Citation 포맷**: `citations.json`은 [CSL JSON](https://docs.citationstyles.org/en/stable/specification.html) 배열로 저장. Pandoc으로 APA/MLA/한국교육자회 등 스타일 자동 변환 가능, Phase 3 교재화에 그대로 재사용.

### SystemState (singleton)
전체 시스템 진행상황. `STATE.json` 1파일.

```json
{
  "course": "교육방법및교육공학 2026-2",
  "overall_progress": 0.42,
  "cumulative_cost_usd": 2.37,
  "chapters": [
    {
      "id": "chapter-01",
      "num": 1,
      "title": "교육방법 및 교육공학 도입/개관",
      "status": "designing",
      "tasks": [
        { "role": "decomposer", "status": "done", "model": "gpt-5.5-medium", "reviews_passed": 3, "cost_usd": 0.42 },
        { "role": "composer",   "status": "done", "model": "gpt-5.5-high",   "reviews_passed": 2, "cost_usd": 1.18 },
        { "role": "designer",   "status": "running", "model": "sonnet-latest", "reviews_passed": 0, "cost_usd": 0.77 },
        { "role": "developer",  "status": "queued" }
      ]
    }
  ],
  "active_agents": ["designer:chapter-01"],
  "queue": [],
  "recent_events": [
    { "ts": "2026-05-25T10:30:00Z", "agent": "composer", "action": "completed", "chapter": "chapter-01" }
  ],
  "updated_at": "2026-05-25T10:30:00Z"
}
```

**비용 필드**: `cost_usd`는 각 task의 누적 API 비용(GPT 토큰 + 이미지 생성 등). `cumulative_cost_usd`는 전체 세션 합. 한도 없음 (PI가 대시보드에서 모니터링).

**업데이트 정책**: atomic write — `STATE.json.tmp` 작성 후 `mv STATE.json.tmp STATE.json`. director만 쓰고 다른 에이전트는 read-only.

---

## 관계 요약

- **Chapter 1 : N AgentTask** — 한 챕터에 최대 4개 작업 (decomposer/composer/designer/developer)
- **AgentTask 1 : N ReviewRound** — 한 작업에 최대 3개 검수 라운드
- **Chapter 1 : N Asset** — 한 챕터에 여러 이미지 + 여러 참고문헌
- **SystemState** — 시스템 전체에 인스턴스 1개 (전역 진행상황)

---

## 파일 시스템 레이아웃

```
lecture-content-maker-agent-team/
├── Previous_lecture_content/          # 이미 존재 — decomposer 입력 (read-only)
│   ├── 2023-2 교육방법및교육공학/
│   ├── 2025-1 교육방법및교육공학/
│   ├── 2025-2 교육방법및교육공학/
│   ├── 2026-1 교육방법및교육공학/
│   └── 목차_학지사_교육방법및교육공학.hwp
│
├── content/                           # 생성됨 — 산출물
│   └── chapters/
│       └── chapter-01/
│           ├── source/                # decomposer가 복사해온 원본 (캐시)
│           ├── decomposed.md          # decomposer 출력
│           ├── composed.md            # composer 출력 (장-절-항 줄글)
│           ├── DESIGN.md              # designer 출력 (시각 설계)
│           ├── slides/
│           │   ├── deck.md            # reveal.js source
│           │   ├── deck.html          # developer 빌드 결과
│           │   └── deck.pdf           # decktape auto-export
│           ├── images/                # Asset(type=image)
│           │   ├── addie-diagram.png
│           │   └── addie-diagram.meta.json   # license, attribution
│           ├── citations.json         # Asset(type=citation) 리스트
│           └── reviews/
│               ├── decomposer-round-1.md
│               ├── decomposer-round-2.md
│               ├── composer-round-1.diff
│               └── ...
│
├── STATE.json                         # SystemState (atomic write)
│
├── dashboard/                         # 로컬 정적 HTML 대시보드
│   ├── index.html
│   ├── poll.js                        # 5초 폴링
│   └── style.css
│
├── scripts/                           # bash 자동화
│   ├── start-session.sh               # tmux 5-pane 세션 부팅
│   ├── send-to-pane.sh                # send-keys 헬퍼
│   ├── run-review.sh                  # 검수 루프 실행기
│   ├── fetch-image.sh                 # Wikimedia + gpt-image-gen
│   └── export-pdf.sh                  # decktape 호출
│
├── prompts/                           # 에이전트 작업 프롬프트 템플릿
│   ├── decomposer/, composer/, designer/, developer/
│   └── reviewer/                      # 검수 루프 프롬프트
│
├── .claude/agents/                    # 5에이전트 시스템 정의
│   ├── director.md
│   ├── decomposer.md
│   ├── composer.md
│   ├── designer.md
│   └── developer.md
│
├── .env                               # 외부 API 키 (.gitignore 필수)
├── PRD/                               # 본 디자인 문서
└── README.md
```

---

## 왜 이 구조인가

- **파일 시스템 = 자연어 인터페이스**: 멀티에이전트가 file path로 핸드오프 — AI가 직접 read/write하기 가장 쉬운 형태. ORM/스키마 정의 불필요.
- **STATE.json singleton**: 단순 1파일로 대시보드/세션 복구/검색 모두 처리. Phase 1에 RDB 도입은 오버킬.
- **Asset 통합 (image+citation)**: 두 자산 모두 "챕터에 부착되는 외부 참조" 추상이라 type 필드로 구분. designer/developer 핸드오프 단순화.
- **확장성**: Phase 2의 Course/SourceArtifact 엔티티는 이 4-엔티티 위에 얹는 형태 (Chapter parent 관계만 추가) — 마이그레이션 비용 최소.
- **atomic write로 race 회피**: director가 STATE.json을 갱신할 때 다른 에이전트가 read 중일 수 있음 → temp 파일 + mv 패턴으로 보장.

---

## Phase 2 확장 (참고)

Phase 2 진입 시 추가될 엔티티:

- **Course**: 학기 단위. `id, title, semester, chapter_count(12|13), pi_name, target_use_date`
- **SourceArtifact**: `Previous_lecture_content/`의 개별 파일. `id, course_id, semester_src, path, type(pptx|gslides|hwp|doc|md), parsed_md_path`

관계 추가:
- Course 1 : N Chapter
- Course 1 : N SourceArtifact
- Chapter N : M SourceArtifact (한 챕터가 여러 원본을 참조, 한 원본이 여러 챕터에 쓰일 수 있음)

Phase 2 진입 시 검토:
- STATE.json이 너무 커지면 SQLite로 마이그레이션
- 이미지 통합 인덱스 (`assets-index.json`) 도입 — 챕터간 이미지 재사용 감지

---

## 결정 완료 / Spike 필요 항목

### 결정 완료 (2026-05-25)
- **composed.md 컨벤션**: `# 장 / ## 절 / ### 항` (표준 마크다운 위계)
- **citations.json 포맷**: CSL JSON (Citation Style Language)
- **DESIGN.md 스키마**: nexu-io/open-design 분석 후 채택/각색 (1주차 spike에서 확정)
- **retry_count 한도**: 3회 (지수 백오프 1s → 10s → 100s) — 04_PROJECT_SPEC.md 참조
- **SystemState 비용 필드**: `cost_usd` per task, `cumulative_cost_usd` 합산

### Spike / 운영 중 보정
- [ ] STATE.json 사이즈 한계 — Phase 2 다중 챕터 시점에 측정 후 SQLite 마이그레이션 판단
- [ ] `images/*.meta.json` vs 통합 인덱스 — Phase 2에서 다중 챕터간 이미지 재사용 시 정리
