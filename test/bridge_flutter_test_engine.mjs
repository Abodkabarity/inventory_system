const port=process.argv[2];
const targets=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target=targets.find(t=>t.type==='page' && t.url.includes('/static/index.html'));
if(!target) throw Error('Isolated Flutter test page not found');
const socket=new WebSocket(target.webSocketDebuggerUrl);
let sequence=0;
const send=(method,params={})=>socket.send(JSON.stringify({id:++sequence,method,params}));
socket.onopen=()=>send('Fetch.enable',{patterns:[{urlPattern:'*/canvaskit/*',requestStage:'Request'}]});
socket.onmessage=async event=>{
 const m=JSON.parse(event.data);
 if(m.id===1){
  console.log('Serving pinned CanvasKit to the isolated Flutter test browser');
  send('Runtime.evaluate',{expression:'document.querySelector("iframe").contentWindow.location.reload()'});
 }
 if(m.method==='Fetch.requestPaused'){
  const {requestId,request}=m.params;
  const original=new URL(request.url);
  if(!original.pathname.startsWith('/canvaskit/')){send('Fetch.continueRequest',{requestId});return;}
  const response=await fetch('http://127.0.0.1:8767'+original.pathname);
  const bytes=Buffer.from(await response.arrayBuffer());
  send('Fetch.fulfillRequest',{requestId,responseCode:response.status,responseHeaders:[{name:'Content-Type',value:original.pathname.endsWith('.wasm')?'application/wasm':'text/javascript'},{name:'Access-Control-Allow-Origin',value:'*'}],body:bytes.toString('base64')});
  console.log('Local test engine asset:',original.pathname);
 }
};
socket.onclose=()=>process.exit();
setTimeout(()=>{socket.close();},240000);
