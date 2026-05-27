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
`bash tests/visual-review/chapter-01-known-bad/run-validation.sh`

정상 deck 복구 후 5 개 fixture 만들고 각각 visual-reviewer 호출.
통과 기준: 5/5 결함 발견, false positive 0.
