const POLL_INTERVAL_MS = 2000;
const MAX_HISTORY_POINTS = 180;  // 2초 × 180 = 6분 슬라이딩 윈도우
const PREVIEW_RELOAD_INTERVAL_MS = 5000;  // deck.html mtime 폴링 주기
const STATE_URL = "/STATE.json";
const TASK_ROLES = ["decomposer", "composer", "designer", "developer"];
const usageHistory = [];  // {ts: Date, tokens, cost, calls} 시계열
let usageChart = null;
let previewChapterId = null;  // 현재 미리보기 중인 챕터 id
let previewLastMtime = null;  // 직전 deck.html 의 Last-Modified
let previewReloadTimer = null;

// status → 한글 라벨 (시각은 CSS .status-pill .status-<key> 에서 처리)
const STATUS_LABELS = {
  queued: "대기",
  running: "진행 중",
  review: "검수",
  done: "완료",
  failed: "실패",
  unknown: "—",
};
const KNOWN_STATUSES = ["queued", "running", "review", "done", "failed"];

let pollTimer = null;

function getElement(id) {
  return document.getElementById(id);
}

function setText(id, value) {
  const element = getElement(id);
  if (element) element.textContent = value;
}

function clearElement(element) {
  if (element) element.replaceChildren();
}

function clamp(value, min, max) {
  const low = Math.min(min, max);
  const high = Math.max(min, max);
  return Math.min(Math.max(value, low), high);
}

function toNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function toPercent(value) {
  const number = toNumber(value);
  return Math.round(clamp(number <= 1 ? number * 100 : number, 0, 100));
}

function formatCurrency(value) {
  return `$${toNumber(value).toFixed(2)}`;
}

function formatTokens(value) {
  const n = toNumber(value);
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return `${n}`;
}

function formatDuration(seconds) {
  const s = Math.max(0, Math.floor(toNumber(seconds)));
  if (s < 60) return `${s}초`;
  const m = Math.floor(s / 60);
  const rs = s % 60;
  if (m < 60) return `${m}분 ${rs}초`;
  const h = Math.floor(m / 60);
  const rm = m % 60;
  return `${h}시간 ${rm}분`;
}

// 모델별 색상 — 같은 모델은 세션 내내 동일 색상
const MODEL_COLORS = {
  "gpt-5.5":           "#2563eb",  // blue
  "claude-sonnet-4-6": "#16a34a",  // green
  "claude-opus-4-7":   "#dc2626",  // red
  "gpt-image-2":       "#ea580c",  // orange
  "unknown":           "#6b7280",  // gray
};
const COLOR_PALETTE = [
  "#9333ea", "#db2777", "#0d9488", "#ca8a04", "#475569", "#65a30d",
];
function hashString(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = ((h << 5) - h + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}
function colorForModel(model) {
  if (MODEL_COLORS[model]) return MODEL_COLORS[model];
  return COLOR_PALETTE[hashString(model) % COLOR_PALETTE.length];
}

function appendUsageSample(state) {
  const u = state.usage || {};
  const byModel = u.by_model || {};
  const ts = state.updated_at ? new Date(state.updated_at) : new Date();
  // by_model 객체에서 model → tokens 누적치 추출
  const modelTokens = {};
  for (const [model, info] of Object.entries(byModel)) {
    modelTokens[model] = toNumber(info && info.tokens);
  }
  const sample = { ts, modelTokens };
  // 직전 sample 과 같은 timestamp 면 덮어쓰기
  const last = usageHistory[usageHistory.length - 1];
  if (last && last.ts.getTime() === ts.getTime()) {
    usageHistory[usageHistory.length - 1] = sample;
  } else {
    usageHistory.push(sample);
    while (usageHistory.length > MAX_HISTORY_POINTS) usageHistory.shift();
  }
}

function fmtChartTime(date) {
  const h = String(date.getHours()).padStart(2, "0");
  const m = String(date.getMinutes()).padStart(2, "0");
  const s = String(date.getSeconds()).padStart(2, "0");
  return `${h}:${m}:${s}`;
}

function initUsageChart() {
  const canvas = document.getElementById("usage-chart");
  if (!canvas || typeof Chart === "undefined") return;
  const ctx = canvas.getContext("2d");
  const root = getComputedStyle(document.documentElement);
  const textColor = root.getPropertyValue("--text-muted").trim() || "#94a3b8";
  const gridColor = root.getPropertyValue("--border").trim() || "rgba(148,163,184,0.15)";
  const surface = root.getPropertyValue("--surface-elev").trim() || "rgba(31,41,55,0.9)";
  const textStrong = root.getPropertyValue("--text-strong").trim() || "#f8fafc";

  // Chart.js 글로벌 폰트
  Chart.defaults.font.family = "'Pretendard', 'Apple SD Gothic Neo', sans-serif";
  Chart.defaults.color = textColor;

  usageChart = new Chart(ctx, {
    type: "line",
    data: {
      labels: [],
      datasets: [],  // 모델 등장 시점에 동적으로 추가됨
    },
    options: {
      animation: false,
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      layout: { padding: { top: 8, right: 8 } },
      scales: {
        x: {
          ticks: {
            autoSkip: true,
            maxTicksLimit: 8,
            font: { size: 10, weight: "500" },
            color: textColor,
          },
          grid: { display: false },
          border: { color: gridColor },
        },
        y: {
          type: "linear",
          beginAtZero: true,
          ticks: {
            callback: function (v) { return formatTokens(v); },
            font: { size: 10, weight: "500" },
            color: textColor,
          },
          grid: { color: gridColor, lineWidth: 1 },
          border: { display: false },
          title: { display: false },
        },
      },
      plugins: {
        legend: {
          position: "bottom",
          labels: {
            font: { size: 12, weight: "600" },
            color: textStrong,
            usePointStyle: true,
            pointStyle: "circle",
            padding: 14,
          },
        },
        tooltip: {
          backgroundColor: surface,
          titleColor: textStrong,
          bodyColor: textStrong,
          borderColor: gridColor,
          borderWidth: 1,
          padding: 10,
          cornerRadius: 8,
          displayColors: true,
          boxPadding: 4,
          callbacks: {
            label: function (item) {
              return ` ${item.dataset.label}: ${formatTokens(item.parsed.y)}`;
            },
          },
        },
      },
    },
  });
}

function updateUsageChart() {
  if (!usageChart) return;
  // 1) usageHistory 의 모든 sample 에서 등장한 모델 집합
  const modelSet = new Set();
  for (const sample of usageHistory) {
    for (const m of Object.keys(sample.modelTokens || {})) modelSet.add(m);
  }
  const models = Array.from(modelSet).sort();

  // 2) 시간 라벨
  usageChart.data.labels = usageHistory.map((p) => fmtChartTime(p.ts));

  // 3) 모델별 dataset (서로 다른 색, 누적 토큰 시계열)
  //    이전 sample 에 그 모델이 없었더라도 0 으로 plot (선이 0 에서부터 자라남)
  usageChart.data.datasets = models.map((model) => {
    const color = colorForModel(model);
    return {
      label: model,
      data: usageHistory.map((sample) => toNumber((sample.modelTokens || {})[model])),
      borderColor: color,
      backgroundColor: color + "1f",  // 12% alpha
      tension: 0.25,
      fill: false,
      pointRadius: 0,
      pointHoverRadius: 4,
      borderWidth: 2,
      spanGaps: true,
    };
  });

  usageChart.update("none");
}

function deriveSessionDurationSec(usage) {
  if (!usage || !usage.session_started_at) return 0;
  const start = new Date(usage.session_started_at).getTime();
  if (Number.isNaN(start)) return 0;
  // last_call_at 이 있으면 그것까지, 없으면 현재 시각
  const end = usage.last_call_at
    ? new Date(usage.last_call_at).getTime()
    : Date.now();
  return Number.isFinite(end) ? Math.max(0, Math.round((end - start) / 1000)) : 0;
}

function formatDateTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "날짜 없음";
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(date);
}

function normalizeStatus(status) {
  const s = String(status || "queued");
  return KNOWN_STATUSES.includes(s) ? s : "queued";
}

function getStatusLabel(status) {
  return STATUS_LABELS[normalizeStatus(status)] || String(status || "queued");
}

// status → CSS 색상 변수 (chart bar 등 inline 색이 필요한 곳에서 사용)
function getStatusColor(status) {
  const s = normalizeStatus(status);
  const root = getComputedStyle(document.documentElement);
  return root.getPropertyValue(`--status-${s}`).trim() || "#94a3b8";
}

function getTaskProgress(task) {
  if (task && task.progress !== undefined) return toPercent(task.progress);
  if (!task) return 0;
  if (task.status === "done") return 100;
  if (task.status === "review") return 75;
  if (task.status === "running") return 45;
  if (task.status === "failed") return 100;
  return 0;
}

function createElement(tagName, className, text) {
  const element = document.createElement(tagName);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}

function applyStatusStyle(element, status) {
  // CSS 클래스 적용 (.status-pill .status-<key>) — color는 CSS variable로 처리됨
  element.classList.add("status-pill", `status-${normalizeStatus(status)}`);
}

function hideMessage() {
  const message = getElement("state-message");
  if (message) message.hidden = true;
}

function showMessage(text, tone = "error") {
  let message = getElement("state-message");
  if (!message) {
    message = createElement("div", "mx-auto my-4 max-w-5xl rounded border px-4 py-3 text-sm");
    message.id = "state-message";
    document.body.prepend(message);
  }
  message.hidden = false;
  message.textContent = text;
  message.style.color = tone === "error" ? "#991b1b" : "#1f2937";
  message.style.backgroundColor = tone === "error" ? "#fef2f2" : "#f9fafb";
  message.style.borderColor = tone === "error" ? "#fecaca" : "#d1d5db";
}

function updateOverallProgress(value) {
  const progress = toPercent(value);
  const element = getElement("overall-progress");
  setText("overall-progress-value", `${progress}%`);
  if (!element) return;
  element.setAttribute("aria-valuemin", "0");
  element.setAttribute("aria-valuemax", "100");
  element.setAttribute("aria-valuenow", String(progress));
  if (element.tagName === "PROGRESS" || element.tagName === "METER") {
    element.value = progress;
    element.max = 100;
    return;
  }
  const fill = element.querySelector("[data-progress-fill]") || element;
  fill.style.width = `${progress}%`;
  if (fill === element) element.textContent = `${progress}%`;
}

function renderStatusBadge(status) {
  const s = normalizeStatus(status);
  const badge = createElement("span", "");
  const dot = createElement("span", "status-dot");
  const labelSpan = createElement("span", "", getStatusLabel(s));
  badge.append(dot, labelSpan);
  applyStatusStyle(badge, s);
  return badge;
}

function renderTask(role, task) {
  const status = task && task.status ? task.status : "queued";
  const progress = getTaskProgress(task);
  const item = createElement("div", "task-tile");

  const header = createElement("div", "flex items-center justify-between gap-2");
  header.append(
    createElement("span", "text-xs font-semibold tracking-tight", role),
    renderStatusBadge(status),
  );

  const bar = createElement("div", "task-tile-progress");
  const fill = createElement("div", "task-tile-progress-fill");
  fill.style.width = `${progress}%`;
  fill.style.background = getStatusColor(status);
  bar.append(fill);

  const meta = createElement("div", "mt-1 text-[10px] leading-tight");
  meta.style.color = "var(--text-muted)";
  const reviewsPassed = task && task.reviews_passed !== undefined ? toNumber(task.reviews_passed) : 0;
  const model = task && task.model ? ` · ${task.model}` : "";
  const usagePart = (task && task.usage && (task.usage.tokens || task.usage.calls))
    ? ` · ${formatTokens(task.usage.tokens)}t(${toNumber(task.usage.calls)})`
    : "";
  const costPart = (task && task.cost_usd && toNumber(task.cost_usd) > 0)
    ? ` · ${formatCurrency(task.cost_usd)}`
    : "";
  meta.textContent = `검수${reviewsPassed}/3${model}${usagePart}${costPart}`;

  item.append(header, bar, meta);
  return item;
}

function renderChapterRow(chapter) {
  const c = chapter || {};
  const row = createElement("li", "chapter-row");
  row.dataset.chapterId = c.id || "";
  if (previewChapterId && c.id === previewChapterId) row.classList.add("is-active");

  // 헤더: 번호 + 제목 + 상태 pill
  const header = createElement("div", "chapter-row-header");
  const num = createElement("span", "chapter-row-num");
  num.textContent = c.num != null ? String(c.num).padStart(2, "0") : "??";
  const title = createElement("span", "chapter-row-title");
  title.textContent = c.title || c.id || "—";
  const statusBadge = renderStatusBadge(c.status || "queued");
  // 좁은 컬럼이라 pill 크기 더 줄임
  statusBadge.style.padding = "0.125rem 0.375rem";
  statusBadge.style.fontSize = "0.625rem";
  header.append(num, title, statusBadge);

  // 4 task 미니 진행도 막대
  const taskRow = createElement("div", "task-dots");
  taskRow.title = "decomposer · composer · designer · developer";
  const taskMap = new Map(
    (Array.isArray(c.tasks) ? c.tasks : [])
      .filter((t) => t && t.role)
      .map((t) => [t.role, t])
  );
  TASK_ROLES.forEach((role) => {
    const task = taskMap.get(role);
    const status = (task && task.status) || "queued";
    const progress = getTaskProgress(task);
    const dot = createElement("div", "task-dot");
    dot.title = `${role}: ${status}`;
    const fill = createElement("div", "task-dot-fill");
    fill.style.width = `${progress}%`;
    fill.style.background = getStatusColor(status);
    dot.append(fill);
    taskRow.append(dot);
  });

  // 클릭 시 preview 챕터 전환
  row.addEventListener("click", () => {
    previewChapterId = c.id;
    refreshPreviewIframe(true);
    // 즉시 active class 표시 (다음 polling 까지 기다리지 않게)
    document.querySelectorAll(".chapter-row").forEach((el) => el.classList.remove("is-active"));
    row.classList.add("is-active");
  });

  row.append(header, taskRow);
  return row;
}

function renderChapters(chapters) {
  const list = getElement("chapter-grid");
  if (!list) return;
  clearElement(list);
  setText("chapters-count", String(Array.isArray(chapters) ? chapters.length : 0));
  if (!Array.isArray(chapters) || chapters.length === 0) {
    const placeholder = createElement("li", "rounded-md border border-dashed px-2 py-1.5 text-[11px]");
    placeholder.style.borderColor = "var(--border-strong)";
    placeholder.style.color = "var(--text-muted)";
    placeholder.textContent = "표시할 챕터가 없습니다.";
    list.append(placeholder);
    return;
  }
  chapters.forEach((chapter) => list.append(renderChapterRow(chapter)));
}

function renderActiveAgents(activeAgents) {
  const container = getElement("active-agents");
  if (!container) return;
  clearElement(container);
  setText("active-agents-count", String(Array.isArray(activeAgents) ? activeAgents.length : 0));
  const itemTag = container.tagName === "UL" || container.tagName === "OL" ? "li" : "span";
  if (!Array.isArray(activeAgents) || activeAgents.length === 0) {
    const empty = createElement(itemTag, "rounded-md border border-dashed px-3 py-2 text-xs");
    empty.style.borderColor = "var(--border-strong)";
    empty.style.color = "var(--text-muted)";
    empty.textContent = "현재 실행 중인 에이전트가 없습니다";
    container.append(empty);
    return;
  }
  activeAgents.forEach((agent) => {
    const chip = createElement(itemTag, "agent-chip", String(agent));
    container.append(chip);
  });
}

/* ─────────── 라이브 교안 미리보기 ─────────── */

function pickPreviewChapter(chapters) {
  // 우선순위: 1) developer 가 running/review/done 인 챕터 (가장 최근)
  //          2) 명시적으로 클릭된 챕터 (previewChapterId 가 chapters 에 있으면 유지)
  //          3) chapters 첫 항목
  if (!Array.isArray(chapters) || chapters.length === 0) return null;
  if (previewChapterId) {
    const explicit = chapters.find((c) => c && c.id === previewChapterId);
    if (explicit) return explicit;
  }
  const inProgress = chapters
    .filter((c) => c && Array.isArray(c.tasks))
    .find((c) => {
      const dev = c.tasks.find((t) => t && t.role === "developer");
      return dev && ["running", "review", "done"].includes(dev.status);
    });
  return inProgress || chapters[0];
}

function deckUrlFor(chapterId) {
  return `/content/chapters/${chapterId}/slides/deck.html`;
}

function showPreviewEmpty(show) {
  const empty = getElement("preview-empty");
  if (empty) empty.style.display = show ? "flex" : "none";
}

function refreshPreviewIframe(force = false) {
  const iframe = getElement("deck-preview");
  const newTab = getElement("preview-newtab");
  if (!previewChapterId) {
    if (iframe) iframe.src = "about:blank";
    if (newTab) newTab.href = "#";
    showPreviewEmpty(true);
    return;
  }
  const url = deckUrlFor(previewChapterId);
  if (newTab) newTab.href = url;
  if (iframe && (force || iframe.src === "about:blank" || iframe.src.endsWith("about:blank"))) {
    iframe.src = `${url}?t=${Date.now()}`;
  }
}

function updateDeckPreview(state) {
  const target = pickPreviewChapter(state.chapters);
  setText("preview-chapter-label", target ? (target.id || "—") : "—");

  if (!target) {
    previewChapterId = null;
    refreshPreviewIframe();
    return;
  }

  // 챕터 변경 시 iframe src 교체
  if (target.id !== previewChapterId) {
    previewChapterId = target.id;
    previewLastMtime = null;
    refreshPreviewIframe(true);
  }
  // active class 동기화
  document.querySelectorAll(".chapter-row").forEach((row) => {
    row.classList.toggle("is-active", row.dataset.chapterId === previewChapterId);
  });
}

async function checkPreviewReload() {
  if (!previewChapterId) return;
  const url = deckUrlFor(previewChapterId);
  try {
    const resp = await fetch(url, { method: "HEAD", cache: "no-store" });
    if (!resp.ok) {
      // deck.html 아직 없음
      showPreviewEmpty(true);
      return;
    }
    const mtime = resp.headers.get("last-modified") || resp.headers.get("Last-Modified");
    if (mtime && mtime !== previewLastMtime) {
      previewLastMtime = mtime;
      const iframe = getElement("deck-preview");
      if (iframe) iframe.src = `${url}?t=${Date.now()}`;
      showPreviewEmpty(false);
    } else if (previewLastMtime) {
      // 이미 표시 중 — empty placeholder 숨김 유지
      showPreviewEmpty(false);
    } else {
      // 첫 진입에 mtime 만 받은 상태
      previewLastMtime = mtime;
      const iframe = getElement("deck-preview");
      if (iframe) iframe.src = `${url}?t=${Date.now()}`;
      showPreviewEmpty(false);
    }
  } catch (e) {
    // 무시 (네트워크 일시 오류)
  }
}

function startPreviewReload() {
  if (previewReloadTimer) return;
  previewReloadTimer = window.setInterval(checkPreviewReload, PREVIEW_RELOAD_INTERVAL_MS);
}

function stopPreviewReload() {
  if (!previewReloadTimer) return;
  window.clearInterval(previewReloadTimer);
  previewReloadTimer = null;
}

function setupPreviewControls() {
  const btn = getElement("preview-reload");
  if (btn) {
    btn.addEventListener("click", () => {
      previewLastMtime = null;
      refreshPreviewIframe(true);
    });
  }
}

function renderCompletedDecks(chapters) {
  const container = getElement("completed-decks");
  if (!container) return;
  clearElement(container);

  // developer task 가 review/done 인 챕터 = deck.html 이 빌드된 상태
  const completed = (Array.isArray(chapters) ? chapters : [])
    .map((c) => {
      if (!c || !Array.isArray(c.tasks)) return null;
      const dev = c.tasks.find((t) => t && t.role === "developer");
      if (!dev) return null;
      const ready = dev.status === "done" || dev.status === "review";
      return ready ? { chapter: c, dev } : null;
    })
    .filter(Boolean);

  setText("completed-decks-count", String(completed.length));

  if (completed.length === 0) {
    const empty = createElement("li", "rounded-md border border-dashed px-2.5 py-1.5 text-[11px]");
    empty.style.borderColor = "var(--border-strong)";
    empty.style.color = "var(--text-muted)";
    empty.textContent = "아직 완성된 교안 없음";
    container.append(empty);
    return;
  }

  completed.forEach(({ chapter, dev }) => {
    const item = createElement("li", "deck-item");

    // 좌측: 챕터 번호 + 제목
    const info = createElement("div", "min-w-0 flex-1");
    const num = createElement("p", "text-[9px] font-bold tracking-wider uppercase");
    num.style.color = "var(--accent)";
    num.textContent = chapter.num != null
      ? `Chapter ${String(chapter.num).padStart(2, "0")}`
      : (chapter.id || "Chapter");
    const title = createElement("p", "truncate text-[12px] font-semibold leading-tight");
    title.style.color = "var(--text-strong)";
    title.textContent = chapter.title || "—";
    info.append(num, title);

    // 우측: 보기 / PDF 버튼 (target=_blank)
    const actions = createElement("div", "flex shrink-0 gap-1");

    const htmlBtn = document.createElement("a");
    // 정적 서버가 프로젝트 루트(.)를 서빙하므로 /content/... 절대 경로 사용
    htmlBtn.href = `/content/chapters/${chapter.id}/slides/deck.html`;
    htmlBtn.target = "_blank";
    htmlBtn.rel = "noopener";
    htmlBtn.className = "deck-button";
    htmlBtn.textContent = "보기";
    htmlBtn.setAttribute("aria-label", `${chapter.title || chapter.id} 슬라이드덱을 새 창에서 열기`);

    const pdfBtn = document.createElement("a");
    pdfBtn.href = `/content/chapters/${chapter.id}/slides/deck.pdf`;
    pdfBtn.target = "_blank";
    pdfBtn.rel = "noopener";
    pdfBtn.className = "deck-button deck-button-secondary";
    pdfBtn.textContent = "PDF";
    pdfBtn.setAttribute("aria-label", `${chapter.title || chapter.id} PDF를 새 창에서 열기`);

    actions.append(htmlBtn, pdfBtn);
    item.append(info, actions);
    container.append(item);
  });
}

function eventSummary(event) {
  const eventData = event || {};
  const parts = [];
  if (eventData.agent) parts.push(String(eventData.agent));
  if (eventData.action) parts.push(String(eventData.action));
  if (eventData.chapter) parts.push(String(eventData.chapter));
  return parts.length > 0 ? parts.join(" · ") : "이벤트 내용 없음";
}

function renderRecentEvents(events) {
  const container = getElement("recent-events");
  if (!container) return;
  clearElement(container);
  if (!Array.isArray(events) || events.length === 0) {
    const empty = createElement("li", "rounded-md border border-dashed px-3 py-2 text-xs");
    empty.style.borderColor = "var(--border-strong)";
    empty.style.color = "var(--text-muted)";
    empty.textContent = "이벤트 없음";
    container.append(empty);
    return;
  }
  events
    .slice()
    .sort((a, b) => toNumber(new Date((b || {}).ts).getTime()) - toNumber(new Date((a || {}).ts).getTime()))
    .slice(0, 10)
    .forEach((event) => {
      const eventData = event || {};
      const item = createElement("li", "event-row");
      // 한 줄에 시각+요약 컴팩트 배치
      const time = createElement("span", "mono-number mr-2 text-[9px] font-bold uppercase tracking-wider");
      time.style.color = "var(--text-muted)";
      time.textContent = formatShortTime(eventData.ts);
      const summary = createElement("span", "text-[11px] font-medium leading-snug");
      summary.style.color = "var(--text-strong)";
      summary.textContent = eventSummary(eventData);
      item.append(time, summary);
      container.append(item);
    });
}

function formatShortTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  const h = String(date.getHours()).padStart(2, "0");
  const m = String(date.getMinutes()).padStart(2, "0");
  return `${h}:${m}`;
}

function updateDashboard(state) {
  hideMessage();
  setText("course-name", state.course || "강의명 없음");
  updateOverallProgress(state.overall_progress);
  const usage = state.usage || {};
  const tokens = formatTokens(usage.total_tokens);
  const calls = toNumber(usage.call_count);
  setText("cumulative-usage", `${tokens} 토큰`);  // chip value — 토큰만
  const durSec = deriveSessionDurationSec(usage);
  setText("session-duration", `${calls}회 · ${durSec > 0 ? formatDuration(durSec) : "-"}`);  // sub — 호출수·시간
  // 누적 USD 환산 비용 (config/pricing.json 기준, record-usage.sh가 누적)
  setText("cumulative-cost", formatCurrency(state.cumulative_cost_usd));
  renderChapters(state.chapters);
  renderActiveAgents(state.active_agents);
  renderCompletedDecks(state.chapters);
  renderRecentEvents(state.recent_events);
  updateDeckPreview(state);
  // 컴팩트 시각 표시 (HH:MM only)
  setText("updated-at", formatShortTime(state.updated_at));
  const updatedAt = getElement("updated-at");
  if (updatedAt) updatedAt.setAttribute("datetime", state.updated_at || "");
  // 시계열 sample 누적 + chart 업데이트
  appendUsageSample(state);
  updateUsageChart();
}

async function pollState() {
  try {
    const response = await fetch(STATE_URL, { cache: "no-store" });
    if (!response.ok) throw new Error(`STATE.json을 불러오지 못했습니다. HTTP ${response.status}`);
    updateDashboard(await response.json());
  } catch (error) {
    showMessage(
      `STATE.json을 아직 읽을 수 없습니다. 파이프라인을 시작했는지, 정적 서버에서 dashboard/를 열었는지 확인하세요. (${error.message})`,
    );
    setText("course-name", "대시보드 준비 중");
    updateOverallProgress(0);
    setText("cumulative-usage", "0 토큰");
    setText("session-duration", "0회 · -");
    setText("cumulative-cost", "$0.00");
    setText("updated-at", "-");
    const updatedAt = getElement("updated-at");
    if (updatedAt) updatedAt.removeAttribute("datetime");
    renderChapters([]);
    renderActiveAgents([]);
    renderCompletedDecks([]);
    renderRecentEvents([]);
  }
}

function startPolling() {
  if (pollTimer || document.visibilityState === "hidden") return;
  pollTimer = window.setInterval(pollState, POLL_INTERVAL_MS);
}

function stopPolling() {
  if (!pollTimer) return;
  window.clearInterval(pollTimer);
  pollTimer = null;
}

function handleVisibilityChange() {
  if (document.visibilityState === "hidden") {
    stopPolling();
    stopPreviewReload();
    return;
  }
  pollState();
  startPolling();
  startPreviewReload();
}

window.addEventListener("load", () => {
  initUsageChart();
  setupPreviewControls();
  startPreviewReload();
  pollState();
  startPolling();
});

document.addEventListener("visibilitychange", handleVisibilityChange);
