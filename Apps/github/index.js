/**
 * GitHub monitor — ephemeral poller, interval 5m
 * Host APIs: host.fetch, host.store, host.notify, host.secrets
 * Tile: Stat with notification count + latest zen
 * Detail: List of notifications/issues + Refresh button
 * Host events: init, tick, action:refresh
 */

const pending = new Map();
let nid = 1;
function send(m){ process.stdout.write(JSON.stringify(m)+"\n"); }
function call(method, params){ const id=nid++; return new Promise(r=>{pending.set(id,r); send({id, method, params})}); }

const host = {
  store:  { get: k=>call("host.store.get",{key:k}), set:(k,v)=>call("host.store.set",{key:k,value:JSON.stringify(v)}) },
  secrets:{ get: k=>call("host.secrets.get",{key:k}) },
  fetch:  (url, opts={})=>call("host.fetch",{url, method:opts.method||"GET"}),
  notify: (t,b)=>call("host.notify",{title:t, body:b}),
  render: p=>send({method:"render", params:JSON.stringify(p)}),
};

let lastCount = 0;

function tileView(count, zen) {
  const value = count != null ? `${count}` : "zen";
  const label = count != null ? "GitHub" : "GitHub";
  const subtitle = zen ? zen.slice(0, 42) : "No token — showing zen";
  return {
    type: "HStack", gap: "md", children: [
      { type: "Stat", label, value, color: count>0 ? "red" : undefined },
      { type: "Text", text: subtitle, variant: "caption", color: "muted" }
    ]
  };
}

function detailView(count, zen, items) {
  const listItems = (items && items.length)
    ? items.slice(0,5).map((it,i)=>({
        id: String(i),
        title: it.title || it.subject?.title || "Notification",
        subtitle: it.repository?.full_name || it.reason || zen?.slice(0,32),
        right: it.unread ? "new" : undefined,
        onClick: { id: "open", payload: { idx: String(i) } }
      }))
    : [{ id:"zen", title: zen || "No data", subtitle: "GitHub zen — add token in secrets for notifications", right: undefined }];

  return {
    type: "VStack", gap: "md", children: [
      { type: "Text", text: count!=null ? `GitHub — ${count} notifications` : "GitHub — Zen", variant: "title" },
      { type: "Text", text: count!=null ? "Polls every 5m via host.fetch" : "Set github_token via host.secrets for real notifications", variant: "caption", color: "muted" },
      { type: "List", items: listItems },
      { type: "HStack", gap: "sm", children: [
        { type: "Button", label: "Refresh", variant: "primary", onClick: { id: "refresh" } },
        ...(count>0 ? [{ type: "Button", label: "Clear", variant: "ghost", onClick: { id: "clear" } }] : [])
      ]}
    ]
  };
}

async function fetchWithAuth(url, token) {
  // Host fetch does not yet forward headers; for v1 we fetch without auth and fallback to zen
  // If token exists we try to hit notifications endpoint unauthenticated will 401, so we detect and use zen
  const raw = await host.fetch(url);
  try { return JSON.parse(raw); } catch { return { body: raw, status:"200" }; }
}

async function onTick() {
  let count = null;
  let zen = "";
  let items = [];

  try {
    // 1. Try zen (always works, no auth, validates host.fetch)
    const zenRaw = await host.fetch("https://api.github.com/zen");
    try { const j = JSON.parse(zenRaw); zen = (j.body||j.value||zenRaw).trim(); } catch { zen = String(zenRaw).trim().slice(0,100); }

    // 2. Try notifications if token is present (opportunistic, won't fail tile if no token)
    const token = await host.secrets.get("github_token");
    const hasToken = token && String(token).trim().length > 10;

    if (hasToken) {
      // host.fetch doesn't yet support headers, so this will likely 401;
      // we attempt and if it returns array we use it, otherwise keep zen
      const notifRaw = await host.fetch("https://api.github.com/notifications");
      try {
        const parsed = JSON.parse(notifRaw);
        const body = parsed.body ? JSON.parse(parsed.body) : parsed;
        if (Array.isArray(body)) {
          items = body;
          count = body.length;
        } else if (Array.isArray(parsed)) {
          items = parsed;
          count = parsed.length;
        }
      } catch {}
    }

    // If we got count, persist and notify on increase
    if (count != null) {
      const prevRaw = await host.store.get("githubCount");
      const prev = prevRaw ? parseInt(String(prevRaw).replace(/"/g,""),10) : 0;
      if (!isNaN(count) && !isNaN(prev) && count > prev && prev !== 0) {
        await host.notify("GitHub", `${count - prev} new notifications`);
      }
      await host.store.set("githubCount", count);
      await host.store.set("githubItems", items.slice(0,5));
    } else {
      // no count, just zen
      await host.store.set("githubZen", zen);
    }

    // store zen always
    await host.store.set("lastZen", zen);

  } catch (e) {
    // render error but don't throw
    host.render({
      tile: { type: "Text", text: "GitHub error", color: "red" },
      detail: { type: "VStack", gap: "md", children: [
        { type: "Text", text: "GitHub fetch failed", variant: "title", color: "red" },
        { type: "Text", text: String(e).slice(0,200), variant: "caption", color: "muted" },
        { type: "Button", label: "Retry", variant: "primary", onClick: { id: "refresh" } }
      ]}
    });
    return;
  }

  // Normal render
  // If count is null we are in zen mode
  if (count == null) {
    // try to restore previous items for detail
    try {
      const cached = await host.store.get("githubItems");
      if (cached) items = JSON.parse(String(cached).replace(/^"|"$/g,"").replace(/\\"/g,'"'));
    } catch {}
  }

  host.render({ tile: tileView(count, zen), detail: detailView(count, zen, items) });
}

async function onAction({id}) {
  if (id === "refresh" || id === "open") {
    await onTick();
  } else if (id === "clear") {
    await host.store.set("githubCount", 0);
    await onTick();
  }
}

let buf="";
process.stdin.on("data", async c=>{
  buf+=c.toString();
  let idx;
  while((idx=buf.indexOf("\n"))!==-1){
    const line=buf.slice(0,idx).trim(); buf=buf.slice(idx+1);
    if(!line) continue;
    try{
      const m=JSON.parse(line);
      if(m.result!==undefined && pending.has(m.id)){ pending.get(m.id)(m.result); pending.delete(m.id); }
      else if(m.method==="event"){
        let p=m.params;
        if(typeof p==="string") try{p=JSON.parse(p)}catch{}
        else if(p&&p.value) try{p=JSON.parse(p.value)}catch{}
        if(p.type==="init" || p.type==="tick") await onTick();
        else if(p.type==="action") await onAction(p);
        send({id:m.id, method:"eventComplete"});
      }
    }catch(e){ console.error("github parse error", e); }
  }
});
