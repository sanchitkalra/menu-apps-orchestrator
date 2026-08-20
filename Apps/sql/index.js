let buf=""; const pending=new Map(); let nid=1;
function send(m){process.stdout.write(JSON.stringify(m)+"\n");}
function call(m,p){const id=nid++;return new Promise(r=>{pending.set(id,r);send({id,method:m,params:p})});}
const host={store:{get:k=>call("host.store.get",{key:k}),set:(k,v)=>call("host.store.set",{key:k,value:JSON.stringify(v)})},secrets:{get:k=>call("host.secrets.get",{key:k})},fetch:(url)=>call("host.fetch",{url}),render:p=>send({method:"render",params:JSON.stringify(p)})};
async function onTick(){
  // mock SQL: fetch placeholder and random metric
  const val = 200 + Math.floor(Math.random()*300);
  const history = JSON.parse(await host.store.get("history")||"[]");
  history.push(val); if(history.length>20) history.shift();
  await host.store.set("history",history);
  const spark = history;
  host.render({
    tile:{type:"VStack",gap:"sm",children:[{type:"Stat",label:"Checkout p95",value:`${val}ms`,color:val>400?"red":"green"},{type:"Sparkline",data:spark}]},
    detail:{type:"VStack",gap:"md",children:[{type:"Text",text:"Checkout p95 — 15m",variant:"title"},{type:"Sparkline",data:spark},{type:"Text",text:`Current: ${val}ms`,variant:"body"}]}
  });
}
let b="";process.stdin.on("data",async c=>{b+=c.toString();let i;while((i=b.indexOf("\n"))!==-1){const l=b.slice(0,i).trim();b=b.slice(i+1);if(!l)continue;try{const m=JSON.parse(l);if(m.result!==undefined&&pending.has(m.id)){pending.get(m.id)(m.result);pending.delete(m.id);}else if(m.method==="event"){let p=m.params;if(typeof p==="string")try{p=JSON.parse(p)}catch{}else if(p&&p.value)try{p=JSON.parse(p.value)}catch{};if(p.type==="init"||p.type==="tick") await onTick(); send({id:m.id,method:"eventComplete"});}}catch{}}});
