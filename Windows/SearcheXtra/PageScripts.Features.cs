using System.Text.Json;

namespace SearcheXtra.Windows;

internal static partial class PageScripts
{
    public static string FillPassword(Login login) => "(()=>{if(window!==top||location.origin!==" + JsonSerializer.Serialize(login.Origin) + ")return;const p=document.querySelector('input[type=password]');if(!p||p.value)return;const u=document.querySelector('input[autocomplete=username],input[type=email],input[name*=user],input[type=text]');const set=(e,v)=>{if(!e)return;Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,v);e.dispatchEvent(new Event('input',{bubbles:true}));};set(u," + JsonSerializer.Serialize(login.Username) + ");set(p," + JsonSerializer.Serialize(login.Password) + ");})()";
    public static string Ads = "(()=>{const s=document.createElement('style');s.textContent=" + JsonSerializer.Serialize(".adsbygoogle,ins.adsbygoogle,[id^=\"google_ads_\"],[id^=\"div-gpt-ad\"],[id^=\"taboola-\"],#taboola-below-article,iframe[src*=\"doubleclick.net\"],iframe[src*=\"googlesyndication\"],iframe[src*=\"amazon-adsystem\"],.ad-slot,.ad-slot-container,.top-banner-ad-container,.ad-leaderboard,.ad-billboard,.ad-giga,.ad-mpu,.ad-mrec,.ad-unit,.adunit,.adslot,.dfp-ad,.gpt-ad,.w_ad{display:none!important}") + ";const put=()=>{(document.head||document.documentElement).appendChild(s)};if(document.documentElement)put();else document.addEventListener('DOMContentLoaded',put,{once:true});})();";
    public const string Features = """
        (()=>{
          if(window!==top)return;
          const send=(data)=>window.chrome.webview.postMessage(data);
          document.addEventListener('mouseover',e=>{const link=e.target.closest?.('a[href]');if(window.__searchPrefs?.links)send({type:'hover',url:link?.href||''});});
          document.addEventListener('mouseout',()=>{if(window.__searchPrefs?.links)send({type:'hover',url:''});});
          document.addEventListener('click',e=>{const link=e.target.closest?.('a[href]');if(link&&e.shiftKey&&!e.ctrlKey&&window.__searchPrefs?.peek){e.preventDefault();send({type:'preview',url:link.href});}},true);
          document.addEventListener('submit',e=>{if(!window.__searchPrefs?.passwords)return;const form=e.target;const p=form.querySelector('input[type=password]');if(!p?.value)return;const u=form.querySelector('input[autocomplete=username],input[type=email],input[name*=user],input[type=text]');send({type:'password',username:u?.value||'',password:p.value});},true);
          document.addEventListener('play',e=>{if(window.__searchPrefs?.wait&&e.target instanceof HTMLMediaElement&&!e.target.__searchManual)e.target.pause();},true);
          document.addEventListener('pointerdown',e=>{const video=e.target.closest?.('video');if(video)video.__searchManual=true;},true);
          const applyText=()=>document.querySelectorAll('input,textarea,[contenteditable=true]').forEach(e=>{e.spellcheck=!!window.__searchPrefs?.autocorrect;e.setAttribute('autocorrect',window.__searchPrefs?.autocorrect?'on':'off');});
          document.addEventListener('DOMContentLoaded',applyText,{once:true});document.addEventListener('focusin',applyText);
          let lastRead=0;document.addEventListener('scroll',()=>{if(!window.__searchPrefs?.reading||performance.now()-lastRead<100)return;lastRead=performance.now();send({type:'reading',value:Math.min(100,100*(scrollY+innerHeight)/Math.max(innerHeight,document.documentElement.scrollHeight))});},{passive:true});
          document.addEventListener('wheel',e=>{if(window.__searchFloating&&window.__searchPrefs?.flicks&&(Math.abs(e.deltaX)>20||Math.abs(e.deltaY)>40))send({type:'flick',x:e.deltaX,y:e.deltaY});},{passive:true});
          let scroll=null;
          const stopScroll=()=>{if(scroll){cancelAnimationFrame(scroll.frame);scroll=null;}};
          document.addEventListener('mousedown',e=>{if(e.button!==1||!window.__searchPrefs?.scroll||e.target.closest?.('a[href]'))return;e.preventDefault();if(scroll){stopScroll();return;}scroll={x:e.clientX,y:e.clientY,dx:0,dy:0};const tick=()=>{if(!scroll)return;if(!window.__searchPrefs?.scroll){stopScroll();return;}window.scrollBy(scroll.dx/8,scroll.dy/8);scroll.frame=requestAnimationFrame(tick);};tick();});
          document.addEventListener('mousemove',e=>{if(scroll){scroll.dx=e.clientX-scroll.x;scroll.dy=e.clientY-scroll.y;}});
          document.addEventListener('keydown',e=>{if(e.key==='Escape')stopScroll();});
          addEventListener('pagehide',stopScroll);
          if(navigator.credentials){const get=navigator.credentials.get.bind(navigator.credentials);const create=navigator.credentials.create.bind(navigator.credentials);navigator.credentials.get=o=>o?.publicKey&&window.__searchPrefs?.passkeys===false?Promise.reject(new DOMException('Passkeys disabled','NotAllowedError')):get(o);navigator.credentials.create=o=>o?.publicKey&&window.__searchPrefs?.passkeys===false?Promise.reject(new DOMException('Passkeys disabled','NotAllowedError')):create(o);}
        })();
        """;
}
