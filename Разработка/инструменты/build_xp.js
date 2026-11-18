/* Сборка XP-версии Airfoil Studio:
   1) вытаскивает <script> из index.html
   2) подменяет blob.text() на FileReader-хелпер (в Firefox 52 нет Blob.text)
   3) транспилирует в ES5 под Firefox 52 (@babel/preset-env)
   4) вставляет обратно + adds compat-CSS (grid-gap) + включает шрифт Tahoma (на XP нет Segoe UI)
   5) добавляет полифилл flex-gap (в FF52 у flex нет gap — расставляем margin)
*/
const fs = require("fs");
const path = require("path");
const babel = require("@babel/core");

const SRC_HTML = process.argv[2];
const DST_HTML = process.argv[3];
let html = fs.readFileSync(SRC_HTML, "utf8");

// ищем ВНУТРЕННИЙ скрипт программы (не <script src="...">)
let s0 = -1;
{
  const reTag = /<script(\s[^>]*)?>/g;
  let m;
  while((m = reTag.exec(html)) !== null){
    if(!m[1] || m[1].indexOf("src=") < 0){ s0 = m.index + m[0].length; break; }
  }
}
const s1 = html.indexOf("</script>", s0);
if (s0 < 0 || s1 < 0 || s1 <= s0) throw new Error("script block not found");
let js = html.slice(s0, s1);

// --- пре-патчи исходника ---
const HELPER = `
/* Полифилл Blob.text() (Firefox 52 и старше его не имеют) */
function _blobText(b){
  return new Promise(function(res, rej){
    try{
      var r = new FileReader();
      r.onload = function(){ res(r.result); };
      r.onerror = function(){ rej(r.error || new Error("не удалось прочитать файл")); };
      r.readAsText(b);
    }catch(e){ rej(e); }
  });
}
`;
js = js.replace('"use strict";', '"use strict";\n' + HELPER);
js = js.replace(/await f\.text\(\)/g, "await _blobText(f)");

// --- транспиляция ---
const res = babel.transformSync(js, {
  filename: "app.js",
  sourceType: "script",
  compact: false,
  comments: true,
  presets: [[require("@babel/preset-env"), { targets: { firefox: "52" }, modules: false }]],
});
let es5 = res.code;

// canvas-шрифты: на XP нет Segoe UI — вместо него Arial
es5 = es5.replace(/(\d+)px Segoe UI\b/g, "$1px Arial");

// --- полифилл flex-gap для старых браузеров ---
const GAP_POLY =
`/* Совместимость с Firefox 52 (Windows XP): у flex-контейнеров нет свойства gap —
   вместо него расставляются отступы у дочерних блоков. Современные браузеры
   проходят проверку и работают нативно, полифилл отключается. */
(function(){
  var box = document.createElement("div");
  box.style.cssText = "display:flex;position:absolute;visibility:hidden;gap:7px";
  box.innerHTML = "<i style='width:10px;height:5px'></i><i style='width:10px;height:5px'></i>";
  document.body.appendChild(box);
  var nativeGap = (box.children[1].offsetLeft - box.children[0].offsetLeft) >= 16;
  document.body.removeChild(box);
  if(nativeGap) return;

  var RULES = [];
  function readGap(style){
    var v = "";
    try{ v = style.getPropertyValue("gap") || ""; }catch(e){}
    if(!v || v === "normal"){ try{ v = style.getPropertyValue("grid-gap") || ""; }catch(e){} }
    if(!v || v === "normal") return 0;
    var m = String(v).match(/^([\\d.]+)px/);
    return m ? parseFloat(m[1]) : 0;
  }
  function walk(rl){
    for(var i=0;i<rl.length;i++){
      var r = rl[i];
      if(r.type === 4 && r.cssRules) walk(r.cssRules);
      else if(r.style && r.selectorText){
        var g = readGap(r.style);
        if(g) RULES.push({ sel: r.selectorText, gap: g });
      }
    }
  }
  try{ for(var i=0;i<document.styleSheets.length;i++) walk(document.styleSheets[i].cssRules); }catch(e){}

  function gapOf(el){
    try{
      var st = el.getAttribute && el.getAttribute("style");
      if(st){ var m = st.match(/(?:^|;)\\s*gap\\s*:\\s*([\\d.]+)px/); if(m) return parseFloat(m[1]); }
      for(var i=RULES.length-1;i>=0;i--){ if(el.matches && el.matches(RULES[i].sel)) return RULES[i].gap; }
    }catch(e){}
    return 0;
  }
  function applyOne(el){
    if(!el || el.nodeType !== 1) return;
    var g = gapOf(el); if(!g) return;
    var cs = getComputedStyle(el);
    if(!cs.display || cs.display.indexOf("flex") === -1 || cs.display.indexOf("grid") !== -1) return;
    var col = /^column/.test(cs.flexDirection || "");
    var kids = el.children;
    for(var i=0;i<kids.length;i++){
      var k = kids[i];
      if(col) k.style.marginBottom = g + "px";
      else k.style.marginRight = (i < kids.length - 1) ? g + "px" : "";
    }
  }
  function applyAll(root){
    var els = root.querySelectorAll("*");
    for(var i=0;i<els.length;i++) applyOne(els[i]);
    applyOne(root);
  }
  applyAll(document.body);
  var mo = new MutationObserver(function(mrs){
    for(var i=0;i<mrs.length;i++){
      var added = mrs[i].addedNodes;
      for(var j=0;j<added.length;j++){
        var n = added[j];
        if(n.nodeType === 1){
          applyOne(n);
          if(n.parentElement) applyOne(n.parentElement);
        }
      }
    }
  });
  mo.observe(document.body, { childList: true, subtree: true });
})();
`;

// --- сборка HTML ---
// 1) базовый шрифт: на XP нет Segoe UI и system-ui
html = html.replace(
  'font:13px/1.45 "Segoe UI",system-ui,sans-serif',
  'font:13px/1.45 Tahoma,"Segoe UI",sans-serif'
);

// 2) compat-CSS перед закрытием основного стиля
const CSS_COMPAT =
`
/* --- совместимость со старым Firefox 52 (Windows XP) --- */
/* в FF52 у grid вместо gap работает старое имя grid-gap */
.grid2,.grid3,.grid4{ grid-gap:7px }
`;
{
  const i = html.indexOf("</style>");
  if(i < 0) throw new Error("</style> not found");
  html = html.slice(0, i) + CSS_COMPAT + html.slice(i);
}

// 3) главный скрипт: ES5 + полифилл gap после него
//    ищем внутренний <script> заново (CSS-вставка сдвинула индексы)
{
  const reTag2 = /<script(\s[^>]*)?>/g;
  let s0x = -1, s1x = -1, m2;
  while((m2 = reTag2.exec(html)) !== null){
    if(!m2[1] || m2[1].indexOf("src=") < 0){ s0x = m2.index; s1x = html.indexOf("</script>", m2.index); break; }
  }
  if(s0x < 0 || s1x <= s0x) throw new Error("inner script not found");
  var out0 = html.slice(0, s0x) + html.slice(s0x, s0x + m2[0].length) + "\n" + es5 + "\n" + GAP_POLY + "\n" + html.slice(s1x);
}

/* --- единый файл-база для обеих программ --- */
/* XP-версия лежит в подпапке: тянем общий airfoil-base.js из корня программы,
   при ошибке — запасную копию из своей папки. Загрузка асинхронная: когда файл
   готов, зовётся hook fileBaseLateLoad из программы — база добирается и
   подписи обновляются без участия юзера. */
const XP_LOADER =
"<script>\n" +
"/* Единый файл-база профилей обеих программ: общий файл в корне программы (../),\n" +
"   если рядом его нет — запасная копия из этой же папки. */\n" +
"(function(){\n" +
"  var tries = ['../airfoil-base.js', './airfoil-base.js'];\n" +
"  var done = false;\n" +
"  window.fileBaseReady = function(){\n" +
"    if(done) return;\n" +
"    done = true;\n" +
"    if(window.fileBaseLateLoad) window.fileBaseLateLoad();\n" +
"  };\n" +
"  function tryLoad(k){\n" +
"    if(k >= tries.length){ window.fileBaseReady(); return; }\n" +
"    var s = document.createElement('script');\n" +
"    s.src = tries[k] + (/^https?:$/i.test(location.protocol) ? '?t=' + Date.now() : '');\n" +
"    s.onload = function(){ window.fileBaseReady(); };\n" +
"    s.onerror = function(){ tryLoad(k + 1); };\n" +
"    (document.head || document.documentElement).appendChild(s);\n" +
"  }\n" +
"  tryLoad(0);\n" +
"})();\n" +
"</script>";
const iL = out0.indexOf('<script src="./airfoil-base.js"></script>');
let out;
if(iL >= 0) out = out0.slice(0, iL) + XP_LOADER + out0.slice(iL + '<script src="./airfoil-base.js"></script>'.length);
else { out = out0; console.log("WARN: loader tag not found"); }

fs.mkdirSync(path.dirname(DST_HTML), { recursive: true });
fs.writeFileSync(DST_HTML, out, "utf8");
console.log(JSON.stringify({
  srcScript: js.length,
  es5: es5.length,
  htmlIn: html.length,
  htmlOut: out.length,
  gridGapAdded: out.indexOf("grid-gap:7px") >= 0,
  blobTextPatched: es5.indexOf("_blobText") >= 0,
  fontPatched: out.indexOf('Tahoma,"Segoe UI"') >= 0
}));
