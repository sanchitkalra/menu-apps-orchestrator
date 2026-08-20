type Todo = { id: string; text: string; done: boolean };

// Minimal host shim over ndjson stdin/stdout
const pending = new Map<number, (v:any)=>void>();
let nextId = 1;
let todos: Todo[] = [];

function send(msg: any) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

function hostCall(method: string, params: any): Promise<any> {
  const id = nextId++;
  return new Promise(resolve => {
    pending.set(id, resolve);
    send({ id, method, params });
  });
}

const host = {
  store: {
    get: (key: string) => hostCall("host.store.get", { key }),
    set: (key: string, value: any) => hostCall("host.store.set", { key, value: JSON.stringify(value) }),
  },
  render: (payload: any) => send({ method: "render", params: payload }),
};

function view(todos: Todo[]) {
  const remaining = todos.filter(t => !t.done).length;
  const subtitle = todos.slice(0, 2).map(t => `• ${t.text}`).join("\n") || "No todos";
  const tile = {
    type: "HStack", gap: "md",
    children: [
      { type: "Stat", label: "Todos", value: `${remaining} left` },
      { type: "Text", text: subtitle, variant: "caption", color: "muted" }
    ]
  };
  const detail = {
    type: "VStack", gap: "md",
    children: [
      { type: "Text", text: "Todos", variant: "title" },
      { type: "Form", fields: [{ name: "text", placeholder: "Add todo...", type: "text" }], onSubmit: { id: "add" } },
      {
        type: "List",
        items: todos.map(t => ({
          id: t.id, title: t.text, subtitle: t.done ? "done" : undefined,
          right: t.done ? "✓" : "○", onClick: { id: "toggle", payload: { id: t.id } }
        }))
      },
      ...(todos.length ? [{ type: "Button", label: "Clear done", variant: "ghost", onClick: { id: "clearDone" } }] : [])
    ]
  };
  return { tile, detail };
}

async function onInit() {
  const raw = await host.store.get("todos");
  try { todos = raw ? JSON.parse(raw) : [] } catch { todos = [] }
  if (todos.length === 0) {
    todos = [
      { id: "1", text: "buy milk", done: false },
      { id: "2", text: "fix cloudflare tunnel", done: false },
    ];
    await host.store.set("todos", todos);
  }
  host.render(view(todos));
}

async function onAction({ id, payload }: any) {
  if (id === "add") {
    const text = (payload?.text ?? "").trim();
    if (!text) return;
    todos = [...todos, { id: Date.now().toString(), text, done: false }];
  }
  if (id === "toggle") todos = todos.map(t => t.id === payload.id ? { ...t, done: !t.done } : t);
  if (id === "clearDone") todos = todos.filter(t => !t.done);
  await host.store.set("todos", todos);
  host.render(view(todos));
}

// ndjson stdin reader
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
        pending.get(msg.id)!(msg.result);
        pending.delete(msg.id);
      } else if (msg.method === "event") {
        const p = msg.params;
        // params may be stringified AnyCodable
        let params = p;
        if (typeof p === "string") try { params = JSON.parse(p); } catch {}
        else if (p?.value) try { params = JSON.parse(p.value); } catch { params = p }

        if (params.type === "init") await onInit();
        if (params.type === "tick") { /* no tick for todo */ }
        if (params.type === "action") await onAction(params);
        // signal completion for lane B
        send({ id: msg.id, method: "eventComplete" });
      }
    } catch (e) {
      console.error("parse error", e);
    }
  }
});

// keep alive for persistent
setInterval(()=>{}, 1000);
