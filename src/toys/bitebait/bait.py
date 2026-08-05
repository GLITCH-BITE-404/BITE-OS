#!/usr/bin/env python3
# bitebait — forge a harmless "you've been hacked" prank link and send it.
#
# The whole thing is a page that opens in your friend's browser. A browser tab
# is a sandbox: it can go fullscreen, make noise and put on a very convincing
# show, but it cannot touch their files, install anything, or keep running once
# the tab is closed. So every scene here is loud theatre with nothing behind it.
#
# The reason it lands is that the scary lines are TRUE. Any web page you open
# already gets to see your public IP (→ city, via a real geo API), your device,
# your battery, your local time. bitebait just says those back to you like it
# broke in. Then it drops the act — GOTCHA — and reassures them nothing happened.
#
# Not phishing: it never asks for a password, never collects anything, never
# sends a thing back to you. ESC ends any scene instantly. It is a jump-scare
# with a punchline, not a trap.

import os, sys, re, json, time, random, socket, subprocess, shutil, http.server, threading
from pathlib import Path

# ─── house colours ───────────────────────────────────────────────────────────
def _c(n): return f'\033[{n}m'
RED, GRN, YLW, CYN, MAG, BLU = _c(31), _c(32), _c(33), _c(36), _c(35), _c(34)
BLD, DIM, RST = _c(1), _c(2), _c(0)
def say(*a): print(*a)
def ok(m):   print(f'{GRN}✓{RST} {m}')
def warn(m): print(f'{YLW}!{RST} {m}')
def err(m):  print(f'{RED}✗{RST} {m}', file=sys.stderr)
def die(m):  err(m); sys.exit(1)

# ─── settings (handed down from the hub as TOY_* env vars) ────────────────────
def env(k, d=''): return os.environ.get('TOY_' + k, d)
BRAND    = env('BRAND', 'BITE-OS')
TAGLINE  = env('TAGLINE', '// THE SYSTEM BIT YOU')
DEF_HOST = env('HOST', 'file')            # file | local | tunnel | github
GH_REPO  = env('GH_REPO', '')             # e.g. GLITCH-BITE-404/baits
OUTDIR   = os.path.expanduser(env('OUTDIR', '~/bite-baits'))
PACE     = env('PACE', 'normal')          # fast | normal | slow
SOUND    = env('SOUND', 'on') != 'off'
CURSOR   = env('HIDECURSOR', 'on') != 'off'
COPYLINK = env('COPYLINK', 'on') != 'off'
QR       = env('QR', 'on') != 'off'
PORT     = int(env('PORT', '8080') or '8080')
DEF_NAME = env('TARGET', '')

CACHE = Path(os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache'))) / 'bite-os'
LOG   = CACHE / 'bitebait.log'

# ══════════════════════════════════════════════════════════════════════════════
#  the page
# ══════════════════════════════════════════════════════════════════════════════

# Shared JavaScript: gather the real intel, small helpers, and the reveal card.
SHARED_JS = r"""
const $=(s,r=document)=>r.querySelector(s), $$=(s,r=document)=>[...r.querySelectorAll(s)];
const PACE_MULT={fast:0.5,normal:1,slow:1.7}[PACE]||1;
const sleep=ms=>new Promise(r=>setTimeout(r,ms*PACE_MULT));
const rnd=(a,b)=>a+Math.random()*(b-a), pick=a=>a[Math.floor(Math.random()*a.length)];
const esc=s=>(s==null?'':(''+s)).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const stage=()=>document.getElementById('stage');

// ── sound: synthesised, so nothing has to be bundled ──
let AC;
function ac(){ if(SOUND&&!AC){try{AC=new (window.AudioContext||window.webkitAudioContext)();}catch(e){}} return AC; }
function tone(f,d=0.12,type='square',g=0.05){ const c=ac(); if(!c)return;
  const o=c.createOscillator(),v=c.createGain(); o.type=type;o.frequency.value=f;v.gain.value=g;
  o.connect(v);v.connect(c.destination);o.start();
  v.gain.setTargetAtTime(0,c.currentTime+d*0.4,d*0.3);o.stop(c.currentTime+d+0.05); }
function noise(d=0.3,g=0.18){ const c=ac(); if(!c)return;
  const b=c.createBuffer(1,Math.max(1,c.sampleRate*d),c.sampleRate),ch=b.getChannelData(0);
  for(let i=0;i<ch.length;i++)ch[i]=(Math.random()*2-1)*(1-i/ch.length);
  const s=c.createBufferSource(),v=c.createGain(); v.gain.value=g; s.buffer=b;s.connect(v);v.connect(c.destination);s.start(); }
function beeps(n,f=440,step=90){ for(let i=0;i<n;i++)setTimeout(()=>tone(f+i*35,0.07),i*step); }

// ── the real data any website already sees ──
const INTEL=(async()=>{
  const d={ip:'—',city:'',region:'',country:'',cc:'',isp:'',lat:null,lon:null,online:true};
  const geo=async(u,map)=>{ const r=await fetch(u); const j=await r.json(); map(j); };
  try{
    await geo('https://ipwho.is/',j=>{ if(j.success===false)throw 0;
      Object.assign(d,{ip:j.ip,city:j.city,region:j.region,country:j.country,cc:j.country_code,
        isp:(j.connection&&(j.connection.isp||j.connection.org))||'',lat:j.latitude,lon:j.longitude}); });
  }catch(e){
    try{ await geo('https://ipapi.co/json/',j=>{
      Object.assign(d,{ip:j.ip,city:j.city,region:j.region,country:j.country_name,cc:j.country,
        isp:j.org||'',lat:j.latitude,lon:j.longitude}); }); }
    catch(e2){ d.online=false; }
  }
  const ua=navigator.userAgent;
  d.os=/Windows/.test(ua)?'Windows':/Android/.test(ua)?'Android':/iPhone|iPad|iOS/.test(ua)?'iOS':
       /Mac/.test(ua)?'macOS':/CrOS/.test(ua)?'ChromeOS':/Linux/.test(ua)?'Linux':'an unknown OS';
  d.browser=/Edg/.test(ua)?'Edge':/OPR|Opera/.test(ua)?'Opera':/Firefox/.test(ua)?'Firefox':
            /Chrome/.test(ua)?'Chrome':/Safari/.test(ua)?'Safari':'their browser';
  d.mobile=/Mobi|Android|iPhone/.test(ua);
  d.screen=screen.width+'×'+screen.height;
  d.lang=(navigator.language||'').toLowerCase();
  d.cores=navigator.hardwareConcurrency||null;
  d.mem=navigator.deviceMemory||null;
  d.tz=(Intl.DateTimeFormat().resolvedOptions().timeZone)||'';
  try{ const b=await (navigator.getBattery&&navigator.getBattery()); if(b){ d.batt=Math.round(b.level*100); d.charging=b.charging; } }catch(e){}
  const con=navigator.connection; if(con){ d.net=con.effectiveType; d.down=con.downlink; }
  d.now=new Date();
  return d;
})();

// ── terminal-style helpers most scenes reuse ──
async function say_(txt,{cls='',speed=16,pre=''}={}){
  const t=stage(); const d=document.createElement('div'); d.className='ln '+cls; t.appendChild(d); d.textContent=pre;
  for(const ch of txt){ d.textContent+=ch; if(speed) await sleep(speed*rnd(0.4,1.6)); }
  t.scrollTop=t.scrollHeight; return d;
}
function put(txt,cls=''){ const t=stage(); const d=document.createElement('div'); d.className='ln '+cls; d.innerHTML=txt; t.appendChild(d); t.scrollTop=t.scrollHeight; return d; }
async function bar(label,ms,{cls='',w=26}={}){
  const d=put('',cls);
  for(let i=0;i<=w;i++){ d.textContent=label+' ['+'▓'.repeat(i)+'░'.repeat(w-i)+'] '+Math.round(i/w*100)+'%';
    stage().scrollTop=stage().scrollHeight; await sleep(ms/w); }
  return d;
}
function shake(ms=500){ document.body.classList.add('shake'); setTimeout(()=>document.body.classList.remove('shake'),ms); }

// ── the punchline ──
let DONE=false;
async function reveal(){
  if(DONE)return; DONE=true;
  try{ if(document.fullscreenElement) await document.exitFullscreen(); }catch(e){}
  const el=document.createElement('div'); el.className='reveal';
  el.innerHTML=`<div class="card">
    <div class="glitch big" data-t="GOTCHA">GOTCHA</div>
    <p class="msg">${esc(GOTCHA)}</p>
    <p class="calm">none of that was real. nothing was installed, nothing was sent anywhere,
    nobody got your anything. it was a web page telling you what every web page already sees.
    close the tab and it never happened.</p>
    <div class="brand">${esc(BRAND)} bitebait &nbsp;·&nbsp; <span class="tag">${esc(TAGLINE)}</span></div>
    <button id="bail">😂 alright, you got me</button>
  </div>`;
  document.body.className='revealed'; document.body.appendChild(el);
  beeps(4,300,120);
  $('#bail').onclick=()=>{ try{window.close();}catch(e){} location.replace('about:blank'); };
}
"""

BOOT_JS = r"""
document.addEventListener('keydown',e=>{ if(e.key==='Escape') reveal(); });
window.addEventListener('load',()=>{
  document.documentElement.classList.add('pace-'+PACE);
  (async()=>{ try{ await runScene(); }catch(e){ console.error(e); reveal(); } })();
});
"""

SHELL_CSS = r"""
*{box-sizing:border-box;margin:0;padding:0}
:root{--g:#39ff14;--r:#ff2d2d;--m:#ff00d4;--c:#00e5ff;--bg:#05060a}
html,body{height:100%}
body{background:var(--bg);color:var(--g);font:15px/1.5 'JetBrains Mono','DejaVu Sans Mono',ui-monospace,monospace;
  overflow:hidden;cursor:CURSORVAL;-webkit-font-smoothing:none}
body::after{content:"";position:fixed;inset:0;pointer-events:none;z-index:9999;
  background:repeating-linear-gradient(0deg,rgba(0,0,0,.18) 0,rgba(0,0,0,.18) 1px,transparent 1px,transparent 3px);
  mix-blend-mode:multiply;opacity:.55}
body.shake{animation:sh .35s infinite}
@keyframes sh{0%{transform:translate(0,0)}25%{transform:translate(-3px,2px)}50%{transform:translate(2px,-2px)}75%{transform:translate(-2px,-1px)}100%{transform:translate(1px,2px)}}
#stage{position:absolute;inset:0;padding:5vh 6vw;overflow:hidden;white-space:pre-wrap;word-break:break-word}
.ln{white-space:pre-wrap}
.g{color:var(--g)}.r{color:var(--r)}.y{color:#ffd400}.m{color:var(--m)}.c{color:var(--c)}.dim{opacity:.5}
.big1{font-size:clamp(28px,7vw,84px);font-weight:700;letter-spacing:2px}
.esc-hint{position:fixed;left:10px;bottom:8px;z-index:10000;color:#666;font-size:11px;opacity:.6}
/* glitch title used by the reveal + some scenes */
.glitch{position:relative;color:#fff}
.glitch::before,.glitch::after{content:attr(data-t);position:absolute;inset:0}
.glitch::before{color:var(--m);animation:gl 2.2s infinite;clip-path:inset(0 0 55% 0)}
.glitch::after{color:var(--c);animation:gl 1.6s infinite reverse;clip-path:inset(55% 0 0 0)}
@keyframes gl{0%,100%{transform:translate(0,0)}20%{transform:translate(-3px,1px)}40%{transform:translate(3px,-1px)}60%{transform:translate(-2px,-1px)}80%{transform:translate(2px,1px)}}
/* reveal */
.reveal{position:fixed;inset:0;display:grid;place-items:center;background:radial-gradient(circle at 50% 40%,#0b0d16,#000);z-index:10001;cursor:auto}
.reveal .card{max-width:640px;padding:6vw;text-align:center}
.reveal .big{font-size:clamp(46px,13vw,150px);font-weight:800;letter-spacing:4px;line-height:1}
.reveal .msg{color:var(--g);font-size:clamp(17px,3.4vw,26px);margin:26px 0 18px;font-weight:700}
.reveal .calm{color:#8b93a7;font-size:14px;line-height:1.7;margin-bottom:26px}
.reveal .brand{color:#5a6072;font-size:12px;letter-spacing:1px;margin-bottom:22px}
.reveal .brand .tag{color:var(--m)}
.reveal button{background:transparent;border:1px solid var(--g);color:var(--g);font-family:inherit;
  font-size:15px;padding:12px 26px;border-radius:3px;cursor:pointer;transition:.15s}
.reveal button:hover{background:var(--g);color:#000}
body.revealed #stage{filter:blur(3px) brightness(.4)}
"""

def _js_str(s):  # embed a python string as a JS string literal
    return json.dumps(s)

def build_page(scene, target, gotcha):
    sc = SCENES[scene]
    parts = sc['build'](target)
    css   = SHELL_CSS.replace('CURSORVAL', 'none' if CURSOR else 'auto') + '\n' + parts.get('css', '')
    consts = (
        f"const PACE={_js_str(PACE)}, SOUND={'true' if SOUND else 'false'};\n"
        f"const BRAND={_js_str(BRAND)}, TAGLINE={_js_str(TAGLINE)}, GOTCHA={_js_str(gotcha)};\n"
        f"const TARGET={_js_str(target)};\n"
    )
    html = f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<meta name="referrer" content="no-referrer">
<title>{sc.get('pagetitle','loading…')}</title>
<style>{css}</style>
</head><body>
<div id="stage"></div>
<div class="esc-hint">press esc to stop</div>
{parts.get('html','')}
<script>
{consts}
{SHARED_JS}
{parts['js']}
{BOOT_JS}
</script>
</body></html>"""
    return html

# ══════════════════════════════════════════════════════════════════════════════
#  the scenes  —  each is a dict with a one-liner, a spice flag, a longer blurb,
#  and build(target) -> {css?, html?, js}. js must define async runScene().
# ══════════════════════════════════════════════════════════════════════════════

def _you(t): return t if t else 'you'

# ── trace: the flagship. reads their real location & device back at them ──
def s_trace(t):
    who = _you(t)
    js = r"""
async function runScene(){
  const d=await INTEL;
  await say_('> establishing reverse connection',{cls:'dim',speed:22});
  await sleep(250); tone(180,.1);
  await say_('> handshake .......... ok',{cls:'g'});
  await say_('> bypassing NAT ...... ok',{cls:'g'});
  await sleep(200);
  put('',''); put("I'M IN.",'big1 m'); put('','');
  await sleep(400); beeps(3,520);
  if(!d.online){ await say_("> couldn't read your location — you went dark. lucky.",{cls:'y'}); }
  else{
    await say_('> target located:',{cls:'dim',speed:10});
    await say_('   '+(d.city?d.city+', ':'')+(d.region?d.region+', ':'')+(d.country||''),{cls:'c',speed:24});
    await say_('   public IP    '+d.ip,{cls:'c',speed:10});
    if(d.isp)  await say_('   carrier      '+d.isp,{cls:'c',speed:10});
    if(d.lat!=null) await say_('   pin          '+d.lat.toFixed(4)+', '+d.lon.toFixed(4)+'  ● dropped',{cls:'r',speed:10});
  }
  await sleep(150);
  await say_('> fingerprinting the machine …',{cls:'dim',speed:14});
  await say_('   '+d.browser+' on '+d.os+'   ·   '+d.screen,{cls:'c',speed:10});
  if(d.cores) await say_('   '+d.cores+' cpu threads'+(d.mem?'  ·  ~'+d.mem+'GB ram':''),{cls:'c',speed:10});
  if(d.batt!=null) await say_('   battery '+d.batt+'%'+(d.charging?' (charging)':' — and dropping'),{cls:d.batt<35?'r':'c',speed:10});
  const h=d.now.getHours();
  if(h<6||h>=23) await say_('   it is '+d.now.toLocaleTimeString()+'. you should be asleep.',{cls:'y',speed:22});
  else await say_('   local time '+d.now.toLocaleTimeString(),{cls:'c',speed:14});
  await sleep(300);
  await bar('  indexing personal files',2600,{cls:'r'});
  await say_('   '+Math.floor(rnd(3000,9000))+' files catalogued',{cls:'r',speed:10});
  await sleep(500);
  put("uploading everything to my server…",'r'); tone(120,.5,'sawtooth');
  await sleep(1400);
  await reveal();
}
"""
    return {'js': js}

# ── matrix: the classic green rain takeover ──
def s_matrix(t):
    css = """
    #mx{position:absolute;inset:0}
    #ov{position:absolute;inset:0;display:grid;place-items:center;text-align:center}
    #ov .big{font-size:clamp(26px,7vw,80px);font-weight:800;color:#fff;text-shadow:0 0 18px var(--g)}
    #ov .sub{color:var(--g);margin-top:14px;font-size:clamp(13px,2.6vw,20px)}
    """
    html = '<canvas id="mx"></canvas><div id="ov" style="opacity:0"></div>'
    js = r"""
async function runScene(){
  const cv=document.getElementById('mx'),x=cv.getContext('2d');
  const R=()=>{cv.width=innerWidth;cv.height=innerHeight;}; R(); addEventListener('resize',R);
  const cols=Math.floor(cv.width/16), y=Array(cols).fill(0);
  const gl='ｱｲｳｴｵｶｷｸｹｺ0123456789<>=/\\|BITE'.split('');
  let run=true;
  (function draw(){ if(!run)return;
    x.fillStyle='rgba(5,6,10,.08)'; x.fillRect(0,0,cv.width,cv.height);
    x.font='15px monospace';
    for(let i=0;i<cols;i++){ x.fillStyle=Math.random()<.02?'#fff':'#39ff14';
      x.fillText(pick(gl),i*16,y[i]*16);
      if(y[i]*16>cv.height&&Math.random()>.975)y[i]=0; y[i]++; }
    requestAnimationFrame(draw); })();
  const d=await INTEL; tone(140,.2,'sawtooth');
  await sleep(2600);
  const ov=document.getElementById('ov');
  ov.innerHTML='<div><div class="big glitch" data-t="SYSTEM COMPROMISED">SYSTEM COMPROMISED</div>'
    +'<div class="sub">'+(d.online?('node '+esc(d.ip)+' — '+esc(d.city||d.country||'located')):'node located')+' is mine now</div></div>';
  ov.style.transition='opacity .6s'; ov.style.opacity='1'; shake(600); noise(.4);
  await sleep(2600);
  await reveal();
}
"""
    return {'css': css, 'html': html, 'js': js}

# ── bsod: the windows blue screen ──
def s_bsod(t):
    css = """
    body{background:#0078d7 !important;color:#fff;cursor:none}
    body::after{opacity:0}
    #stage{padding:9vh 12vw}
    .sad{font-size:clamp(60px,14vw,160px);font-weight:200;margin-bottom:20px}
    .bs-t{font-size:clamp(18px,3.2vw,26px);max-width:760px;line-height:1.5}
    .bs-p{margin-top:26px;font-size:clamp(15px,2.4vw,20px)}
    .bs-s{margin-top:34px;font-size:13px;opacity:.85}
    """
    js = r"""
async function runScene(){
  const d=await INTEL; noise(.25,.1);
  const s=stage();
  s.innerHTML='<div class="sad">:(</div>';
  await sleep(500);
  put('<div class="bs-t">Your PC ran into a problem and needs to restart. '
    +"We're just collecting some error info, and then we'll restart for you.</div>");
  const p=put('<div class="bs-p">0% complete</div>');
  const box=p.querySelector('.bs-p');
  for(let i=0;i<=100;i+=pick([1,2,3,5])){ box.textContent=Math.min(i,100)+'% complete'; await sleep(60); }
  put('<div class="bs-s">Stop code: BITE_GOT_YOU_0x1B17E<br>What failed: your composure.sys<br><br>'
    +'Reporting to '+esc(d.online?d.city||d.country||'nobody':'nobody')+'… press any key.</div>');
  const go=()=>{ removeEventListener('keydown',go); removeEventListener('click',go); reveal(); };
  addEventListener('keydown',go); addEventListener('click',go);
  await sleep(9000); go();
}
"""
    return {'css': css, 'js': js}

# ── panic: linux kernel panic scroll ──
def s_panic(t):
    js = r"""
async function runScene(){
  const d=await INTEL;
  const lines=['Kernel panic - not syncing: Attempted to kill init! exitcode=0x0000babe',
    'CPU: '+(d.cores||4)+' PID: 1 Comm: '+(d.browser||'init')+' Tainted: G  B  D  bitebait',
    'Hardware name: '+(d.os||'unknown')+' / '+(d.screen||'?'),
    'Call Trace:',' [<c0421337>] ? panic+0x1a/0x14',' [<c04dead0>] ? you_opened_the_link+0x0/0x0',
    ' [<c0b17e00>] ? trust_a_stranger+0x2f/0x40',' [<c0000000>] ? regret+0x0/0xfff',
    'RIP: '+(d.online?(d.ip+' ('+(d.city||d.country||'?')+')'):'0000:babe:cafe'),
    'CR2: 00000000ba5eba11','---[ end trace '+Math.random().toString(16).slice(2,14)+' ]---'];
  await say_('[    0.000000] booting the thing you should not have opened',{cls:'dim',speed:8});
  await sleep(300); tone(90,.3,'sawtooth');
  for(const l of lines){ put(esc(l),'r'); noise(.04,.05); await sleep(rnd(130,340)); }
  put('','');
  await say_('kernel is dead. so is your afternoon.',{cls:'y',speed:26});
  await sleep(1600); await reveal();
}
"""
    return {'js': js}

# ── format: erasing your disk ──
def s_format(t):
    js = r"""
async function runScene(){
  const d=await INTEL;
  const home='/home/'+((d.online&&d.city)?d.city.toLowerCase().replace(/[^a-z]/g,''):'user');
  const files=['Documents','Pictures','wallpapers','.ssh/id_ed25519','saved_passwords.kdbx',
    'that_one_folder','tax_2019.pdf','projects','not_a_virus.exe','node_modules','memories'];
  await say_('WARNING: low-level format initiated. do not power off.',{cls:'y',speed:14});
  await say_('target: '+home+'   ('+(d.screen||'')+')',{cls:'dim',speed:10});
  put('','');
  for(const f of files){
    const d2=put('  rm -rf '+esc(home)+'/'+esc(f),'r');
    await sleep(rnd(120,340));
    d2.innerHTML+=' <span class="dim">…gone</span>'; tone(rnd(200,600),.05,'square',.03);
  }
  put('','');
  await bar('  zeroing free space',3000,{cls:'r'});
  put('disk wiped. hope none of that mattered.','r'); noise(.5,.15); shake(500);
  await sleep(1600); await reveal();
}
"""
    return {'js': js}

# ── ransom: the lock screen with a countdown ──
def s_ransom(t):
    css = """
    body{background:#0a0000 !important}
    #stage{padding:6vh 8vw;display:flex;flex-direction:column;align-items:center;text-align:center}
    .lock{font-size:clamp(46px,10vw,90px)}
    .rt{color:var(--r);font-size:clamp(24px,5vw,44px);font-weight:800;margin:10px 0 6px;letter-spacing:1px}
    .rs{color:#d9a;max-width:640px;line-height:1.6}
    .clock{font-size:clamp(40px,11vw,96px);font-weight:800;color:#fff;margin:22px 0;font-variant-numeric:tabular-nums}
    .addr{color:var(--y);background:#1a0000;border:1px solid #500;padding:10px 16px;border-radius:4px;margin-top:8px;word-break:break-all}
    """
    js = r"""
async function runScene(){
  const d=await INTEL;
  const s=stage(); noise(.3,.12); tone(90,.6,'sawtooth');
  s.innerHTML='<div class="lock">🔒</div><div class="rt">YOUR FILES ARE ENCRYPTED</div>';
  await sleep(400);
  put('<div class="rs">Every document, photo and password on '+esc(d.online?(d.city||d.country||'this device'):'this device')
    +' has been locked with military-grade AES-256. Your IP '+esc(d.ip)+' has been logged.</div>');
  put('<div class="clock" id="ck">23:59:59</div>');
  put('<div class="rs">Send <b>0.0777 BTC</b> within the window or the key is destroyed forever:</div>');
  put('<div class="addr">bc1q'+Array.from({length:34},()=>pick('0123456789abcdefghijklmnpqrstuvwxyz'.split(''))).join('')+'</div>');
  let sec=24*3600-1; const ck=document.getElementById('ck');
  const iv=setInterval(()=>{ sec--; const h=(x)=>String(x).padStart(2,'0');
    ck.textContent=h(sec/3600|0)+':'+h((sec%3600)/60|0)+':'+h(sec%60); if(sec%3===0)tone(600,.04); },1000/8);
  await sleep(6500); clearInterval(iv);
  await reveal();
}
"""
    return {'css': css, 'js': js}

# ── crack: the screen shatters ──
def s_crack(t):
    css = """
    #stage{opacity:0}
    #glass{position:absolute;inset:0;pointer-events:none;opacity:0;transition:opacity .05s}
    #hint{position:fixed;left:0;right:0;top:60%;text-align:center;color:#fff;font-size:clamp(15px,3vw,24px);
      text-shadow:0 0 10px #000;opacity:0;transition:opacity .4s}
    """
    html = '<svg id="glass" xmlns="http://www.w3.org/2000/svg"></svg><div id="hint">…oh no.</div>'
    js = r"""
function shatter(cx,cy){
  const g=document.getElementById('glass'); g.setAttribute('viewBox','0 0 '+innerWidth+' '+innerHeight);
  let p=''; const ring=(n,r,jit)=>{ let pts=[];
    for(let i=0;i<n;i++){ const a=i/n*Math.PI*2, rr=r*rnd(1-jit,1+jit);
      pts.push([cx+Math.cos(a)*rr,cy+Math.sin(a)*rr]); }
    for(let i=0;i<n;i++){ const A=pts[i],B=pts[(i+1)%n];
      p+=`<line x1="${A[0]}" y1="${A[1]}" x2="${B[0]}" y2="${B[1]}"/>`; } return pts; };
  let prev=[[cx,cy]];
  for(const r of [30,80,150,260,420,650]){ const pts=ring(9,r,.35);
    for(const P of pts){ const Q=pick(prev); p+=`<line x1="${P[0]}" y1="${P[1]}" x2="${Q[0]}" y2="${Q[1]}"/>`; }
    prev=pts; }
  for(let i=0;i<26;i++){ const a=rnd(0,Math.PI*2),r=rnd(200,Math.max(innerWidth,innerHeight));
    p+=`<line x1="${cx}" y1="${cy}" x2="${cx+Math.cos(a)*r}" y2="${cy+Math.sin(a)*r}"/>`; }
  g.innerHTML='<g stroke="#cfe8ff" stroke-width="1.1" opacity=".9" fill="none">'+p
    +'</g><circle cx="'+cx+'" cy="'+cy+'" r="26" fill="rgba(255,255,255,.15)"/>';
  g.style.opacity='1';
}
async function runScene(){
  await INTEL;
  const s=stage(); s.style.opacity='1';
  s.innerHTML='<div style="text-align:center;margin-top:34vh;color:#8b93a7">loading your file…</div>';
  await sleep(1600);
  const cx=innerWidth*rnd(.35,.65), cy=innerHeight*rnd(.3,.55);
  // glass smash: sharp noise burst + high tone
  noise(.5,.35); tone(2400,.04,'square',.2); tone(1700,.06); shake(650);
  shatter(cx,cy);
  document.getElementById('hint').style.opacity='1';
  await sleep(2600); await reveal();
}
"""
    return {'css': css, 'html': html, 'js': js}

# ── typer: auto hacker-typer, personalised ──
def s_typer(t):
    who = _you(t)
    prompt = json.dumps(who)
    js = r"""
async function runScene(){
  const d=await INTEL; const WHO=%s;
  const steps=[['booting exploit kit ……………','dim'],
    ['target = '+WHO+' @ '+(d.online?d.ip:'unknown'),'c'],
    ['[+] geolocated → '+(d.online?(d.city||d.country||'?'):'?'),'g'],
    ['[+] '+d.browser+'/'+d.os+' fingerprint captured','g'],
    ['[*] cracking '+WHO+"'s instagram ………",'y'],
    ['[+] password = ••••••••••   (kidding)','g'],
    ['[*] bypassing 2FA ……………','y'],
    ['[+] 2FA bypassed. jk. i cannot do that.','g'],
    ['[*] reading DMs …','y'],['[+] wow. bold of you to keep those.','g'],
    ['[*] enabling front camera …','r'],['[+] webcam armed ● (not really)','r'],
    ['[!] deploying keylogger to '+(d.online?d.ip:'device')+' …','r']];
  for(const [txt,cls] of steps){ await say_(txt,{cls,speed:12}); tone(rnd(300,900),.03,'square',.02); await sleep(rnd(120,360)); }
  put('','');
  await say_('nah. none of that is possible from a link. but you believed it for a second.',{cls:'m',speed:22});
  await sleep(1400); await reveal();
}
""" % prompt
    return {'js': js}

# ── webcam: fake camera access, no permission actually requested ──
def s_webcam(t):
    css = """
    #cam{position:absolute;inset:0;background:#000;display:grid;place-items:center}
    #cam .frame{width:min(70vw,520px);aspect-ratio:4/3;border:2px solid #333;border-radius:6px;position:relative;
      background:repeating-conic-gradient(#111 0% 25%,#151515 0% 50%) 50%/12px 12px;overflow:hidden}
    #cam .stat{filter:none;position:absolute;inset:0;background:
      repeating-linear-gradient(0deg,rgba(255,255,255,.04) 0 2px,transparent 2px 4px);
      animation:roll .4s linear infinite;mix-blend-mode:screen}
    @keyframes roll{to{transform:translateY(4px)}}
    #cam .rec{position:absolute;top:10px;left:12px;color:#fff;font-size:13px;display:flex;gap:7px;align-items:center}
    #cam .dot{width:10px;height:10px;border-radius:50%;background:var(--r);animation:bl 1s infinite}
    @keyframes bl{50%{opacity:.2}}
    #cam .cap{position:absolute;bottom:10px;left:12px;color:#9fb;font-size:12px}
    """
    html = '<div id="cam"><div class="frame"><div class="stat"></div>'\
           '<div class="rec"><span class="dot"></span>REC · LIVE</div>'\
           '<div class="cap"></div></div></div>'
    js = r"""
async function runScene(){
  const d=await INTEL;
  await sleep(500); tone(880,.08); tone(1100,.08);
  const cap=$('#cam .cap');
  cap.textContent='requesting camera…'; await sleep(900);
  cap.textContent='ACCESS GRANTED — '+(d.online?d.city||d.country||'you':'you')+' · '+d.browser;
  $('.rec').insertAdjacentHTML('beforeend','');
  await sleep(1400);
  cap.textContent='● recording you right now';
  await sleep(1200);
  cap.innerHTML='saving clip to my server…'; await sleep(1500);
  // the truth: nothing was ever captured — no getUserMedia was called.
  await reveal();
}
"""
    return {'css': css, 'html': html, 'js': js}

# ── cursors: a swarm of fake pointers ──
def s_cursors(t):
    css = """
    .fk{position:fixed;width:20px;height:20px;z-index:9000;pointer-events:none;
      filter:drop-shadow(0 0 3px #000)}
    #stage{display:grid;place-items:center;text-align:center}
    """
    html = ''
    js = r"""
const CUR='data:image/svg+xml;utf8,'+encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><path d="M2 2l6 14 2-6 6-2z" fill="#fff" stroke="#000"/></svg>');
async function runScene(){
  const d=await INTEL;
  await say_('> multiplying input devices …',{cls:'dim',speed:16});
  await sleep(400);
  const N=45; const cur=[];
  for(let i=0;i<N;i++){ const img=new Image(); img.src=CUR; img.className='fk';
    document.body.appendChild(img); cur.push({el:img,x:Math.random()*innerWidth,y:Math.random()*innerHeight,
      vx:rnd(-4,4),vy:rnd(-4,4)}); }
  let run=true;
  (function move(){ if(!run)return; for(const c of cur){ c.x+=c.vx;c.y+=c.vy;
    if(c.x<0||c.x>innerWidth)c.vx*=-1; if(c.y<0||c.y>innerHeight)c.vy*=-1;
    c.el.style.left=c.x+'px'; c.el.style.top=c.y+'px'; } requestAnimationFrame(move); })();
  for(let i=0;i<6;i++){ tone(400+i*60,.04); await sleep(300); }
  stage().innerHTML='<div class="big1 m glitch" data-t="which one are you?">which one are you?</div>';
  await sleep(2600); await reveal();
}
"""
    return {'css': css, 'html': html, 'js': js}

# ── corrupt: the page they are reading melts ──
def s_corrupt(t):
    css = """
    #stage{display:grid;place-items:center;text-align:center}
    #doc{max-width:620px;color:#cdd;line-height:1.8;font-size:clamp(15px,2.6vw,19px)}
    """
    html = '<div id="stage"><div id="doc"></div></div>'
    js = r"""
async function runScene(){
  const d=await INTEL;
  const doc=document.getElementById('doc');
  const text="thanks for opening this! just a totally normal document. nothing "
    +"strange going on here at all. everything is fine. please keep reading. "
    +"you are safe. this is a safe and ordinary file with no surprises whatsoever.";
  for(const ch of text){ doc.textContent+=ch; await sleep(24); }
  await sleep(800);
  const GL='#$%&@!?▓�e▚0x1▘★☓█▛¿'.split('');
  for(let pass=0;pass<60;pass++){
    let s=doc.textContent.split('');
    for(let k=0;k<pass;k++){ const i=Math.floor(Math.random()*s.length); s[i]=pick(GL); }
    doc.textContent=s.join('');
    doc.style.transform='skew('+rnd(-pass/12,pass/12)+'deg) translate('+rnd(-pass/8,pass/8)+'px,0)';
    doc.style.color=pass>25?pick(['#ff2d2d','#ff00d4','#39ff14','#fff']):'#cdd';
    if(pass%6===0){ noise(.05,.06); tone(rnd(80,300),.04,'sawtooth'); }
    await sleep(55);
  }
  document.body.style.filter='invert(1) hue-rotate(90deg)'; shake(500);
  put('<div class="big1 r">it was never a document.</div>');
  await sleep(1600); document.body.style.filter=''; await reveal();
}
"""
    return {'css': css, 'html': html, 'js': js}

# ── battery: the device "dies" (uses their real battery %) ──
def s_battery(t):
    css = """
    #stage{display:grid;place-items:center;text-align:center}
    #fade{position:fixed;inset:0;background:#000;opacity:0;z-index:9500;transition:opacity 2.4s;pointer-events:none}
    .pct{font-size:clamp(40px,10vw,90px);font-weight:800;color:#fff}
    .lab{color:#8b93a7;margin-top:10px}
    """
    html = '<div id="fade"></div>'
    js = r"""
async function runScene(){
  const d=await INTEL;
  let p=(d.batt!=null)?d.batt:pick([12,9,7,4]);
  const s=stage(); s.innerHTML='<div><div class="pct" id="p">'+p+'%</div><div class="lab" id="l">battery status</div></div>';
  const pe=document.getElementById('p'),le=document.getElementById('l');
  await sleep(700);
  le.textContent=d.charging?'charging… or is it?':'critical — draining fast';
  await sleep(600);
  const step=async()=>{ p=Math.max(0,p-pick([1,2,3,4])); pe.textContent=p+'%';
    pe.style.color=p<15?'#ff2d2d':'#fff'; tone(200+p*3,.04); };
  while(p>0){ await step(); await sleep(rnd(160,360)); }
  le.textContent='shutting down'; tone(120,.5,'sine');
  document.getElementById('fade').style.opacity='1';
  await sleep(2600);
  await reveal();
}
"""
    return {'css': css, 'html': html, 'js': js}

# ── update: the eternal "configuring updates" troll ──
def s_update(t):
    css = """
    body{background:#0a4a8f !important}
    body::after{opacity:0}
    #stage{display:grid;place-items:center;text-align:center}
    .spin{width:64px;height:64px;border:6px solid rgba(255,255,255,.25);border-top-color:#fff;border-radius:50%;
      animation:sp 1s linear infinite;margin:0 auto 26px}
    @keyframes sp{to{transform:rotate(360deg)}}
    .ut{color:#fff;font-size:clamp(18px,3.4vw,28px)}
    .uw{color:#cfe0ff;margin-top:14px;font-size:clamp(13px,2.4vw,18px)}
    """
    js = r"""
async function runScene(){
  await INTEL;
  stage().innerHTML='<div><div class="spin"></div><div class="ut" id="u">Working on updates 0%</div>'
    +'<div class="uw">Don\'t turn off your computer. This will take a while.</div></div>';
  const u=document.getElementById('u');
  const seq=[0,0,1,3,3,7,14,27,27,27,31,49,72,88,99,99,99,100];
  for(const v of seq){ u.textContent='Working on updates '+v+'% complete'; tone(500,.03,'sine',.02); await sleep(rnd(500,1300)); }
  await sleep(1200);
  u.textContent="…it was never going to finish.";
  await sleep(1400); await reveal();
}
"""
    return {'css': css, 'js': js}

# ── selfdestruct: big red countdown ──
def s_selfdestruct(t):
    css = """
    #stage{display:grid;place-items:center;text-align:center}
    .sd{color:var(--r);font-size:clamp(20px,5vw,40px);font-weight:800;letter-spacing:3px}
    .num{font-size:clamp(90px,30vw,300px);font-weight:900;color:#fff;line-height:1;font-variant-numeric:tabular-nums;
      text-shadow:0 0 40px var(--r)}
    """
    js = r"""
async function runScene(){
  const d=await INTEL;
  const s=stage();
  s.innerHTML='<div><div class="sd">SELF-DESTRUCT SEQUENCE ARMED</div><div class="num" id="n">10</div>'
    +'<div class="sd" id="tgt" style="font-size:14px;letter-spacing:1px;color:#d99"></div></div>';
  document.getElementById('tgt').textContent=d.online?('target: '+(d.city||d.country||'this device')+' · '+d.ip):'target locked';
  const n=document.getElementById('n');
  for(let i=10;i>=1;i--){ n.textContent=i; n.style.color=i<=3?'#ff2d2d':'#fff';
    tone(i<=3?900:500,.12,'square',.08); shake(120); await sleep(900); }
  n.textContent='0'; noise(.6,.4); shake(700);
  document.body.style.background='#fff'; await sleep(120); document.body.style.background='';
  await sleep(900);
  put('<div class="sd">…pfft. it was a webpage. what did you think would happen?</div>');
  await sleep(1600); await reveal();
}
"""
    return {'css': css, 'js': js}

# ── bitten: the gentle brand-only reveal ──
def s_bitten(t):
    who = _you(t)
    js = r"""
async function runScene(){
  const d=await INTEL; const WHO=%s;
  await say_('> hi '+WHO+'.',{cls:'g',speed:40});
  await sleep(500);
  await say_('> i can see you are on '+d.browser+', '+(d.online?(d.city||d.country||'somewhere'):'somewhere')
    +', at '+d.now.toLocaleTimeString()+'.',{cls:'c',speed:22});
  await say_('> relax. every website knows that much. i just said it out loud.',{cls:'dim',speed:20});
  await sleep(700);
  put('<div class="big1 m glitch" data-t="you’ve been bitten">you’ve been bitten</div>');
  await sleep(1800); await reveal();
}
""" % json.dumps(who)
    return {'js': js}

SCENES = {
 'trace':   {'title':'trace',   'spicy':False, 'pagetitle':'connecting…',
   'desc':'"I\'m in." Reads their REAL city, IP, carrier, device and battery back at them, then fake-uploads their files.',
   'about':'the flagship. reads the real data any web page already sees — public IP, the city it maps to, carrier, '
           'browser, screen, cpu, battery, the actual local time — and recites it like a break-in, then pretends to '
           'index and upload their files. every line is true, which is what makes it land.',
   'build':s_trace},
 'matrix':  {'title':'matrix',  'spicy':False, 'pagetitle':'…',
   'desc':'Full green matrix-rain takeover, then SYSTEM COMPROMISED stamped over their real IP.',
   'about':'the classic. green code rains over the whole screen, then a glitching SYSTEM COMPROMISED lands over their '
           'real IP and city. loud, familiar, instantly readable on camera.',
   'build':s_matrix},
 'bsod':    {'title':'bsod',    'spicy':False, 'pagetitle':'',
   'desc':'A pixel-perfect Windows blue-screen of death with a joke stop code. Any key reveals.',
   'about':'the windows blue screen, sad face and all, filling to 100% with the stop code BITE_GOT_YOU. works a treat '
           'on someone who actually runs windows. any key or click drops the act.',
   'build':s_bsod},
 'panic':   {'title':'panic',   'spicy':False, 'pagetitle':'kernel',
   'desc':'A Linux kernel panic scrolls by — call trace, tainted flags, their specs woven in.',
   'about':'the linux sibling of bsod: a kernel panic with a call trace of functions like trust_a_stranger() and '
           'regret(), their real cpu count and ip folded in. for the penguin crowd.',
   'build':s_panic},
 'format':  {'title':'format',  'spicy':True,  'pagetitle':'',
   'desc':'"Formatting your disk — do not power off." Named files delete one by one, then it zeroes free space.',
   'about':'rm -rf marches down a list of scary-sounding files (.ssh keys, saved_passwords.kdbx, memories/) one at a '
           'time, then zeroes the disk. spicy — it looks genuinely destructive until the punchline, so aim it at '
           'someone who can take it.',
   'build':s_format},
 'ransom':  {'title':'ransom',  'spicy':True,  'pagetitle':'!',
   'desc':'A ransomware lock screen: "files encrypted", a fake BTC address and a ticking countdown.',
   'about':'the full ransomware lock: YOUR FILES ARE ENCRYPTED, a generated bitcoin address, their real ip logged, and '
           'a countdown burning down. the spiciest one — very convincing, so only for friends with a sense of humour.',
   'build':s_ransom},
 'crack':   {'title':'crack',   'spicy':False, 'pagetitle':'loading…',
   'desc':'Their screen appears to physically shatter from where they "tapped", with a glass-smash crack.',
   'about':'opens on a harmless "loading your file…", then the screen shatters — a real crack pattern spidering out '
           'from a random point with a glass-smash sound. the one everyone tries to wipe off with their sleeve.',
   'build':s_crack},
 'typer':   {'title':'typer',   'spicy':False, 'pagetitle':'…',
   'desc':'A hacker terminal auto-types its way through "cracking" their Instagram, 2FA and DMs — using their name.',
   'about':'hollywood-hacker auto-typer, personalised with the name you give it: cracking THEIR instagram, bypassing '
           '2FA, reading THEIR dms — each line undercut at the end by admitting a link cannot do any of that.',
   'build':s_typer},
 'webcam':  {'title':'webcam',  'spicy':False, 'pagetitle':'',
   'desc':'A fake "CAMERA ACCESS GRANTED · REC ●" viewfinder. It never actually touches the camera.',
   'about':'a live-looking camera viewfinder with a blinking REC dot that claims to be recording and uploading them. '
           'it never calls getUserMedia — nothing is ever captured — which is the whole gag once it reveals.',
   'build':s_webcam},
 'cursors': {'title':'cursors', 'spicy':False, 'pagetitle':'…',
   'desc':'Dozens of fake mouse pointers swarm the screen — "which one are you?"',
   'about':'input "multiplies": forty-odd fake cursors scatter and bounce around the screen until it asks which one is '
           'really theirs. silly, harmless, good for a laugh rather than a scare.',
   'build':s_cursors},
 'corrupt': {'title':'corrupt', 'spicy':False, 'pagetitle':'document',
   'desc':'A calm "totally normal document" they\'re reading slowly corrupts into glitching garbage.',
   'about':'lulls them with a reassuring little document, then rots it in place — characters decay to glyphs, the text '
           'skews and inverts — before admitting it was never a document. a slow burn.',
   'build':s_corrupt},
 'battery': {'title':'battery', 'spicy':False, 'pagetitle':'',
   'desc':'Reads their REAL battery %, then drains it to 0 on screen and fakes a shutdown.',
   'about':'grabs their actual battery level and counts it down to zero, dimming to black like the device died. spooky '
           'precisely because it starts from the true number. (falls back to a low guess if the browser hides it.)',
   'build':s_battery},
 'update':  {'title':'update',  'spicy':False, 'pagetitle':'',
   'desc':'The eternal "Working on updates — don\'t turn off your computer" that never, ever finishes.',
   'about':'the update screen everyone dreads, stuck climbing and stalling at 27% and 99% forever, before it admits it '
           'was never going to finish. quiet, relatable, infuriating.',
   'build':s_update},
 'selfdestruct':{'title':'selfdestruct','spicy':False,'pagetitle':'⚠',
   'desc':'A giant red "SELF-DESTRUCT IN 10…" countdown over their location, that fizzles at zero.',
   'about':'a huge red countdown from ten with escalating beeps and screen-shake, target locked on their city and ip, '
           'that flashes white at zero and then sheepishly admits it was only a webpage.',
   'build':s_selfdestruct},
 'bitten':  {'title':'bitten',  'spicy':False, 'pagetitle':'hi.',
   'desc':'The gentle one: greets them by name, calmly recites what any site sees, reveals. No scare.',
   'about':'the soft option. no takeover — it just greets them, quietly notes their browser, city and local time, '
           'points out every website already knows that, and reveals. use it when a full scare would be too much.',
   'build':s_bitten},
}

# ══════════════════════════════════════════════════════════════════════════════
#  hosting  —  turn the page into something you can send
# ══════════════════════════════════════════════════════════════════════════════

def _lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('1.1.1.1', 80)); ip = s.getsockname()[0]; s.close(); return ip
    except Exception:
        return '127.0.0.1'

def _bait_id(scene):
    return scene + '-' + ''.join(random.choice('abcdefghijkmnpqrstuvwxyz23456789') for _ in range(6))

def _clip(url):
    if not COPYLINK: return
    for tool in (['wl-copy'], ['xclip', '-selection', 'clipboard']):
        if shutil.which(tool[0]):
            try:
                subprocess.run(tool, input=url.encode(), check=True); ok('link copied to your clipboard'); return
            except Exception:
                pass

def _qr(url):
    if not QR or not shutil.which('qrencode'): return
    try:
        print(); subprocess.run(['qrencode', '-t', 'ANSIUTF8', '-m', '1', url])
    except Exception:
        pass

def _log(scene, where, url):
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        with open(LOG, 'a') as f:
            f.write(f'{time.strftime("%Y-%m-%d %H:%M")}\t{scene}\t{where}\t{url}\n')
    except Exception:
        pass

def _serve_dir(root, port, host='0.0.0.0'):
    """Start a quiet static server in a thread. Returns the httpd."""
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k): super().__init__(*a, directory=str(root), **k)
        def log_message(self, *a): pass
    httpd = http.server.ThreadingHTTPServer((host, port), H)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd

def host_file(html, bait_id, scene):
    Path(OUTDIR).mkdir(parents=True, exist_ok=True)
    p = Path(OUTDIR) / (bait_id + '.html')
    p.write_text(html, encoding='utf-8')
    ok(f'prank forged → {BLD}{p}{RST}')
    url = 'file://' + str(p)
    say(f'  {DIM}it is one self-contained file. send it, or open it locally to try it:{RST}')
    say(f'    {CYN}xdg-open {p}{RST}')
    say(f'  {DIM}to hand a friend a real https link instead, set a host:{RST}')
    say(f'    {CYN}bite-toys config bitebait host github{RST}   {DIM}(one-time setup — see the toy\'s about){RST}')
    _clip(url); _log(scene, 'file', str(p))
    return url

def host_local(html, bait_id, scene):
    root = CACHE / 'bitebait-serve'
    d = root / bait_id; d.mkdir(parents=True, exist_ok=True)
    (d / 'index.html').write_text(html, encoding='utf-8')
    ip = _lan_ip()
    url = f'http://{ip}:{PORT}/{bait_id}/'
    try:
        _serve_dir(root, PORT)
    except OSError as e:
        die(f'could not open port {PORT} ({e}). set another: bite-toys config bitebait port 9000')
    ok('serving on your local network — this link works for anyone on the same wifi:')
    say(f'    {BLD}{CYN}{url}{RST}')
    _clip(url); _qr(url); _log(scene, 'local', url)
    warn('this link only lives while this stays open. ctrl-c ends it.')
    try:
        while True: time.sleep(1)
    except KeyboardInterrupt:
        say('\nserver closed — link is dead now.')
    return url

def host_tunnel(html, bait_id, scene):
    cf = shutil.which('cloudflared')
    if not cf:
        die('tunnel needs cloudflared — sudo pacman -S cloudflared — or use host=github / host=local')
    root = CACHE / 'bitebait-serve'
    d = root / bait_id; d.mkdir(parents=True, exist_ok=True)
    (d / 'index.html').write_text(html, encoding='utf-8')
    _serve_dir(root, PORT, host='127.0.0.1')
    say(f'{DIM}opening a public tunnel…{RST}')
    proc = subprocess.Popen([cf, 'tunnel', '--url', f'http://127.0.0.1:{PORT}'],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    pub = None
    try:
        for line in proc.stdout:
            m = re.search(r'https://[a-z0-9-]+\.trycloudflare\.com', line)
            if m:
                pub = m.group(0) + f'/{bait_id}/'; break
        if not pub:
            die('cloudflared did not hand back a URL — try again, or use host=github')
        ok('public link is live — send this to anyone, anywhere:')
        say(f'    {BLD}{CYN}{pub}{RST}')
        _clip(pub); _qr(pub); _log(scene, 'tunnel', pub)
        warn('the tunnel is temporary — it dies when you ctrl-c here.')
        proc.wait()
    except KeyboardInterrupt:
        say('\ntunnel closed — link is dead now.')
    finally:
        proc.terminate()
    return pub

def host_github(html, bait_id, scene):
    if not GH_REPO or '/' not in GH_REPO:
        die('github hosting needs a repo first:\n'
            f'    {CYN}bite-toys config bitebait gh_repo YOUR-USER/baits{RST}\n'
            '  create that repo on github, enable Pages (Settings → Pages → deploy from main),\n'
            '  and make sure `git push` to it works without a password (ssh key or gh auth).')
    if not shutil.which('git'):
        die('git is missing — sudo pacman -S git')
    user, name = GH_REPO.split('/', 1)
    work = CACHE / 'bitebait-pages'
    remote = f'git@github.com:{GH_REPO}.git'
    try:
        if not (work / '.git').exists():
            shutil.rmtree(work, ignore_errors=True)
            say(f'{DIM}cloning {GH_REPO}…{RST}')
            if subprocess.run(['git', 'clone', '--depth', '1', remote, str(work)]).returncode != 0:
                # fall back to https if ssh is not set up
                subprocess.run(['git', 'clone', '--depth', '1',
                                f'https://github.com/{GH_REPO}.git', str(work)], check=True)
        sub = work / 'baits' / bait_id
        sub.mkdir(parents=True, exist_ok=True)
        (sub / 'index.html').write_text(html, encoding='utf-8')
        subprocess.run(['git', '-C', str(work), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(work), 'commit', '-m', f'bait: {bait_id}'], check=True)
        if subprocess.run(['git', '-C', str(work), 'push']).returncode != 0:
            die('push failed — check that you can push to ' + GH_REPO)
    except subprocess.CalledProcessError as e:
        die(f'git step failed ({e}). is the repo real and pushable?')
    url = f'https://{user.lower()}.github.io/{name}/baits/{bait_id}/'
    ok('published to github pages — real, lasting link:')
    say(f'    {BLD}{CYN}{url}{RST}')
    say(f'  {DIM}pages can take a minute on the first publish, and once per repo you must enable it in Settings → Pages.{RST}')
    _clip(url); _qr(url); _log(scene, 'github', url)
    return url

HOSTS = {'file': host_file, 'local': host_local, 'tunnel': host_tunnel, 'github': host_github}

# ══════════════════════════════════════════════════════════════════════════════
#  cli
# ══════════════════════════════════════════════════════════════════════════════

def print_catalog(full=False):
    say(f'{BLD}{BRAND} bitebait{RST} {DIM}— harmless "you\'ve been hacked" prank links{RST}\n')
    for k, s in SCENES.items():
        spice = f' {RED}◆ spicy{RST}' if s['spicy'] else ''
        say(f'  {BLD}{CYN}{k:<13}{RST}{spice}')
        say(f'  {DIM}└{RST} {s["desc"]}')
        if full:
            say(f'    {DIM}{s["about"]}{RST}')
        say('')
    say(f'{DIM}send with:{RST} bitebait make <scene>    ·    {DIM}just browse:{RST} bitebait (no args)')

def choose_interactive():
    print_catalog(full=False)
    keys = list(SCENES)
    try:
        pick_s = input(f'\n{BLD}which prank?{RST} (name, or number 1-{len(keys)}) ').strip()
    except (EOFError, KeyboardInterrupt):
        say('\nnothing forged.'); sys.exit(0)
    if pick_s.isdigit() and 1 <= int(pick_s) <= len(keys):
        scene = keys[int(pick_s) - 1]
    elif pick_s in SCENES:
        scene = pick_s
    else:
        die(f'no scene called "{pick_s}"')
    if SCENES[scene]['spicy']:
        warn('heads up: this one looks genuinely destructive until the reveal. good friends only.')
    try:
        target = input(f"{BLD}their name?{RST} (optional, personalises it) [{DEF_NAME or 'skip'}] ").strip() or DEF_NAME
        default_msg = 'you got bitten. it was a joke — nothing happened. love you.'
        gotcha = input(f'{BLD}your gotcha line?{RST} [default] ').strip() or default_msg
        host = input(f'{BLD}where should the link live?{RST} (file/local/tunnel/github) [{DEF_HOST}] ').strip() or DEF_HOST
    except (EOFError, KeyboardInterrupt):
        say('\nnothing forged.'); sys.exit(0)
    forge(scene, target, gotcha, host)

def forge(scene, target, gotcha, host):
    if scene not in SCENES: die(f'no scene called "{scene}" — try: bitebait list')
    if host not in HOSTS:   die(f'unknown host "{host}" — one of: {", ".join(HOSTS)}')
    html = build_page(scene, target, gotcha)
    bait_id = _bait_id(scene)
    say('')
    HOSTS[host](html, bait_id, scene)

def cmd_make(argv):
    scene = argv[0] if argv else None
    if not scene: die('usage: bitebait make <scene> [--name X] [--msg "..."] [--host file|local|tunnel|github]')
    target, gotcha, host = DEF_NAME, 'you got bitten. it was a joke — nothing happened. love you.', DEF_HOST
    out_override = None
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in ('--name', '-n') and i+1 < len(argv): target = argv[i+1]; i += 2
        elif a in ('--msg', '-m') and i+1 < len(argv): gotcha = argv[i+1]; i += 2
        elif a in ('--host', '-H') and i+1 < len(argv): host = argv[i+1]; i += 2
        elif a in ('--out', '-o') and i+1 < len(argv): out_override = argv[i+1]; i += 2
        else: die(f'unknown option: {a}')
    if out_override:
        global OUTDIR
        OUTDIR = os.path.dirname(os.path.abspath(out_override)) or OUTDIR
    forge(scene, target, gotcha, host)

HELP = f"""{BLD}bitebait{RST} — forge a harmless "you've been hacked" prank link and send it.

  {CYN}bitebait{RST}                     browse the scenes and forge one, step by step
  {CYN}bitebait list{RST}                list every prank scene with a one-line description
  {CYN}bitebait about{RST}               the same list, with the longer blurbs
  {CYN}bitebait make <scene>{RST}        forge one directly
      {DIM}--name  <name>   personalise it (their name){RST}
      {DIM}--msg   "<text>" your own GOTCHA line{RST}
      {DIM}--host  <where>  file · local · tunnel · github{RST}

  {BLD}how the link can live:{RST}
    {CYN}file{RST}    a self-contained .html you send as a file       {DIM}(works offline, no setup){RST}
    {CYN}local{RST}   a link for anyone on your wifi                  {DIM}(dies when you close it){RST}
    {CYN}tunnel{RST}  a temporary public https link                  {DIM}(needs cloudflared){RST}
    {CYN}github{RST}  a real, lasting github-pages link               {DIM}(one-time repo setup){RST}

  every scene ends on GOTCHA and reassures them. nothing installs, nothing is
  collected, nothing is sent back to you. ESC ends any scene. it is a jump-scare,
  not a trap — and never asks for a password, so it is not phishing.
"""

def main():
    argv = sys.argv[1:]
    if not argv:
        choose_interactive(); return
    cmd = argv[0]
    if cmd in ('--preview',):        print_catalog(full=False); return
    if cmd in ('list', 'ls', 'scenes'): print_catalog(full=False); return
    if cmd in ('about', 'info'):     print_catalog(full=True); return
    if cmd in ('-h', '--help', 'help'): print(HELP); return
    if cmd == 'make':                cmd_make(argv[1:]); return
    if cmd in SCENES:                cmd_make(argv); return   # `bitebait trace` shorthand
    die(f'unknown command: {cmd}  (try: bitebait --help)')

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        say('\nbye.')
