let buf=""; const pending=new Map(); let nid=1;
function send(m){process.stdout.write(JSON.stringify(m)+"\n");}
function call(m,p){const id=nid++;return new Promise(r=>{pending.set(id,r);send({id,method:m,params:p})});}
const host={store:{get:k=>call("host.store.get",{key:k}),set:(k,v)=>call("host.store.set",{key:k,value:JSON.stringify(v)})},fetch:(url)=>call("host.fetch",{url}),notify:(t,b)=>call("host.notify",{title:t,body:b}),render:p=>send({method:"render",params:JSON.stringify(p)})};
// Mock Sentry: fetch from statuspage or random
async function onTick(){
  const issues = [
    {id:"a", title:"TypeError in /api/checkout", subtitle:"12 events • 4 users", right:"P1"},
    {id:"b", title:"Timeout in /api/search", subtitle:"7 events • 2 users", right:"P2"}
  ];
  const count = issues.length;
  const prev = await host.store.get("sentryCount");
  if(prev!==String(count) && count>0) await host.notify("Sentry", `${count} issues`);
  await host.store.set("sentryCount", count);
  host.render({
    tile:{type:"HStack",gap:"md",children:[{type:"Stat",label:"Sentry",value:`${count} new`,color:count?"red":undefined},{type:"Text",text:issues[0].title, variant:"caption"}]},
    detail:{type:"VStack",gap:"md",children:[{type:"Text",text:"Sentry — Last 24h",variant:"title"},{type:"List",items:issues}]}
  });
}
let b="";process.stdin.on("data",async c=>{b+=c.toString();let i;while((i=b.indexOf("\n"))!==-1){const l=b.slice(0,i).trim();b=b.slice(i+1);if(!l)continue;try{const m=JSON.parse(l);if(m.result!==undefined&&pending.has(m.id)){pending.get(m.id)(m.result);pending.delete(m.id);}else if(m.method==="event"){let p=m.params;if(typeof p==="string")try{p=JSON.parse(p)}catch{}else if(p&&p.value)try{p=JSON.parse(p.value)}catch{};if(p.type==="init"||p.type==="tick") await onTick(); send({id:m.id,method:"eventComplete"});}}catch{}}});
