let buf=""; const pending=new Map(); let nid=1;
function send(m){process.stdout.write(JSON.stringify(m)+"\n");}
function call(m,p){const id=nid++;return new Promise(r=>{pending.set(id,r);send({id,method:m,params:p})});}
const host={store:{get:k=>call("host.store.get",{key:k}),set:(k,v)=>call("host.store.set",{key:k,value:JSON.stringify(v)})},shell:{exec:cmd=>call("host.shell.exec",{cmd})},render:p=>send({method:"render",params:JSON.stringify(p)})};
let history=[];
async function onInit(){
  try{ history=JSON.parse(await host.store.get("history")||"[]"); }catch{history=[];}
  if(!history.length) history=["copied text 1","hello world","https://example.com"];
  render();
}
function render(){
  host.render({
    tile:{type:"HStack",gap:"md",children:[{type:"Stat",label:"Clipboard",value:`${history.length}`},{type:"Text",text:history[0]?.slice(0,20)||"empty",variant:"caption",color:"muted"}]},
    detail:{type:"VStack",gap:"md",children:[{type:"Text",text:"Clipboard History",variant:"title"},{type:"List",items:history.slice(0,5).map((t,i)=>({id:String(i),title:t.slice(0,40),subtitle:`${t.length} chars`,right:"copy",onClick:{id:"copy",payload:{idx:String(i)}}}))},{type:"Button",label:"Clear",variant:"ghost",onClick:{id:"clear"}}]}
  });
}
async function onAction({id,payload}){
  if(id==="copy"){
    const idx=parseInt(payload.idx,10);
    const txt=history[idx];
    await host.shell.exec(`echo ${JSON.stringify(txt)} | pbcopy`);
  }
  if(id==="clear"){ history=[]; await host.store.set("history",history); render(); return; }
  // simulate new copy every tick via shell
  render();
}
let b="";process.stdin.on("data",async c=>{b+=c.toString();let i;while((i=b.indexOf("\n"))!==-1){const l=b.slice(0,i).trim();b=b.slice(i+1);if(!l)continue;try{const m=JSON.parse(l);if(m.result!==undefined&&pending.has(m.id)){pending.get(m.id)(m.result);pending.delete(m.id);}else if(m.method==="event"){let p=m.params;if(typeof p==="string")try{p=JSON.parse(p)}catch{}else if(p&&p.value)try{p=JSON.parse(p.value)}catch{};if(p.type==="init") await onInit(); else if(p.type==="action") await onAction(p); send({id:m.id,method:"eventComplete"});}}catch{}}});
setInterval(async()=>{
  // poll clipboard via pbpaste every 3s (persistent stays alive)
  try{
    const res=JSON.parse(await host.shell.exec("pbpaste"));
    const txt=(res.stdout||"").trim();
    if(txt && history[0]!==txt){ history.unshift(txt); history=history.slice(0,20); await host.store.set("history",history); render(); }
  }catch{}
},3000);
