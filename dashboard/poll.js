const POLL_INTERVAL_MS = 5000;
const STATE_URL = "../STATE.json";
const TASK_ROLES = ["decomposer", "composer", "designer", "developer"];

const STATUS_STYLES = {
  queued: { label: "대기", color: "#6b7280", background: "#f3f4f6", border: "#d1d5db" },
  running: { label: "진행 중", color: "#1d4ed8", background: "#dbeafe", border: "#93c5fd" },
  review: { label: "검수", color: "#a16207", background: "#fef3c7", border: "#facc15" },
  done: { label: "완료", color: "#15803d", background: "#dcfce7", border: "#86efac" },
  failed: { label: "실패", color: "#b91c1c", background: "#fee2e2", border: "#fca5a5" },
};

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

function getStatusStyle(status) {
  return STATUS_STYLES[status] || STATUS_STYLES.queued;
}

function getStatusLabel(status) {
  return STATUS_STYLES[status] ? STATUS_STYLES[status].label : String(status || "queued");
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
  const style = getStatusStyle(status);
  element.style.color = style.color;
  element.style.backgroundColor = style.background;
  element.style.borderColor = style.border;
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
  const badge = createElement(
    "span",
    "inline-flex items-center rounded border px-2 py-0.5 text-xs font-medium",
    getStatusLabel(status),
  );
  applyStatusStyle(badge, status);
  return badge;
}

function renderTask(role, task) {
  const status = task && task.status ? task.status : "queued";
  const progress = getTaskProgress(task);
  const item = createElement("div", "rounded border border-gray-200 p-3");

  const header = createElement("div", "mb-2 flex items-center justify-between gap-2");
  header.append(
    createElement("span", "text-sm font-semibold text-gray-900", role),
    renderStatusBadge(status),
  );

  const bar = createElement("div", "h-2 overflow-hidden rounded bg-gray-100");
  const fill = createElement("div", "h-full rounded");
  fill.style.width = `${progress}%`;
  fill.style.backgroundColor = getStatusStyle(status).color;
  bar.append(fill);

  const meta = createElement("div", "mt-2 text-xs text-gray-600");
  const reviewsPassed = task && task.reviews_passed !== undefined ? toNumber(task.reviews_passed) : 0;
  const model = task && task.model ? ` · ${task.model}` : "";
  const cost = task && task.cost_usd !== undefined ? ` · ${formatCurrency(task.cost_usd)}` : "";
  meta.textContent = `검수 통과 ${reviewsPassed}/3${model}${cost}`;

  item.append(header, bar, meta);
  return item;
}

function renderChapterCard(chapter) {
  const chapterData = chapter || {};
  const card = createElement("article", "rounded border border-gray-200 bg-white p-4 shadow-sm");
  const header = createElement("div", "mb-4 flex items-start justify-between gap-3");
  const titleGroup = createElement("div");
  titleGroup.append(
    createElement("p", "text-xs font-medium text-gray-500", chapterData.id || `chapter-${chapterData.num || "?"}`),
    createElement("h2", "mt-1 text-base font-semibold text-gray-950", chapterData.title || "제목 없음"),
  );
  header.append(titleGroup, renderStatusBadge(chapterData.status || "queued"));

  const taskMap = new Map(
    (Array.isArray(chapterData.tasks) ? chapterData.tasks : [])
      .filter((task) => task && task.role)
      .map((task) => [task.role, task]),
  );
  const taskGrid = createElement("div", "grid gap-3 md:grid-cols-2");
  TASK_ROLES.forEach((role) => taskGrid.append(renderTask(role, taskMap.get(role))));

  card.append(header, taskGrid);
  return card;
}

function renderChapters(chapters) {
  const grid = getElement("chapter-grid");
  if (!grid) return;
  clearElement(grid);
  if (!Array.isArray(chapters) || chapters.length === 0) {
    grid.append(createElement("p", "text-sm text-gray-500", "표시할 챕터가 아직 없습니다."));
    return;
  }
  chapters.forEach((chapter) => grid.append(renderChapterCard(chapter)));
}

function renderActiveAgents(activeAgents) {
  const container = getElement("active-agents");
  if (!container) return;
  clearElement(container);
  setText("active-agents-count", String(Array.isArray(activeAgents) ? activeAgents.length : 0));
  const itemTag = container.tagName === "UL" || container.tagName === "OL" ? "li" : "span";
  if (!Array.isArray(activeAgents) || activeAgents.length === 0) {
    container.append(createElement(itemTag, "text-sm text-gray-500", "현재 실행 중인 에이전트가 없습니다."));
    return;
  }
  activeAgents.forEach((agent) => {
    const chip = createElement(itemTag, "inline-flex rounded-full border px-3 py-1 text-sm font-medium", String(agent));
    chip.style.color = "#1d4ed8";
    chip.style.backgroundColor = "#dbeafe";
    chip.style.borderColor = "#93c5fd";
    container.append(chip);
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
    container.append(createElement("li", "text-sm text-gray-500", "최근 이벤트가 없습니다."));
    return;
  }
  events
    .slice()
    .sort((a, b) => toNumber(new Date((b || {}).ts).getTime()) - toNumber(new Date((a || {}).ts).getTime()))
    .slice(0, 10)
    .forEach((event) => {
      const eventData = event || {};
      const item = createElement("li", "rounded border border-gray-200 p-3");
      item.append(
        createElement("time", "block text-xs text-gray-500", formatDateTime(eventData.ts)),
        createElement("p", "mt-1 text-sm text-gray-900", eventSummary(eventData)),
      );
      container.append(item);
    });
}

function updateDashboard(state) {
  hideMessage();
  setText("course-name", state.course || "강의명 없음");
  updateOverallProgress(state.overall_progress);
  setText("cumulative-cost", formatCurrency(state.cumulative_cost_usd));
  renderChapters(state.chapters);
  renderActiveAgents(state.active_agents);
  renderRecentEvents(state.recent_events);
  setText("updated-at", formatDateTime(state.updated_at));
  const updatedAt = getElement("updated-at");
  if (updatedAt) updatedAt.setAttribute("datetime", state.updated_at || "");
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
    setText("cumulative-cost", "$0.00");
    setText("updated-at", "업데이트 없음");
    const updatedAt = getElement("updated-at");
    if (updatedAt) updatedAt.removeAttribute("datetime");
    renderChapters([]);
    renderActiveAgents([]);
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
    return;
  }
  pollState();
  startPolling();
}

window.addEventListener("load", () => {
  pollState();
  startPolling();
});

document.addEventListener("visibilitychange", handleVisibilityChange);
