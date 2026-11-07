"""Private, loopback-only Chrome/Edge CDP session. Never attaches to user profiles.

Uses a fixed isolated-world script, not model-generated JavaScript. Element ids
are bound to a page/document; Playwright executes checked element actions.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

from agent_runtime import ActionError, ExecutionUncertain, Stopped, Observation, SENSITIVE, clean_env, safe_url


def compact_observation(data, targets, media=None, max_bytes=7500):
    """Budget complete records, never cut serialized JSON or an element reference."""
    def clipped(value, size):
        return str(value or '').encode('utf-8')[:size].decode('utf-8', errors='ignore')
    payload = {'url':clipped(data.get('url'),500), 'title':clipped(data.get('title'),200),
        'ready_state':data.get('ready_state'),
        'viewport':data.get('viewport'), 'elements':{},
        'text':clipped(data.get('text'),4200 if (data.get('inspection') or {}).get('kind')=='text' else 3000),
        'omitted_elements':len(targets)}
    payload['tabs'] = [{'id':t['id'],'title':clipped(t.get('title'),100),
                        'url':clipped(t.get('url'),180)} for t in data.get('tabs',[])[:8]]
    if media:
        payload['media'] = media[:4]
    if data.get('inspection') is not None:
        payload['inspection'] = data['inspection']
    def encode():
        return json.dumps(payload,ensure_ascii=False,separators=(',',':'))
    records = list(targets.items())
    # A crowded navigation bar must not hide the field needed to search a page.
    priority = sorted(range(len(records)), key=lambda i:(
        0 if records[i][1].get('type') in ('input','textarea','select') else
        1 if records[i][1].get('result_rank') is not None else 2,i))
    selected = {}
    for index in priority:
        identifier, item = records[index]
        entry = {'name':clipped(item.get('name'),180),'type':item.get('type'),'order':index}
        for key in ('search','search_submit','empty','disabled','role','checked','rect','context'):
            if item.get(key) is not None:
                entry[key] = item[key]
        if item.get('url'):
            entry['url'] = clipped(item['url'],220)
        if item.get('result_rank') is not None:
            entry['result_rank'] = item['result_rank']
        payload['elements'][identifier] = entry
        payload['omitted_elements'] = len(records)-len(payload['elements'])
        if len(encode().encode('utf-8')) > max_bytes:
            del payload['elements'][identifier]
            payload['omitted_elements'] = len(records)-len(payload['elements'])
        else:
            selected[identifier] = item
    payload['elements'] = dict(sorted(payload['elements'].items(),key=lambda pair:pair[1]['order']))
    selected = {identifier:targets[identifier] for identifier in payload['elements']}
    return encode(), selected


SCRIPT = r"""(() => {
const store = globalThis.__jarvisState ||= {seq:0, nodes:new Map(), nodeIds:new WeakMap()};
const inspection=globalThis.__jarvisInspection||null;
delete globalThis.__jarvisInspection;
let matches=0;
store.nodeIds ||= new WeakMap();
for(const [key,node] of store.nodes) if(!node.isConnected) store.nodes.delete(key);
const items=[];
const pageUrl=new URL(location.href);
const searchPage=/search/i.test(pageUrl.pathname)||['q','query','search_query'].some(k=>pageUrl.searchParams.has(k));
const resultRanks=new Map();
function visibleText(root,limit=5000) {
 const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT); const parts=[]; let n,total=0,seen=0;
 while((n=walker.nextNode()) && seen++<12000 && total<limit) {
  const value=n.textContent.trim(); const p=n.parentElement;
  if(!value||!p||p.closest('script,style,noscript')) continue;
  const range=document.createRange(); range.selectNodeContents(n); const r=range.getBoundingClientRect();
  if(r.width<1||r.height<1||r.bottom<=0||r.top>=innerHeight||r.right<=0||r.left>=innerWidth) continue;
  const x=(Math.max(0,r.left)+Math.min(innerWidth,r.right))/2;
  const y=(Math.max(0,r.top)+Math.min(innerHeight,r.bottom))/2;
  const hit=document.elementFromPoint(x,y);
  if(!hit||!(p===hit||p.contains(hit)||hit.contains(p))) continue;
  const style=getComputedStyle(p); if(style.visibility==='hidden'||style.display==='none') continue;
  parts.push(value); total+=value.length+1;
 }
 return parts.join('\n').slice(0,limit);
}
function mediaKey(e) {
 try {
  const url=new URL(e.href);
  // Channel/profile links share /video/ on some sites; they are not videos.
  if(/\/(?:video|shorts|clip)\/(?:person|channel|channels|user|users|category|categories)(?:\/|$)/i.test(url.pathname)) return null;
  if(!/\/(?:video|shorts|clip)\/[^/]+/.test(url.pathname) && !(url.pathname==='/watch'&&url.searchParams.has('v'))) return null;
  url.hash='';
  // A thumbnail and title can carry different tracking/playback parameters.
  // Rank the video identity once, not each URL variant of the same card.
  if(url.pathname==='/watch') {
   const video=url.searchParams.get('v'); url.search=''; url.searchParams.set('v',video);
  } else { url.search=''; url.pathname=url.pathname.replace(/\/+$/,'')+'/'; }
  return url.href;
 } catch {return null;}
}
if(searchPage) {
 const main=document.querySelector('main,[role="main"]')||document.body;
 for(const link of main?.querySelectorAll('a[href]')||[]) {
  const key=mediaKey(link), rect=link.getBoundingClientRect(), style=getComputedStyle(link);
  if(key && rect.width>=2 && rect.height>=2 && style.display!=='none' && style.visibility!=='hidden' && !resultRanks.has(key)) resultRanks.set(key,resultRanks.size+1);
 }
}
function searchInput(e) {
 const label=(e.getAttribute('aria-label')||e.labels?.[0]?.innerText||e.getAttribute('placeholder')||e.name||'').trim().replace(/\s+/g,' ');
 return e.matches('input[type="search"],[role="searchbox"]') || (e.matches('input,textarea') && /^(?:search|search query|search videos|search bar|address bar|address and search bar|search or enter address|enter search or web address|omnibox|поиск|найти|поиск видео|строка поиска|строка адреса|адресная строка|адрес и строка поиска|поиск или ввод адреса|введите адрес или поисковый запрос|что ищем\??)$/i.test(label));
}
for (const e of document.querySelectorAll('a,button,input,textarea,select,label[for],[role="button"],[role="link"],[role="radio"],[role="option"],[role="tab"],[contenteditable="true"]')) {
 if(inspection?.scope==='text') break;
 const r=e.getBoundingClientRect();
 const style=getComputedStyle(e);
 if(r.width<2 || r.height<2 || r.bottom<0 || r.right<0 || r.top>innerHeight || r.left>innerWidth || style.visibility==='hidden' || style.display==='none') continue;
 // Layout visibility alone includes buttons covered by autocomplete or dialogs.
 const left=Math.max(0,r.left), top=Math.max(0,r.top), right=Math.min(innerWidth,r.right), bottom=Math.min(innerHeight,r.bottom);
 if(right<=left || bottom<=top || ![.2,.5,.8].some(f=>{
   const hit=document.elementFromPoint(left+(right-left)*f,top+(bottom-top)*.5);
   return hit && (hit===e || e.contains(hit));
 })) continue;
 if(e.matches('input[type="password"],input[type="hidden"]') || /password|парол|one.time.code|cc-number|cc-csc/i.test([e.name,e.autocomplete,e.type].join(' '))) continue;
 let id=store.nodeIds.get(e);
 if(!id) {id='b'+(++store.seq);store.nodes.set(id,e);store.nodeIds.set(e,id);}
 const buttonValue=e.matches('input[type="submit"],input[type="button"],input[type="reset"]')?e.value:'';
 const labelled=(e.getAttribute('aria-labelledby')||'').split(/\s+/).map(id=>document.getElementById(id)?.innerText||'').join(' ').trim();
 const icon=e.querySelector('svg title')?.textContent||e.querySelector('svg[aria-label]')?.getAttribute('aria-label')||e.querySelector('svg use')?.getAttribute('href')||e.querySelector('svg use')?.getAttribute('xlink:href')||'';
 const name=(e.getAttribute('aria-label')||labelled||e.labels?.[0]?.innerText||e.innerText||buttonValue||e.getAttribute('title')||e.getAttribute('placeholder')||e.name||icon||e.getAttribute('data-testid')||'').trim().slice(0,180);
 if(inspection) {
   if(inspection.id ? id!==inspection.id : !name.toLocaleLowerCase().includes(inspection.query.toLocaleLowerCase())) continue;
   const index=matches++;
   if(index<inspection.offset || items.length>=24) continue;
 }
 const search=searchInput(e);
 const form=e.form||e.closest('form');
 const fields=form?[...form.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="radio"]):not([type="checkbox"]),textarea,[contenteditable="true"]')]:[];
 const searchForm=fields.length>0 && fields.every(searchInput);
 const search_submit=e.matches('button,input[type="submit"],[role="button"]') &&
   (/^(?:поиск|найти|искать|поиск видео|кнопка поиска|search|search videos|submit search|search button)$/i.test(name.trim().replace(/\s+/g,' ')) || searchForm && e.type==='submit');
 items.push({id,name,type:e.tagName.toLowerCase(),input_type:e.type||'',search,search_submit,focused:document.activeElement===e,
 role:e.getAttribute('role')||undefined,
 checked:e.matches('input[type="radio"],input[type="checkbox"]')?e.checked:e.getAttribute('aria-checked')||undefined,
 context:(e.closest('fieldset,[role="group"],article,li')||e.parentElement)?.innerText?.trim().replace(/\s+/g,' ').slice(0,200),
 result_rank:e.tagName==='A'?resultRanks.get(mediaKey(e)):undefined,
 empty:('value' in e && typeof e.value==='string')?e.value.length===0:undefined,
 _value_state:e.matches('input,textarea')&&typeof e.value==='string'?e.value:undefined,
 url:e.tagName==='A'?e.href:undefined,disabled:!!e.disabled,rect:[r.left,r.top,r.right,r.bottom].map(Math.round)});
 if(!inspection && items.length>=1000) break;
}
let bodyText=inspection?.scope==='text'?(document.body?.innerText||''):visibleText(document.body);
if(inspection?.scope==='text' && inspection.query) bodyText=bodyText.split('\n').filter(line=>line.toLocaleLowerCase().includes(inspection.query.toLocaleLowerCase())).join('\n');
const textMode=inspection?.scope==='text';
return {url:location.href,title:document.title,ready_state:document.readyState,document_id:String(performance.timeOrigin),viewport:[innerWidth,innerHeight],items,
 inspection:inspection?{kind:textMode?'text':'elements',matches:textMode?bodyText.length:matches,
 next_offset:textMode?(inspection.offset+1000<bodyText.length?inspection.offset+1000:null):(matches>inspection.offset+items.length?inspection.offset+items.length:null)}:undefined,
 text:textMode?bodyText.slice(inspection.offset,inspection.offset+1000):bodyText.slice(0,5000)};
})()"""


class ManagedBrowser:
    def __init__(self, *, profile=None, guard=None, broker=None):
        from websockets.sync.client import connect
        self.connect = connect
        self.process = self.ws = None
        self.seq = 0
        self.context = None
        self.actions = None
        self.guard = guard or (lambda: None)
        self.broker = broker
        self.profile = Path(profile) if profile else Path(os.environ.get("LOCALAPPDATA", tempfile.gettempdir())) / "JARVIS/agent-browser"
        self.profile.mkdir(parents=True, exist_ok=True)
        self.page_id = ""
        self._selective_observation = True

    def _start(self):
        managed_port = os.environ.get('JARVIS_AGENT_BROWSER_PORT', '').strip()
        if not managed_port and self.broker is not None:
            managed_port = str(self.broker())
            os.environ['JARVIS_AGENT_BROWSER_PORT'] = managed_port
        if managed_port.isdigit() and 1 <= int(managed_port) <= 65535:
            self.port = int(managed_port)
            pages = self.pages()
            page = next((p for p in pages if p.get('type') == 'page'), None)
            if not page:
                request = urllib.request.Request(
                    f"http://127.0.0.1:{self.port}/json/new?about:blank", method="PUT")
                with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request, timeout=2):
                    pass
                pages = self.pages()
                page = next((p for p in pages if p.get('type') == 'page'), None)
            if not page:
                raise ActionError("Окно Jarvis Browser не открыло страницу")
            self.page_id = page['id']
            self.ws = self.connect(page['webSocketDebuggerUrl'], open_timeout=3, max_size=8_000_000)
            self.call("Page.enable")
            self.call("Runtime.enable")
            self.call("Page.bringToFront")
            from agent_playwright import BrowserActions
            self.actions = BrowserActions(f"http://127.0.0.1:{self.port}")
            return
        candidates = [Path(os.environ.get("PROGRAMFILES", "")) / "Google/Chrome/Application/chrome.exe",
            Path(os.environ.get("PROGRAMFILES(X86)", "")) / "Microsoft/Edge/Application/msedge.exe",
            Path(os.environ.get("LOCALAPPDATA", "")) / "Google/Chrome/Application/chrome.exe"]
        exe = next((p for p in candidates if p.is_file()), None)
        if not exe:
            raise ActionError("Для управляемого браузера нужен Chrome или Edge")
        port_file = self.profile / "DevToolsActivePort"
        # Persistent profile belongs only to the agent's managed browser.
        # A stale port file must not attach us to somebody else's listening process.
        if port_file.exists():
            port_file.unlink()
        self.process = subprocess.Popen([str(exe), "--remote-debugging-port=0",
            "--remote-debugging-address=127.0.0.1", "--user-data-dir=" + str(self.profile),
            "--no-first-run", "--no-default-browser-check", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=0x08000000, env=clean_env())
        end = time.monotonic() + 12
        while time.monotonic() < end:
            if port_file.exists():
                lines = port_file.read_text().splitlines()
                if lines and lines[0].isdigit():
                    self.port = int(lines[0])
                    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(f"http://127.0.0.1:{self.port}/json/list", timeout=2) as resp:
                        pages = json.load(resp)
                    page = next((p for p in pages if p.get("type") == "page"), None)
                    if page:
                        self.page_id = page["id"]
                        self.ws = self.connect(page["webSocketDebuggerUrl"], open_timeout=3, max_size=8_000_000)
                        self.call("Page.enable")
                        self.call("Runtime.enable")
                        from agent_playwright import BrowserActions
                        self.actions = BrowserActions(f"http://127.0.0.1:{self.port}")
                        return
            time.sleep(0.1)
        raise ActionError("Не удалось открыть управляемый браузер")

    def call(self, method, params=None):
        self.seq += 1
        number = self.seq
        self.ws.send(json.dumps({"id": number, "method": method, "params": params or {}}))
        end = time.monotonic() + 8
        while time.monotonic() < end:
            message = json.loads(self.ws.recv(timeout=max(0.05, end-time.monotonic())))
            if message.get("id") == number:
                if "error" in message:
                    raise ActionError("Браузер отклонил действие")
                return message.get("result", {})
        raise ActionError("Браузер не ответил")

    def evaluate(self, expression):
        if self.context is None:
            frame = self.call("Page.getFrameTree")["frameTree"]["frame"]
            self.context = self.call("Page.createIsolatedWorld", {
                "frameId": frame["id"], "worldName": "jarvis-agent"})["executionContextId"]
        result = self.call("Runtime.evaluate", {"expression": expression, "contextId": self.context,
                                                "returnByValue": True})
        if result.get("exceptionDetails"):
            raise ActionError("Страница изменилась; нужно новое наблюдение")
        return result.get("result", {}).get("value")

    def open(self, url):
        safe_url(url)
        if self.ws is None:
            self._start()
        page = self.actions.select_page(self.page_id)
        # A retained tab is already a valid starting point. Reloading it can
        # restart a player, wipe a draft and add a pointless load wait.
        if page.url == url:
            page.bring_to_front()
            return
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=15000)
        except Exception:
            raise ActionError("Страница не загрузилась вовремя; проверь новое состояние") from None
        self.context = None

    def observe(self, image=False, *, query=None, offset=0, target_id=None, scope='elements'):
        tree = self.call("Page.getFrameTree")
        frame = tree["frameTree"]["frame"]
        world = self.call("Page.createIsolatedWorld", {"frameId": frame["id"], "worldName": "jarvis-agent"})
        self.context = world["executionContextId"]
        inspection = {'query':str(query or ''),'offset':offset,'id':target_id,'scope':scope} if query is not None or target_id else None
        script = ('globalThis.__jarvisInspection='+json.dumps(inspection,ensure_ascii=False)+';'+SCRIPT) if inspection else SCRIPT
        data = self.evaluate(script)
        if not isinstance(data, dict):
            raise ActionError("Страница ещё не доступна")
        if SENSITIVE.search(data["title"]):
            raise ActionError("Страница может содержать секреты")
        items=data.pop('items')
        value_hashes=[]
        for item in items:
            # Bind one-action approval to actual ordinary field contents. Values
            # stay local and are removed before model text, fingerprints or logs.
            value=item.pop('_value_state',None)
            if isinstance(value,str):
                value_hash=hashlib.sha256(value.encode('utf-8')).hexdigest()
                value_hashes.append((item['id'],value_hash))
                item['_value_hash']=value_hash
        permission_fingerprint=hashlib.sha256(json.dumps(value_hashes).encode()).hexdigest()
        targets = {item['id']:item for item in items}
        data["tabs"] = [{"id": "t" + p["id"], "title": p.get("title", "")[:120],
                         "url": p.get("url", "")[:500]} for p in self.pages()]
        # Do not publish values of inputs. Text comes from rendered body only.
        fingerprint = hashlib.sha256((json.dumps(data | {'elements':targets},ensure_ascii=False)+permission_fingerprint).encode()).hexdigest()
        # Playback clocks are evidence for the verifier, not layout changes that
        # should invalidate every input while a video is playing.
        media=self.evaluate("[...document.querySelectorAll('video,audio')].slice(0,4).map(e=>({kind:e.tagName.toLowerCase(),paused:e.paused,ended:e.ended,ready:e.readyState,time:Math.round(e.currentTime*10)/10,duration:Number.isFinite(e.duration)?Math.round(e.duration):null}))")
        catalog = targets
        text, targets = compact_observation(data, targets, media)
        jpeg = None
        if image:
            # Password fields aren't sent, including their screenshot pixels.
            # Rather than alter the user's page, refuse screenshots on login/payment forms.
            private = self.evaluate("!!document.querySelector('input[type=password],input[autocomplete=one-time-code],input[autocomplete=cc-number]')")
            if private:
                raise ActionError("Снимок формы с паролями/картой не отправляется модели")
            jpeg = base64.b64decode(self.call("Page.captureScreenshot", {"format": "jpeg", "quality": 70,
                                              "captureBeyondViewport": False})["data"])
        width, height = data["viewport"]
        return Observation(text, fingerprint, image=jpeg, targets=targets,
                           window=0, rect=(0, 0, width, height),
                           document=self.page_id+':'+data['document_id']+':'+data['url'],
                           permission_fingerprint=permission_fingerprint, catalog=catalog)

    @staticmethod
    def same_target(before,after,identifier):
        old=before.targets.get(identifier)
        new=(getattr(after, 'catalog', None) or after.targets).get(identifier)
        return bool(before.document==after.document and old and new and
            old.get('_value_hash')==new.get('_value_hash') and
            all(old.get(key)==new.get(key) for key in ('name','type','input_type','url','search','search_submit','result_rank','disabled')))

    def _observe_target(self, identifier):
        if getattr(self,'_selective_observation',False):
            return self.observe(target_id=identifier)
        return self.observe()

    def validate(self, name, args, obs):
        if name not in ("click", "type", "click_point", "scroll", "shortcut", "switch"):
            raise ActionError("В управляемом браузере это действие недоступно. Используй элементы страницы")
        if name == "switch" and args.get("id") not in {"t" + p["id"] for p in self.pages()}:
            raise ActionError("Вкладка отсутствует в управляемом браузере")
        if name in ("click", "type"):
            target = obs.targets.get(str(args.get("id", "")))
            if target is None or target.get("disabled"):
                candidates = [(key,value) for key,value in obs.targets.items()
                    if not value.get('disabled') and (name != 'type' or value.get('type') in ('input','textarea'))]
                choices = '; '.join(key+' '+str(value.get('name',''))[:80] for key,value in candidates[:8])
                raise ActionError("Элемент отсутствует или недоступен. Используй только id из текущих elements. "
                                  + ('Доступные цели: '+choices if choices else 'Подходящих полей сейчас не видно; сначала найди их на странице.'))
            if name == "type":
                if target["type"] not in ("input", "textarea") or target.get("input_type") in ("file", "password", "checkbox", "radio", "submit", "button", "hidden"):
                    raise ActionError("Этот элемент не является обычным текстовым полем")
                if not isinstance(args.get("text"), str) or len(args["text"]) > 4000:
                    raise ActionError("Недопустимый текст")
                if type(args.get("clear", False)) is not bool:
                    raise ActionError("clear должен быть boolean")
            if name == "click" and (args.get("button", "left") not in ("left", "right") or
                type(args.get("count", 1)) is not int or args.get("count", 1) not in (1, 2)):
                raise ActionError("Недопустимый клик")
        if name == "click_point" and (not obs.image or any(type(args.get(k)) not in (int, float) or
                 not 0 <= args[k] <= 1000 for k in ("x", "y"))):
            raise ActionError("Нужен снимок и координаты 0..1000")
        if name == "scroll" and (args.get("direction") not in ("up", "down", "left", "right") or
                type(args.get("count", 3)) is not int or not 1 <= args.get("count", 3) <= 8):
            raise ActionError("Некорректная прокрутка")
        if name == "shortcut" and args.get("keys", "").lower() not in (
                "enter", "escape", "tab", "shift+tab", "ctrl+a", "ctrl+f", "alt+left", "alt+right"):
            raise ActionError("Это сочетание не поддерживается в управляемом браузере")

    @classmethod
    def same_keyboard_target(cls, before, after):
        # Autocomplete and live page text may change without changing where
        # the key goes. Still reject navigation, lost focus and edited contents.
        focused = [key for key, value in before.targets.items() if value.get('focused')]
        current = [key for key, value in after.targets.items() if value.get('focused')]
        return bool(len(focused) == 1 and focused == current and
                    cls.same_target(before, after, focused[0]))

    def execute(self, name, args, obs):
        self.validate(name, args, obs)
        current = self._observe_target(str(args['id'])) if name in ('click','type') else self.observe()
        if name in ('click','type'):
            if not self.same_target(obs,current,str(args['id'])):
                # A transient overlay can hide the exact observed node from the
                # planner snapshot without replacing it. Let Playwright's trial
                # wait for it, then recheck full identity/value before dispatch.
                identifier=str(args['id'])
                transient_cover=(obs.document==current.document and identifier in obs.targets
                                 and identifier not in current.targets)
                if not transient_cover:
                    raise ActionError('Цель или документ изменились; выбираю действие заново')
        elif name == 'shortcut' and self.same_keyboard_target(obs, current):
            pass
        elif current.fingerprint != obs.fingerprint:
            raise ActionError("Страница изменилась; выбираю действие заново")
        if name == "switch":
            page = next(p for p in self.pages() if "t" + p["id"] == args["id"])
            self.ws.close()
            self.ws = self.connect(page["webSocketDebuggerUrl"], open_timeout=3, max_size=8_000_000)
            self.page_id = page["id"]
            self.context = None
            self.call("Page.enable")
            self.call("Runtime.enable")
            self.call("Page.bringToFront")
        elif name in ("click", "type"):
            node_id = json.dumps(str(args["id"]))
            marker = 'data-jarvis-action-' + secrets.token_hex(12)
            selector = self.evaluate(f"""(() => {{
                const e=__jarvisState.nodes.get({node_id});
                if(!e||!e.isConnected||e.disabled) return null;
                e.setAttribute({json.dumps(marker)},'');
                const selector='['+{json.dumps(marker)}+']';
                return document.querySelectorAll(selector).length===1 && document.querySelector(selector)===e ? selector : null;
            }})()""")
            if not selector:
                raise ActionError("Цель изменилась; нужно новое наблюдение")
            handle = None
            dispatched = False
            phase = 'actionability'
            click_ack = False
            try:
                handle = self.actions.target(self.page_id, selector)
                # Trial performs Playwright's visibility/stability/occlusion checks
                # without generating a click or replacing existing field contents.
                handle.click(trial=True, timeout=2500)
                if not self.same_target(obs,self._observe_target(str(args['id'])),str(args['id'])):
                    raise ActionError("Цель изменилась во время ожидания; выбираю действие заново")
                identity = self.evaluate(f"document.querySelectorAll({json.dumps(selector)}).length===1 && document.querySelector({json.dumps(selector)})===__jarvisState.nodes.get({node_id})")
                if not identity:
                    raise ActionError("Элемент заменён; нужно новое наблюдение")
                self.guard()  # Cancellation/correction can arrive during Playwright's wait.
                if name == "click":
                    # Keep local proof of delivery separate from proof that the
                    # requested task succeeded. Some pages time out after the
                    # native click has already reached the exact target.
                    self.evaluate(f"""(() => {{
                        const e=__jarvisState.nodes.get({node_id});
                        const ack={{seen:false,count:0}};
                        const listen=event=>{{if(event.isTrusted && (event.target===e || e.contains(event.target))
                            && event.button==={2 if args.get('button')=='right' else 0})
                            ack.seen=++ack.count>={args.get('count',1)};}};
                        __jarvisState.clickAck=ack;
                        ack.remove=()=>document.removeEventListener('{ 'contextmenu' if args.get('button')=='right' else 'click' }',listen,true);
                        document.addEventListener('{ 'contextmenu' if args.get('button')=='right' else 'click' }',listen,true);
                    }})()""")
                    click_ack = True
                    phase = 'click_dispatch'
                    dispatched = True
                    # Navigation is observed by the controller afterwards. A
                    # slow destination must not turn an already delivered click
                    # into an input failure (or trigger a duplicate click).
                    handle.click(button=args.get("button", "left"), click_count=args.get("count", 1), timeout=1200, no_wait_after=True)
                else:
                    phase = 'text_input'
                    if not handle.is_editable():
                        raise ActionError("Поле недоступно для ввода")
                    if args.get("clear", False):
                        dispatched = True
                        handle.fill(args["text"], timeout=1200)
                    else:
                        handle.focus()
                        if not self.evaluate(f"document.activeElement===__jarvisState.nodes.get({node_id})"):
                            raise ActionError("Фокус перешёл в другое поле; ввод отменён")
                        # Literal text, no key interpretation and no implicit Enter.
                        dispatched = True
                        self.actions.select_page(self.page_id).keyboard.insert_text(args["text"])
                    actual = handle.input_value(timeout=1200)
                    verified = actual == args["text"] if args.get("clear") else args["text"] in actual
                    if not verified:
                        raise ExecutionUncertain("Ввод не подтверждён. Задача остановлена; повторно текст не ввожу.")
                    return "Ввод проверен: True; отправка не выполнялась"
            except (ActionError, Stopped):
                raise
            except Exception as exc:
                from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
                if click_ack and isinstance(exc,PlaywrightTimeoutError):
                    try:
                        delivered = self.evaluate('globalThis.__jarvisState?.clickAck?.seen===true')
                    except Exception:
                        delivered = False
                    if delivered:
                        return 'Доставка клика целевому элементу подтверждена; проверь новое состояние. Повторять клик не нужно.'
                raw = str(exc).lower()
                detail = next((label for marker, label in (
                    ('intercepts pointer events', 'элемент перекрыт другим элементом'),
                    ('not visible', 'элемент не виден'),
                    ('not stable', 'элемент движется'),
                    ('not attached', 'элемент удалён со страницы'),
                    ('timeout', 'истекло время ожидания браузера'),
                ) if marker in raw), type(exc).__name__)
                # Playwright's actionability check explicitly reports that a
                # target never became stable before input dispatch. This is a
                # safe retry condition after a fresh observation; treating it
                # as an uncertain completed click unnecessarily kills tasks.
                definitely_not_dispatched = 'not stable' in raw
                if dispatched and not definitely_not_dispatched:
                    error=ExecutionUncertain("Результат действия не подтверждён: " + detail + ". Повторный ввод остановлен.")
                    error.phase=phase
                    raise error from None
                retry_hint = (" Подожди, пока цель перестанет двигаться, затем обнови наблюдение." if definitely_not_dispatched else " Выбери доступный элемент из нового наблюдения.")
                error=ActionError("Браузер не выполнил действие: " + detail + "." + retry_hint)
                error.phase=phase
                raise error from None
            finally:
                try:
                    self.evaluate(f"__jarvisState.nodes.get({node_id})?.removeAttribute({json.dumps(marker)})")
                except Exception:
                    pass  # The action may have navigated away from this document.
                if click_ack:
                    try:
                        self.evaluate('globalThis.__jarvisState?.clickAck?.remove()')
                    except Exception:
                        pass  # Navigation may have destroyed the old document.
                try:
                    if handle is not None:
                        handle.dispose()
                except Exception:
                    pass  # Cleanup must not turn a successful input into a retry.
        elif name == "click_point":
            self.guard()
            if time.monotonic() - obs.captured > 20:
                raise ActionError("Снимок устарел")
            self._click((obs.rect[2]-1)*args["x"]/1000, (obs.rect[3]-1)*args["y"]/1000)
        elif name == "scroll":
            self.guard()
            count, direction = args.get("count", 3), args["direction"]
            dx = (-1 if direction == "left" else 1)*count*100 if direction in ("left", "right") else 0
            dy = (-1 if direction == "up" else 1)*count*100 if direction in ("up", "down") else 0
            page = self.actions.select_page(self.page_id)
            page.mouse.move(obs.rect[2]/2, obs.rect[3]/2)
            self._input(lambda: page.mouse.wheel(dx,dy))
        elif name == "shortcut":
            self.guard()
            self.key(args["keys"])
        return "Действие страницы выполнено; проверь новое состояние"

    def pages(self):
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(f"http://127.0.0.1:{self.port}/json/list", timeout=2) as response:
            return [p for p in json.load(response) if p.get("type") == "page"]

    def _click(self, x, y, button="left", count=1):
        if button not in ("left", "right") or type(count) is not int or count not in (1, 2):
            raise ActionError("Недопустимый клик")
        page = self.actions.select_page(self.page_id)
        page.bring_to_front()
        self._input(lambda: page.mouse.click(x,y,button=button,click_count=count))

    def _input(self, operation):
        self.guard()
        try:
            operation()
        except Stopped:
            raise
        except Exception:
            raise ExecutionUncertain("Ввод в браузере мог выполниться, но ответ потерян. Остановился, чтобы не повторить действие.") from None

    def key(self, keys):
        parts = keys.lower().split("+")
        key = parts[-1]
        label = {"enter":"Enter","escape":"Escape","tab":"Tab",
                 "left":"ArrowLeft","right":"ArrowRight"}.get(key,key)
        chord = '+'.join([{'alt':'Alt','ctrl':'Control','shift':'Shift'}[part] for part in parts[:-1]]+[label])
        page = self.actions.select_page(self.page_id)
        self._input(lambda: page.keyboard.press(chord))

    def close(self):
        if self.actions is not None:
            try:
                self.actions.close()
            except Exception:
                pass
            self.actions = None
        if self.ws is not None:
            try:
                # A browser managed by the long-lived Jarvis process survives the
                # task worker. Closing this CDP socket only detaches the worker.
                if self.process is not None:
                    self.call("Browser.close")
            except Exception:
                pass
            self.ws.close()
        if self.process is not None:
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.terminate()
