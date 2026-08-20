// Card count monitor — port of swift-bar-plugins/cub.1m.sh, with a 100-poll trend graph.
const pending=new Map(); let nid=1;
function send(m){process.stdout.write(JSON.stringify(m)+"\n");}
function call(m,p){const id=nid++;return new Promise(r=>{pending.set(id,r);send({id,method:m,params:p})});}
const host={
  store:{get:k=>call("host.store.get",{key:k}),set:(k,v)=>call("host.store.set",{key:k,value:JSON.stringify(v)})},
  shell:{exec:cmd=>call("host.shell.exec",{cmd})},
  render:p=>send({method:"render",params:JSON.stringify(p)})
};
const shq=s=>"'"+String(s).replace(/'/g,"'\\''")+"'";  // shell single-quote

// Connection details live outside the repo: ~/Orchestrator/Data/cards/config.json
// (see config.example.json). Password still comes from ~/.pgpass, same as the plugin.
const fs=require("fs");
const CFG_PATH=`${process.env.ORCHESTRATOR_DATA_DIR||"."}/config.json`;
let cfg={}; let cfgError=null;
try{ cfg=JSON.parse(fs.readFileSync(CFG_PATH,"utf8")); }
catch{ cfgError=`missing config: ${CFG_PATH}`; }
const DB={host:cfg.host||"",port:cfg.port||"5432",name:cfg.database||"",user:cfg.user||""};
const PSQL=cfg.psql||"/opt/homebrew/bin/psql";
const QUERY=cfg.query||"";
const LABEL=cfg.label||"Cards";
const KEEP=100;        // polls kept for the graph
const FRESH_MS=3000;   // a poll this recent is reused instead of re-querying prod

let history=[];   // [{t: epoch_ms, n: count}]
let error=cfgError;
let busy=false;   // query in flight -> tile shows a spinner caption

async function query(){
  if(cfgError) throw new Error(cfgError);
  const cmd=`${PSQL} --host=${shq(DB.host)} --port=${DB.port} --dbname=${shq(DB.name)} --username=${shq(DB.user)}`
    +` --no-password --tuples-only --no-align --command=${shq(QUERY)}`;
  const res=JSON.parse(await host.shell.exec(cmd));
  const out=(res.stdout||"").trim();
  if(Number(res.exitCode)!==0||!/^\d+$/.test(out)) throw new Error(((res.stderr||out||"psql failed").trim().split("\n")[0])||"psql failed");
  return parseInt(out,10);
}

const fmt=n=>n.toLocaleString("en-IN");
const ago=t=>{const s=Math.round((Date.now()-t)/1000);
  return s<60?`${s}s ago`:s<3600?`${Math.round(s/60)}m ago`:`${Math.round(s/3600)}h ago`;};

function render(){
  const last=history[history.length-1];
  const counts=history.map(h=>h.n);
  // caption only carries state: refreshing / stale. No trend text.
  const caption=busy?"refreshing…":error?"stale":null;

  const tile=!last
    ? {type:"VStack",gap:"sm",children:[
        {type:"Stat",label:LABEL,value:busy?"…":"—",color:busy?"muted":"red"},
        {type:"Text",text:busy?"querying prod…":error?String(error).slice(0,48):"no data yet",
         variant:"caption",color:busy?"muted":"red"}]}
    : {type:"VStack",gap:"sm",children:[
        {type:"HStack",gap:"md",children:[
          {type:"Stat",label:LABEL,value:fmt(last.n),color:error?"red":"green"},
          ...(caption?[{type:"Text",text:caption,variant:"caption",color:busy?"muted":"red"}]:[])]},
        {type:"Sparkline",data:counts}]};

  const detail={type:"VStack",gap:"md",children:[
    {type:"Text",text:cfg.title||"Active Cards",variant:"title"},
    {type:"Text",text:cfg.subtitle||DB.name||"not configured",variant:"caption",color:"muted"},
    ...(busy?[{type:"Text",text:"⟳ querying prod…",variant:"caption",color:"muted"}]:[]),
    ...(error?[{type:"Text",text:`⚠ ${error}`,variant:"body",color:"red"}]:[]),
    ...(last?[
      {type:"Stat",label:`as of ${ago(last.t)}`,value:fmt(last.n),color:error?"red":"green"},
      {type:"Sparkline",data:counts}
    ]:[]),
    {type:"HStack",gap:"sm",children:[{type:"Button",label:"Refresh",variant:"primary",onClick:{id:"refresh"}}]}
  ]};
  host.render({tile,detail});
}

async function poll(){
  const last=history[history.length-1];
  // Cold start already polls; a click landing right after would hit prod twice for the same number.
  if(last && Date.now()-last.t < FRESH_MS){ render(); return; }
  busy=true; render();                     // paint the spinner before the slow round trip
  try{
    const n=await query(); error=null;
    history.push({t:Date.now(),n}); history=history.slice(-KEEP);
    await host.store.set("history",history);
  }catch(e){ error=e.message||String(e); }
  busy=false; render();
}

async function onInit(){
  try{ history=JSON.parse(await host.store.get("history")||"[]"); }catch{ history=[]; }
  render();          // paint cached history instantly, then go to the db
  await poll();
}
async function onAction({id}){ if(id==="refresh") await poll(); }

let b="";process.stdin.on("data",async c=>{b+=c.toString();let i;while((i=b.indexOf("\n"))!==-1){const l=b.slice(0,i).trim();b=b.slice(i+1);if(!l)continue;try{const m=JSON.parse(l);if(m.result!==undefined&&pending.has(m.id)){pending.get(m.id)(m.result);pending.delete(m.id);}else if(m.method==="event"){let p=m.params;if(typeof p==="string")try{p=JSON.parse(p)}catch{}else if(p&&p.value)try{p=JSON.parse(p.value)}catch{};if(p.type==="init") await onInit(); else if(p.type==="tick") await poll(); else if(p.type==="action") await onAction(p); send({id:m.id,method:"eventComplete"});}}catch{}}});
