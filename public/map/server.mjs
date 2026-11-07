import { createReadStream, existsSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';

const port = Number(process.env.PORT || 4176);
const webhookToken = process.env.BARRIO_WEBHOOK_TOKEN || 'barrio-dev-token';
const root = new URL('.', import.meta.url).pathname;
const products = new Map();
const clients = new Set();
const mime = { '.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.geojson':'application/geo+json','.svg':'image/svg+xml','.jpg':'image/jpeg','.png':'image/png' };
const send = (res,status,body,headers={}) => { res.writeHead(status,{'content-type':'application/json; charset=utf-8',...headers});res.end(JSON.stringify(body)); };
const broadcast = (event) => { const message=`event: product.sync\ndata: ${JSON.stringify(event)}\n\n`; for(const client of clients) client.write(message); };
const readBody = (req) => new Promise((resolve,reject) => { let raw='';req.on('data',(c)=>{raw+=c;if(raw.length>1_000_000)reject(new Error('Payload demasiado grande'));});req.on('end',()=>{try{resolve(JSON.parse(raw||'{}'))}catch{reject(new Error('JSON inválido'))}});req.on('error',reject); });

createServer(async (req,res) => {
  const url = new URL(req.url,`http://${req.headers.host}`);
  if (url.pathname === '/api/health') return send(res,200,{ok:true,service:'barrio-product-sync'});
  if (url.pathname === '/api/events') { res.writeHead(200,{'content-type':'text/event-stream','cache-control':'no-cache','connection':'keep-alive','access-control-allow-origin':'*'});res.write('retry: 3000\n\n');clients.add(res);req.on('close',()=>clients.delete(res));return; }
  const match = url.pathname.match(/^\/api\/merchant\/([a-z0-9-]+)\/products$/i);
  if (match && req.method === 'GET') { const record=products.get(match[1]); return send(res,200,record||{merchantId:match[1],products:[],updatedAt:null,source:null}); }
  if (match && req.method === 'POST') {
    if (req.headers.authorization !== `Bearer ${webhookToken}`) return send(res,401,{error:'unauthorized'});
    try { const body=await readBody(req); if(!Array.isArray(body.products)||body.products.length===0) return send(res,422,{error:'products must be a non-empty array'}); const clean=body.products.map((p)=>({name:String(p.name||'').trim(),priceMXN:Number(p.priceMXN),unit:String(p.unit||'pieza'),stock:Number(p.stock),available:p.available!==false})).filter((p)=>p.name&&Number.isFinite(p.priceMXN)&&Number.isFinite(p.stock)); if(!clean.length)return send(res,422,{error:'no valid products'}); const event={merchantId:match[1],products:clean,updatedAt:new Date().toISOString(),source:String(body.source||'whatsapp')};products.set(match[1],event);broadcast(event);return send(res,202,event); } catch(error) { return send(res,400,{error:error.message}); }
  }
  const path = normalize(join(root,url.pathname === '/' ? 'index.html' : url.pathname));
  if (!path.startsWith(root)||!existsSync(path)) { res.writeHead(404);res.end('Not found');return; }
  res.writeHead(200,{'content-type':mime[extname(path)]||'application/octet-stream'});createReadStream(path).pipe(res);
}).listen(port,()=>console.log(`BARRIO API + app running on http://127.0.0.1:${port}`));
