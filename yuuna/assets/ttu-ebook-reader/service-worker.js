const h=location.pathname.split("/").slice(0,-1).join("/"),U=[h+"/",h+"/auth",h+"/b",h+"/manage",h+"/settings",h+"/statistics"],g="1791396015887";/**
 * @license BSD-3-Clause
 * Copyright (c) 2026, ッツ Reader Authors
 * All rights reserved.
 */const W="";/**
 * @license BSD-3-Clause
 * Copyright (c) 2026, ッツ Reader Authors
 * All rights reserved.
 */function q(e){return Object.entries(e).map(([t,n])=>`${encodeURIComponent(t)}=${encodeURIComponent(n)}`).join("&")}/**
 * @license BSD-3-Clause
 * Copyright (c) 2026, ッツ Reader Authors
 * All rights reserved.
 */const b="ttu-userfonts",c=self,d=`build:${g}`,$=new Set(U),R=[],y=new Set(R);c.addEventListener("install",e=>{c.skipWaiting(),e.waitUntil(caches.open(d).then(t=>t.addAll(R)))});c.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(t=>{const n=t.filter(s=>s!==d&&s!==b);return Promise.all(n.map(s=>caches.delete(s)))}))});c.addEventListener("fetch",e=>{if(e.request.method!=="GET"||e.request.headers.has("range"))return;const t=new URL(e.request.url),n=t.protocol.startsWith("http"),s=t.hostname===c.location.hostname&&t.port!==c.location.port,o=t.host===c.location.host,u=o&&y.has(t.pathname),a=e.request.cache==="only-if-cached"&&!u;if(!(!n||s||a)){if(o&&$.has(t.pathname)){const r=new Request(t.pathname);e.respondWith(w(e.request,!1,d,r));return}if(o&&t.pathname.startsWith("/userfonts/")){e.respondWith(caches.match(t.pathname).then(r=>r??C("/fonts/noto-serif-v21-regular.woff2")));return}if(o){const r=u?caches.match(t.pathname).then(l=>l??fetch(e.request)):A(e.request);if(r){e.respondWith(r);return}}t.host==="fonts.googleapis.com"&&e.respondWith(w(e.request))}});async function w(e,t=!0,n,s){const o=await caches.open(`other:${g}`),u=new AbortController;let a,r=!1,l=!1;const p=()=>n?caches.match(s??e,{cacheName:n}):void 0,f=async()=>{if(!t)return p();const i=await o.match(e);if(i)return i;if(n)return p()};try{const i=setTimeout(async()=>{a=await f(),l=!0,!(!a||r)&&u.abort()},1e3),m=await fetch(e,{signal:u.signal});return r=!0,clearTimeout(i),t&&o.put(e,m.clone()),m}catch(i){if(l||(a=await f()),a)return a;throw i}}function A(e){const t=new URL(e.url),s=/\/b\/(?<id>\d+)\/?(\?|$)/.exec(t.pathname);if(s!=null&&s.groups)return C(`${[[W]]}/b?${q(s.groups)}`)}function C(e){return new Response(null,{status:302,headers:{location:e}})}
