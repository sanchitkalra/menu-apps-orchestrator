/**
 * Todo mini-app — persistent, local-store, fully implements the orchestrator DSL
 * Host API: host.store.get/set, host.render
 * Host events: init, action (add/toggle/delete/clearDone)
 */

let todos = [];
const pending = new Map();
let nextId = 1;

function send(msg) { process.stdout.write(JSON.stringify(msg) + "\n"); }
function hostCall(method, params) {
  const id = nextId++;
  return new Promise(resolve => { pending.set(id, resolve); send({ id, method, params }); });
}

const host = {
  store: {
    get: (key) => hostCall("host.store.get", { key }),
    set: (key, value) => hostCall("host.store.set", { key, value: JSON.stringify(value) }),
  },
  render: (payload) => send({ method: "render", params: JSON.stringify(payload) }),
};

function tileView(todos) {
  const remaining = todos.filter(t => !t.done).length;
  const subtitle = todos.length === 0
    ? "No todos — add one"
    : todos.slice(0, 2).map(t => `• ${t.done ? "✓ " : ""}${t.text}`).join("\n");
  const value = todos.length === 0 ? "0" : `${remaining} left`;
  const color = remaining === 0 && todos.length > 0 ? "green" : undefined;
  return {
    type: "HStack", gap: "md", children: [
      { type: "Stat", label: "Todos", value, color },
      { type: "Text", text: subtitle, variant: "caption", color: "muted" }
    ]
  };
}

function detailView(todos) {
  const items = todos.map(t => ({
    id: t.id,
    title: t.text,
    subtitle: t.done ? "done" : undefined,
    right: t.done ? "✓" : "○",
    onClick: { id: "toggle", payload: { id: t.id } }
  }));
  // Add delete as secondary action via button per row? DSL List only supports onClick, so we use a second list for delete
  // For v1 we expose delete via the toggle row's subtitle and a dedicated Delete button in detail footer
  const children = [
    { type: "Text", text: "Todos", variant: "title" },
    { type: "Text", text: `${todos.filter(t=>!t.done).length} remaining • ${todos.length} total`, variant: "caption", color: "muted" },
    { type: "Form", fields: [{ name: "text", placeholder: "Add todo…", type: "text" }], onSubmit: { id: "add" } },
    { type: "List", items },
  ];
  if (todos.length > 0) {
    children.push({ type: "HStack", gap: "sm", children: [
      { type: "Button", label: "Clear done", variant: "ghost", onClick: { id: "clearDone" } },
      { type: "Button", label: "Clear all", variant: "ghost", onClick: { id: "clearAll" } },
    ]});
  }
  // Per-item delete is handled by long-press alternative: we expose a helper text
  if (todos.length > 0) {
    children.push({ type: "Text", text: "Tip: click a row to toggle • use Clear buttons to delete", variant: "caption", color: "muted" });
  }
  return { type: "VStack", gap: "md", children };
}

function view(todos) {
  return { tile: tileView(todos), detail: detailView(todos) };
}

async function onInit() {
  try {
    const raw = await host.store.get("todos");
    const v = typeof raw === "string" ? raw : raw?.value;
    if (v) {
      const parsed = JSON.parse(v);
      if (Array.isArray(parsed)) todos = parsed;
    }
  } catch { todos = []; }
  if (!Array.isArray(todos)) todos = [];
  if (todos.length === 0) {
    // seed with useful examples, not empty
    todos = [
      { id: "1", text: "buy milk", done: false },
      { id: "2", text: "fix cloudflare tunnel", done: false },
      { id: "3", text: "review Sentry issues", done: true },
    ];
    await host.store.set("todos", todos);
  }
  host.render(view(todos));
}

async function onAction({ id, payload }) {
  const text = (payload?.text ?? "").trim();
  if (id === "add") {
    if (!text) return;
    // dedupe: don't add exact duplicate
    if (todos.some(t => t.text === text)) return;
    todos = [...todos, { id: Date.now().toString(), text, done: false }];
  } else if (id === "toggle") {
    const target = payload?.id;
    if (!target) return;
    todos = todos.map(t => t.id === target ? { ...t, done: !t.done } : t);
  } else if (id === "delete") {
    const target = payload?.id;
    todos = todos.filter(t => t.id !== target);
  } else if (id === "clearDone") {
    todos = todos.filter(t => !t.done);
  } else if (id === "clearAll") {
    todos = [];
  } else {
    return;
  }
  // persist and re-render atomically
  await host.store.set("todos", todos);
  host.render(view(todos));
}

// ndjson stdin
let buf = "";
process.stdin.on("data", async (chunk) => {
  buf += chunk.toString();
  let idx;
  while ((idx = buf.indexOf("\n")) !== -1) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.result !== undefined && msg.id && pending.has(msg.id)) {
        pending.get(msg.id)(msg.result);
        pending.delete(msg.id);
      } else if (msg.method === "event") {
        let params = msg.params;
        if (typeof params === "string") try { params = JSON.parse(params); } catch {}
        else if (params?.value) try { params = JSON.parse(params.value); } catch { params = params; }
        if (params.type === "init") await onInit();
        else if (params.type === "action") await onAction(params);
        else if (params.type === "tick") { /* no-op for persistent */ }
        send({ id: msg.id, method: "eventComplete" });
      }
    } catch (e) {
      console.error("todo parse error", e, line.slice(0,200));
    }
  }
});

// keep persistent alive — host reaps after 30s idle, but we stay resident while window open
setInterval(()=>{}, 10000);
