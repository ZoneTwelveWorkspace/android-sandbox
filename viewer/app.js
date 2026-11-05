"use strict";
const $ = (id) => document.getElementById(id);
const CATS = window.CATEGORIES, TOOLS = window.TOOLS;
const app = { events: new Map(), rev: 0, boot: null, tools: [], selected: null, follow: true, mode: "ai", phase: "after", side: "detail", meta: {}, online: null, liveLoaded: false };

// Screen text comes from apps and may be hostile, so every value goes through text nodes and never through HTML.
function el(tag, props, ...kids) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (k === "class") node.className = v;
    else if (k === "style") for (const [p, x] of Object.entries(v)) node.style.setProperty(p, x);
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null) node.setAttribute(k, v);
  }
  for (const kid of kids) if (kid !== null && kid !== undefined) node.append(kid);
  return node;
}

function parseState(text) {
  const state = { w: 0, h: 0, nodes: [], app: null, title: null };
  let win = null, topApp = null;
  for (const line of (text || "").split("\n")) {
    const screen = line.match(/^screen:(\d+)x(\d+)/);
    if (screen) { state.w = +screen[1]; state.h = +screen[2]; continue; }
    if (line.startsWith("--- window:")) {
      win = { type: (line.match(/type:(\S+)/) || [])[1], pkg: (line.match(/pkg:(\S+)/) || [])[1], title: (line.match(/title:(.*?) (?:activity|layer):/) || [])[1], focused: /focused:true/.test(line), order: state.windows = (state.windows || 0) + 1 };
      if (win.type === "APPLICATION" && (win.focused || !topApp)) { topApp = win; state.app = win.pkg; state.title = win.title; }
      continue;
    }
    if (!line.startsWith("node_") || !line.includes("\t")) continue;
    const c = line.split("\t");
    if (c[0] === "node_id" || c.length < 7) continue;
    const b = c[5].split(",").map(Number);
    if (b.length !== 4 || b.some(Number.isNaN)) continue;
    const dash = (v) => (v === "-" ? "" : v);
    const flags = new Set(c[6].split(","));
    state.nodes.push({ id: c[0], cls: c[1], text: dash(c[2]), desc: dash(c[3]), res: dash(c[4]), box: b, flags, win: win ? win.order : 0, pkg: win && win.pkg });
  }
  return state.w && state.nodes.length ? state : null;
}

const nodeName = (n) => n.text || n.desc || (n.res ? n.res.split("/").pop() : "") || n.cls;
const area = (n) => (n.box[2] - n.box[0]) * (n.box[3] - n.box[1]);
const eventsInOrder = () => [...app.events.values()].sort((a, b) => a.id - b.id);
const feedEvents = () => eventsInOrder().filter((e) => e.source === "ai");

// Text never changes once an event ends, so each state is parsed only once.
function stateOf(e) {
  if (e.tool !== "android_get_screen_state" || e.status !== "ok") return null;
  if (e._state === undefined) e._state = parseState(e.text);
  return e._state;
}

function stateBefore(id) {
  let found = null;
  for (const e of eventsInOrder()) { if (e.id >= id) break; const s = stateOf(e); if (s) found = { state: s, event: e }; }
  return found;
}

function stateAfter(id) {
  for (const e of eventsInOrder()) { if (e.id < id) continue; const s = stateOf(e); if (s) return { state: s, event: e }; }
  return null;
}

function latestState() {
  const all = eventsInOrder();
  for (let i = all.length - 1; i >= 0; i--) { const s = stateOf(all[i]); if (s) return { state: s, event: all[i] }; }
  return null;
}

function findNode(id, event) {
  if (!id) return null;
  for (const e of eventsInOrder().reverse()) { if (e.id > event.id) continue; const s = stateOf(e); const n = s && s.nodes.find((x) => x.id === id); if (n) return n; }
  return null;
}

function nodeAt(state, x, y) {
  if (!state) return null;
  const hits = state.nodes.filter((n) => n.flags.has("on") && x >= n.box[0] && x <= n.box[2] && y >= n.box[1] && y <= n.box[3]);
  const named = hits.filter((n) => n.text || n.desc);
  return (named.length ? named : hits).sort((a, b) => a.win - b.win || area(a) - area(b))[0] || null;
}

const quote = (s, max = 60) => { const t = String(s ?? ""); return "「" + (t.length > max ? t.slice(0, max) + "…" : t) + "」"; };
const DIRS = { up: "往上", down: "往下", left: "往左", right: "往右" };

function describe(e) {
  const a = e.args || {};
  if (e.method === "initialize") return "AI 連上了手機" + (a.clientInfo && a.clientInfo.name ? "（" + a.clientInfo.name + "）" : "");
  if (e.method === "tools/list") return "AI 查看自己能用哪些工具";
  if (e.method !== "tools/call") return "AI 送出 " + e.method;
  const before = stateBefore(e.id);
  const target = (id) => { const n = findNode(id, e); return n ? quote(nodeName(n)) : "元素 " + id; };
  const at = () => { const n = nodeAt(before && before.state, a.x, a.y); return n ? "，那裡是" + quote(nodeName(n)) : ""; };
  switch (e.tool) {
    case "android_get_screen_state": return a.include_screenshot ? "AI 讀取畫面，並拿了一張截圖" : "AI 讀取畫面的元素清單（沒有截圖）";
    case "android_tap": return `AI 點了座標 (${a.x}, ${a.y})${at()}`;
    case "android_long_press": return `AI 長按座標 (${a.x}, ${a.y})${at()}`;
    case "android_double_tap": return `AI 連點兩下座標 (${a.x}, ${a.y})${at()}`;
    case "android_swipe": return `AI 從 (${a.x1}, ${a.y1}) 滑到 (${a.x2}, ${a.y2})`;
    case "android_scroll": return `AI ${DIRS[a.direction] || a.direction}捲動畫面`;
    case "android_pinch": return `AI 在 (${a.center_x}, ${a.center_y}) ${a.scale > 1 ? "放大" : "縮小"}畫面`;
    case "android_click_node": case "android_tap_node": return "AI 點了" + target(a.node_id);
    case "android_long_click_node": return "AI 長按" + target(a.node_id);
    case "android_scroll_to_node": return "AI 捲動畫面到" + target(a.node_id);
    case "android_type_append_text": return `AI 在${target(a.node_id)}打字：${quote(a.text)}`;
    case "android_type_insert_text": return `AI 在${target(a.node_id)}插入：${quote(a.text)}`;
    case "android_type_replace_text": return `AI 把${target(a.node_id)}裡的${quote(a.search)}改成${quote(a.new_text)}`;
    case "android_type_clear_text": return "AI 清空" + target(a.node_id);
    case "android_press_key": return `AI 按下 ${a.key} 鍵`;
    case "android_find_nodes": return `AI 尋找${quote(a.value)}`;
    case "android_get_node_details": return "AI 讀取元素的完整文字";
    case "android_wait_for_node": return `AI 等待${quote(a.value)}出現`;
    case "android_open_app": case "android_close_app": return `AI ${e.tool === "android_open_app" ? "開啟" : "關閉"} App ${a.package_id}`;
    case "android_open_uri": return `AI 開啟連結 ${a.uri}`;
    case "android_send_intent": return `AI 送出 Intent ${a.action || a.component || ""}`.trim();
    case "android_set_clipboard": return `AI 把${quote(a.text)}放進剪貼簿`;
    case "android_read_file": case "android_write_file": case "android_append_file": case "android_file_replace": case "android_delete_file": case "android_share_file_via_web":
      return `AI ${TOOLS[e.tool][1]}：${a.path}`;
    case "android_list_files": return `AI 查看資料夾 ${a.path || "/"}`;
    case "android_download_from_url": return `AI 下載 ${a.url} 到 ${a.path}`;
  }
  const known = TOOLS[e.tool];
  return known ? "AI " + known[1] : "AI 呼叫 " + e.tool;
}

function outcome(e) {
  if (e.status === "running") return "執行中…";
  if (e.status === "error") {
    if (/HTTP 401/.test(e.error || "")) return "失敗：token 不對";
    return "失敗：" + (e.error || e.text.split("\n").filter(Boolean).pop() || "手機回報錯誤").slice(0, 160);
  }
  const s = stateOf(e);
  if (s) { const seen = s.nodes.filter((n) => n.flags.has("on")).length; return `看到 ${seen} 個元素` + (s.app ? `，目前在 ${s.app}` : ""); }
  if (e.method === "tools/list") { return `共有 ${app.tools.length} 種工具`; }
  return "成功";
}

function markerFor(e, state) {
  if (!e || !e.tool) return null;
  const a = e.args || {};
  if (a.node_id && typeof a.node_id === "string") { const n = findNode(a.node_id, e); return n ? { box: n.box, label: nodeName(n) } : null; }
  if (e.tool === "android_swipe") return { line: [[a.x1, a.y1, a.x2, a.y2]] };
  if (e.tool === "android_pinch") return { point: [a.center_x, a.center_y] };
  if (e.tool === "android_scroll" && state) {
    const x = state.w / 2, y = state.h / 2, d = state.h / 4;
    const delta = { up: [0, d], down: [0, -d], left: [d, 0], right: [-d, 0] }[a.direction];
    return delta ? { line: [[x, y, x + delta[0], y + delta[1]]] } : null;
  }
  if (e.tool === "android_custom_gesture" && Array.isArray(a.paths)) {
    const line = [];
    for (const path of a.paths) { const pts = Array.isArray(path) ? path : path.points || []; for (let i = 1; i < pts.length; i++) line.push([pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y]); }
    return line.length ? { line } : null;
  }
  if (typeof a.x === "number" && typeof a.y === "number") return { point: [a.x, a.y] };
  return null;
}

const pct = (v, total) => (v / total) * 100 + "%";

function addMarker(stage, marker, state) {
  if (!marker || !state) return;
  if (marker.box) {
    const b = marker.box;
    stage.append(el("div", { class: "mark-box", style: { left: pct(b[0], state.w), top: pct(b[1], state.h), width: pct(b[2] - b[0], state.w), height: pct(b[3] - b[1], state.h) } }));
  }
  if (marker.point) stage.append(el("div", { class: "mark-point", style: { left: pct(marker.point[0], state.w), top: pct(marker.point[1], state.h) } }));
  if (marker.line) {
    const ns = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", `0 0 ${state.w} ${state.h}`);
    svg.setAttribute("class", "mark-line");
    for (const [x1, y1, x2, y2] of marker.line) {
      const l = document.createElementNS(ns, "line");
      Object.entries({ x1, y1, x2, y2 }).forEach(([k, v]) => l.setAttribute(k, v));
      svg.append(l);
    }
    const last = marker.line[marker.line.length - 1];
    const dot = document.createElementNS(ns, "circle");
    Object.entries({ cx: last[2], cy: last[3], r: 9 }).forEach(([k, v]) => dot.setAttribute(k, v));
    svg.append(dot);
    stage.append(svg);
  }
}

function renderWireframe(stage, state) {
  const nodes = state.nodes.filter((n) => n.flags.has("on") && (n.text || n.desc || n.flags.has("clk") || n.flags.has("edt") || n.flags.has("scr")));
  // Later windows sit underneath, so they are drawn first. Larger nodes go first within a window.
  nodes.sort((a, b) => b.win - a.win || area(b) - area(a));
  for (const n of nodes) {
    const kind = n.flags.has("edt") ? "edt" : n.flags.has("clk") ? "clk" : n.flags.has("scr") ? "scr" : "txt";
    const b = n.box;
    stage.append(el("div", { class: "node " + kind, title: `${nodeName(n)}\n${n.cls} · ${n.res || "無 ID"}\n(${b.join(", ")})`, style: { left: pct(b[0], state.w), top: pct(b[1], state.h), width: pct(b[2] - b[0], state.w), height: pct(b[3] - b[1], state.h) } }, n.text || n.desc ? el("span", {}, n.text || n.desc) : null));
  }
}

function setCaption(text) { $("caption").textContent = text; }

function renderStage() {
  const stage = $("stage");
  const sel = app.selected && app.events.get(app.selected);
  const isAction = sel && sel.tool && !stateOf(sel) && sel.source === "ai";
  $("phase").hidden = !isAction || app.mode === "live";
  document.querySelectorAll("#phase button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.phase === app.phase)));
  $("legend").hidden = app.mode !== "ai";
  stage.classList.toggle("live", app.mode === "live");

  if (app.mode === "live") {
    if (!app.liveLoaded && app.meta.webPort) {
      stage.replaceChildren(el("iframe", { title: "手機即時畫面（唯讀）", src: `http://127.0.0.1:${app.meta.webPort}/vnc.html?autoconnect=1&resize=scale&view_only=1&v=2` }));
      app.liveLoaded = true;
    }
    setCaption("這是手機現在的樣子（唯讀），不是 AI 看到的內容。AI 要讀取畫面後才看得到。");
    return;
  }
  app.liveLoaded = false;

  let picked = null;
  if (sel) {
    if (stateOf(sel)) picked = { state: stateOf(sel), event: sel };
    else if (app.phase === "before") picked = stateBefore(sel.id) || stateAfter(sel.id);
    else picked = (app.follow ? latestState() : stateAfter(sel.id)) || stateBefore(sel.id);
  } else picked = latestState();

  stage.replaceChildren();
  if (!picked) {
    stage.style.removeProperty("--r");
    stage.append(el("p", { class: "empty" }, "還沒有畫面。按「重新讀取」試試；如果沒反應，請確認手機已開機。"));
    setCaption("");
    return;
  }
  const { state, event } = picked;
  stage.style.setProperty("--r", String(state.w / state.h));
  const when = new Date(event.ts * 1000).toLocaleTimeString("zh-TW", { hour12: false });
  const who = event.source === "ai" ? "AI 讀取" : "檢視器替你讀取，AI 沒有看到這一份";
  if (app.mode === "ai") {
    stage.classList.add("wire");
    renderWireframe(stage, state);
    setCaption(`這是元素清單畫成的樣子。AI 只有另外要截圖時，才看得到顏色和圖片（${who}，${when}）。`);
  } else {
    stage.classList.remove("wire");
    const image = event.images && event.images.find(Boolean);
    if (image) stage.append(el("img", { src: "/api/image/" + image, alt: "當時的手機截圖" }));
    else stage.append(el("p", { class: "empty" }, "這次讀取沒有截圖。"));
    setCaption(`截圖上的紅框和編號是手機的 MCP 加上的，AI 拿到的就是這樣（${who}，${when}）。`);
  }
  addMarker(stage, isAction ? markerFor(sel, state) : null, state);
}

function renderFeed() {
  const feed = $("feed");
  const events = feedEvents().reverse();
  if (!events.length) {
    const prefix = app.meta.name && app.meta.name !== "android-fc" ? `AVM_NAME=${app.meta.name} ` : "";
    feed.replaceChildren(el("li", { class: "onboard" },
      el("h3", {}, "AI 還沒有經過這裡"),
      el("p", {}, "把 AI 連到這個網址，它的每個操作才會出現在這裡："),
      el("code", {}, `http://127.0.0.1:${app.meta.port || ""}/mcp`),
      el("p", {}, "Claude Code 可以直接執行："),
      el("code", {}, `${prefix}VIEW=1 ./avm mcp add android-view`),
      el("p", { class: "muted" }, "直接連手機原本 MCP port 的 AI 不會被記錄。")));
    return;
  }
  feed.replaceChildren(...events.map((e) => {
    const known = TOOLS[e.tool];
    const cat = e.tool ? CATS[known ? known[0] : "other"] : "連線";
    const time = new Date(e.ts * 1000).toLocaleTimeString("zh-TW", { hour12: false });
    return el("li", { class: "item " + e.status + (e.id === app.selected ? " on" : "") },
      el("button", { "aria-current": e.id === app.selected ? "true" : null, onclick: () => select(e.id) },
        el("span", { class: "line1" }, el("span", { class: "cat" }, cat), el("time", {}, time)),
        el("span", { class: "say" }, describe(e)),
        el("span", { class: "result" }, outcome(e) + (e.ms !== null ? ` · ${e.ms < 1000 ? e.ms + " 毫秒" : (e.ms / 1000).toFixed(1) + " 秒"}` : ""))));
  }));
}

function renderDetail(side) {
  const e = app.selected && app.events.get(app.selected);
  if (!e) { side.replaceChildren(el("p", { class: "empty" }, "點左邊任何一步，這裡會顯示 AI 送了什麼、手機回了什麼。")); return; }
  const known = TOOLS[e.tool];
  const server = app.tools.find((t) => t.name === e.tool);
  side.replaceChildren(...[
    el("h3", {}, describe(e)),
    el("p", { class: "result " + e.status }, outcome(e)),
    known ? el("p", {}, known[2]) : server ? el("p", { lang: "en" }, server.description) : null,
    el("h4", {}, "AI 送出的內容"),
    el("pre", {}, JSON.stringify(e.tool ? { 工具: e.tool, 參數: e.args } : { 方法: e.method, 參數: e.args }, null, 2)),
    el("h4", {}, "手機回傳的內容"),
    (e.images || []).filter(Boolean).length ? el("p", { class: "muted" }, "另外附了一張截圖，可在「截圖」分頁查看。") : null,
    el("pre", {}, e.error || e.text || "（沒有文字內容）")].filter(Boolean));
}

function renderCatalog(side) {
  const used = new Map();
  for (const e of feedEvents()) if (e.tool) used.set(e.tool, (used.get(e.tool) || 0) + 1);
  const groups = new Map(Object.keys(CATS).map((k) => [k, []]));
  for (const t of app.tools) { const k = TOOLS[t.name] ? TOOLS[t.name][0] : "other"; groups.get(k).push(t); }
  const blocks = [];
  for (const [k, list] of groups) {
    if (!list.length) continue;
    blocks.push(el("h4", {}, `${CATS[k]}（${list.length}）`), el("ul", { class: "catalog" }, ...list.map((t) => {
      const known = TOOLS[t.name], n = used.get(t.name) || 0;
      return el("li", {}, el("div", { class: "row" }, el("b", {}, known ? known[1] : t.name), n ? el("span", { class: "count" }, `用了 ${n} 次`) : null), el("span", { lang: known ? null : "en" }, known ? known[2] : t.description || ""), el("code", {}, t.name));
    })));
  }
  side.replaceChildren(el("p", {}, app.tools.length ? `這支手機開放 ${app.tools.length} 種工具給 AI 使用。` : "還沒讀到工具清單。"), ...blocks);
}

function renderSide() { const side = $("side"); if (app.side === "detail") renderDetail(side); else renderCatalog(side); }

function renderStatus() {
  const s = $("status");
  const count = feedEvents().length;
  const phone = app.online === false ? "連不上這個頁面的伺服器" : (latestState() ? "手機已連線" : "等待手機回應");
  s.className = "status " + (app.online === false ? "bad" : latestState() ? "good" : "wait");
  s.textContent = `${phone} · 已記錄 ${count} 步`;
}

function renderAll() { renderFeed(); renderSide(); renderStage(); renderStatus(); }

function select(id) { app.selected = id; app.follow = false; $("follow").checked = false; renderAll(); }

async function poll() {
  try {
    const r = await fetch(`/api/events?since=${app.rev}`);
    const data = await r.json();
    if (data.boot !== app.boot) { app.events.clear(); app.selected = null; app.boot = data.boot; if (app.rev) { app.rev = 0; return; } }
    const changed = data.events.length > 0 || app.online !== true;
    app.online = true;
    app.rev = data.rev;
    app.tools = data.tools;
    for (const e of data.events) app.events.set(e.id, e);
    if (app.follow) { const list = feedEvents(); app.selected = list.length ? list[list.length - 1].id : null; }
    if (changed) renderAll();
  } catch (err) {
    if (app.online !== false) { app.online = false; renderStatus(); }
  } finally { setTimeout(poll, 800); }
}

function bindTabs() {
  document.querySelectorAll("[data-mode]").forEach((b) => b.addEventListener("click", () => {
    app.mode = b.dataset.mode;
    document.querySelectorAll("[data-mode]").forEach((x) => x.setAttribute("aria-selected", String(x === b)));
    renderStage();
  }));
  document.querySelectorAll("[data-side]").forEach((b) => b.addEventListener("click", () => {
    app.side = b.dataset.side;
    document.querySelectorAll("[data-side]").forEach((x) => x.setAttribute("aria-selected", String(x === b)));
    renderSide();
  }));
  document.querySelectorAll("[data-phase]").forEach((b) => b.addEventListener("click", () => { app.phase = b.dataset.phase; renderStage(); }));
  $("follow").addEventListener("change", (ev) => { app.follow = ev.target.checked; if (app.follow) { const l = feedEvents(); app.selected = l.length ? l[l.length - 1].id : null; renderAll(); } });
  $("refresh").addEventListener("click", () => fetch("/api/refresh", { method: "POST" }));
}

(async function start() {
  bindTabs();
  try { app.meta = await (await fetch("/api/meta")).json(); $("vm").textContent = `${app.meta.name} · MCP ${app.meta.mcpPort}`; } catch (err) { /* poll reports the outage */ }
  renderAll();
  poll();
})();
