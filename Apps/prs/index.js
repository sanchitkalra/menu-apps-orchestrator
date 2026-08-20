// PR auto-merge keeper — port of swift-bar-plugins/pr.1m.sh.
const pending=new Map(); let nid=1;
function send(m){process.stdout.write(JSON.stringify(m)+"\n");}
function call(m,p){const id=nid++;return new Promise(r=>{pending.set(id,r);send({id,method:m,params:p})});}
const host={
  store:{get:k=>call("host.store.get",{key:k}),set:(k,v)=>call("host.store.set",{key:k,value:JSON.stringify(v)})},
  shell:{exec:cmd=>call("host.shell.exec",{cmd})},
  render:p=>send({method:"render",params:JSON.stringify(p)})
};
const shq=s=>"'"+String(s).replace(/'/g,"'\\''")+"'";  // shell single-quote

// Repo lives outside the repo tree: ~/Orchestrator/Data/prs/config.json (see config.example.json)
const fs=require("fs");
const CFG_PATH=`${process.env.ORCHESTRATOR_DATA_DIR||"."}/config.json`;
let cfg={}; let cfgError=null;
try{ cfg=JSON.parse(fs.readFileSync(CFG_PATH,"utf8")); }
catch{ cfgError=`missing config: ${CFG_PATH}`; }
const REPO=cfg.repo||"";
const PATH_PREFIX='export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; ';
// Same unattended behaviour as the plugin: approved PRs get squash auto-merge enabled and
// main merged in when behind. Set false to make this app read-only and drive it by button.
const AUTO_KEEP=true;

let prs=[];            // [{number,title,url,reviewDecision,mergeStateStatus,autoMergeRequest,isDraft}]
let notes={};          // number -> "merged main · auto-merge on"
let error=cfgError;
let lastRun=null;

async function sh(cmd){ return JSON.parse(await host.shell.exec(PATH_PREFIX+cmd)); }

async function load(){
  if(cfgError) throw new Error(cfgError);
  const r=await sh(`gh pr list --repo ${shq(REPO)} --author @me --state open`
    +` --json number,title,url,reviewDecision,mergeStateStatus,autoMergeRequest,isDraft`);
  if(Number(r.exitCode)!==0) throw new Error((r.stderr||"gh unavailable or not authenticated").trim().split("\n")[0]);
  const all=JSON.parse(r.stdout||"[]");
  return all.filter(p=>!p.isDraft);
}

// Approved + behind -> merge main in. Approved + no auto-merge -> enable squash auto-merge.
// Unapproved PRs are never touched, matching the plugin.
async function keepReady(pr){
  if(pr.reviewDecision!=="APPROVED") return "";
  if(pr.mergeStateStatus==="DIRTY") return "merge conflict — resolve manually";
  let note="";
  if(pr.mergeStateStatus==="BEHIND"){
    const r=await sh(`gh api --method PUT repos/${REPO}/pulls/${pr.number}/update-branch`);
    note=Number(r.exitCode)===0?"merged main":"update blocked";
  }
  if(pr.autoMergeRequest==null){
    const r=await sh(`gh pr merge ${pr.number} --repo ${shq(REPO)} --auto --squash`
      +` --subject ${shq(`${pr.title} (#${pr.number})`)} --body ''`);
    note=(note?note+" · ":"")+(Number(r.exitCode)===0?"auto-merge on":"auto-merge failed");
  } else {
    note=(note?note+" · ":"")+"auto-merge on";
  }
  return note;
}

const ago=t=>{if(!t) return "never";const s=Math.round((Date.now()-t)/1000);
  return s<60?`${s}s ago`:s<3600?`${Math.round(s/60)}m ago`:`${Math.round(s/3600)}h ago`;};

// glyph + colour per PR state, mirroring the plugin's SF Symbols
function mark(pr){
  if(pr.mergeStateStatus==="DIRTY") return {g:"⚠",c:"red",s:"conflict"};
  switch(pr.reviewDecision){
    case "APPROVED": return {g:"✓",c:"green",s:"approved"};
    case "CHANGES_REQUESTED": return {g:"✗",c:"red",s:"changes requested"};
    default: return {g:"○",c:"muted",s:"review pending"};
  }
}

function render(){
  const total=prs.length;
  const approved=prs.filter(p=>p.reviewDecision==="APPROVED").length;
  const conflicts=prs.filter(p=>p.mergeStateStatus==="DIRTY").length;
  const headline=conflicts>0?"red":approved>0?"green":"muted";

  const status=conflicts>0?`⚠ ${conflicts} conflict${conflicts>1?"s":""}`
                  :total===0?"no open PRs"
                  :prs.map(p=>mark(p).g).join(" ");

  const tile=error
    ? {type:"VStack",gap:"sm",children:[
        {type:"Stat",label:"PRs",value:"—",color:"red"},
        {type:"Text",text:String(error).slice(0,48),variant:"caption",color:"red"}]}
    : {type:"VStack",gap:"sm",children:[
        {type:"Stat",label:"PRs approved",value:`${approved}/${total}`,color:headline},
        {type:"Progress",value:total?approved/total:0},
        {type:"Text",text:status,variant:"caption",color:conflicts>0?"red":"muted"}]};

  const items=prs.map(p=>{
    const m=mark(p);
    const note=notes[p.number];
    return {id:String(p.number),
            title:`${m.g} #${p.number} ${p.title}`,
            subtitle:note?`${m.s} — ${note}`:m.s,
            right:p.autoMergeRequest?"auto":"",
            onClick:{id:"open",payload:{url:p.url}}};
  });

  const detail={type:"VStack",gap:"md",children:[
    {type:"Text",text:`Open PRs${REPO?" — "+REPO.split("/").pop():""}`,variant:"title"},
    {type:"Text",text:`${approved} approved · ${total} open${conflicts?` · ${conflicts} conflicted`:""} · checked ${ago(lastRun)}`,
     variant:"caption",color:conflicts?"red":"muted"},
    ...(error?[{type:"Text",text:`⚠ ${error}`,variant:"body",color:"red"},
               {type:"Text",text:"Run: gh auth login",variant:"caption",color:"muted"}]:[]),
    ...(total?[{type:"Progress",value:approved/total},{type:"List",items}]
             :error?[]:[{type:"Text",text:"Nothing open. ",variant:"body",color:"muted"}]),
    {type:"HStack",gap:"sm",children:[
      {type:"Button",label:"Refresh",variant:"primary",onClick:{id:"refresh"}},
      ...(AUTO_KEEP?[]:[{type:"Button",label:"Keep approved ready",variant:"ghost",onClick:{id:"keep"}}])]}
  ]};
  host.render({tile,detail});
}

async function poll(keep){
  try{
    prs=await load(); error=null; lastRun=Date.now();
    render();                              // show the list before the slower keep-ready calls
    if(keep){
      for(const p of prs){ const n=await keepReady(p); if(n) notes[p.number]=n; }
      prs=await load();                    // states change once auto-merge is on
    }
  }catch(e){ error=e.message||String(e); }
  render();
}

async function onAction({id,payload}){
  if(id==="refresh") return poll(AUTO_KEEP);
  if(id==="keep") return poll(true);
  if(id==="open"&&payload&&payload.url) await sh(`open ${shq(payload.url)}`);
}

let b="";process.stdin.on("data",async c=>{b+=c.toString();let i;while((i=b.indexOf("\n"))!==-1){const l=b.slice(0,i).trim();b=b.slice(i+1);if(!l)continue;try{const m=JSON.parse(l);if(m.result!==undefined&&pending.has(m.id)){pending.get(m.id)(m.result);pending.delete(m.id);}else if(m.method==="event"){let p=m.params;if(typeof p==="string")try{p=JSON.parse(p)}catch{}else if(p&&p.value)try{p=JSON.parse(p.value)}catch{};if(p.type==="init"||p.type==="tick") await poll(AUTO_KEEP); else if(p.type==="action") await onAction(p); send({id:m.id,method:"eventComplete"});}}catch{}}});
