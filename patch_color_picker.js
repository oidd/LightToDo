const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'Sources/StickyNotes/Resources/lexical-editor.html');
let content = fs.readFileSync(filePath, 'utf8');

console.log('--- Starting Patch Process ---');

// 1. 替换颜色数组 (15色 -> 8色)
const oldColors = '["#d0021b","#f5a623","#f8e71c","#8b572a","#7ed321","#417505","#bd10e0","#9013fe","#4a90e2","#50e3c2","#b8e986","#000000","#4a4a4a","#9b9b9b","#ffffff"]';
const newColors = '["","#989898","#e14a54","#ef8834","#f2c343","#58b05c","#5bb5f7","#d24be2"]';

if (content.includes(oldColors)) {
  content = content.replace(oldColors, newColors);
  content = content.replace(oldColors, newColors);
  console.log('✅ 颜色数组已替换');
}

// 2. 替换 CSS 样式
const oldCSSStart = '.color-picker-wrapper{padding:20px}';
const newCSS = '.color-picker-wrapper{padding:12px}.color-picker-basic-color{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:0;padding:0}.color-picker-basic-color button{border:1px solid #ccc;border-radius:6px;height:28px;width:28px;cursor:pointer;list-style-type:none;transition:transform .1s ease,box-shadow .1s ease}.color-picker-basic-color button:hover{transform:scale(1.1)}.color-picker-basic-color button.active{box-shadow:0 0 0 2px #0000004d;transform:scale(1.1)}.color-picker-basic-color button.transparent{background-image:linear-gradient(45deg,#ccc 25%,transparent 25%),linear-gradient(-45deg,#ccc 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#ccc 75%),linear-gradient(-45deg,transparent 75%,#ccc 75%);background-size:8px 8px;background-position:0 0,0 4px,4px -4px,-4px 0px;background-color:#fff}';

if (content.includes(oldCSSStart)) {
  content = content.replace('</style>', newCSS + '</style>');
  console.log('✅ 新 CSS 样式已追加');
}

// 3. 简化颜色选择器渲染
const oldRenderPart = 'T.jsxs("div",{className:"color-picker-wrapper",style:{width:go},ref:s,children:[T.jsx(t1,{label:"Hex",onChange:c,value:i}),T.jsx("div",{className:"color-picker-basic-color",children:n1.map(m=>T.jsx("button",{className:m===n.hex?" active":"",style:{backgroundColor:m},onClick:_=>y(_,m)},m))}),T.jsx(Xg,{className:"color-picker-saturation",style:{backgroundColor:`hsl(${n.hsv.h}, 100%, 50%)`},onChange:f,children:T.jsx("div",{className:"color-picker-saturation_cursor",style:{backgroundColor:n.hex,left:l.x,top:l.y}})}),T.jsx(Xg,{className:"color-picker-hue",onChange:d,children:T.jsx("div",{className:"color-picker-hue_cursor",style:{backgroundColor:`hsl(${n.hsv.h}, 100%, 50%)`,left:a.x}})}),T.jsx("div",{className:"color-picker-color",style:{backgroundColor:n.hex}})]})';

const newRenderPart = 'T.jsx("div",{className:"color-picker-wrapper",ref:s,children:T.jsx("div",{className:"color-picker-basic-color",children:n1.map((m,idx)=>T.jsx("button",{className:(m===n.hex?" active":"")+(idx===0?" transparent":""),style:idx===0?{}:{backgroundColor:m},onClick:_=>y(_,m)},m||"transparent"))})})';

if (content.indexOf(oldRenderPart) !== -1) {
  content = content.replace(oldRenderPart, newRenderPart);
  console.log('✅ 颜色选择器渲染已简化');
}

// 4. 替换背景色为高亮
const oldBgBtn = 'T.jsx(rm,{disabled:!a,buttonClassName:"toolbar-item color-picker",buttonAriaLabel:"Formatting background color",buttonIconClassName:"icon bg-color",color:s.bgColor,onChange:d=>c({"background-color":d},!0),title:"Background color"})';
const newHighlightBtn = 'T.jsx("button",{disabled:!a,onClick:()=>{t.dispatchCommand(Tt,"highlight")},className:"toolbar-item spaced "+(s.isHighlight?"active":""),title:"Highlight",type:"button","aria-label":"Highlight text",children:T.jsx("i",{className:"format highlight"})})';

if (content.includes(oldBgBtn)) {
  content = content.replace(oldBgBtn, newHighlightBtn);
  console.log('✅ 背景色组件已完全替换为 Highlight 按钮');
}

// 5. 移除 focus 蓝框
const focusRemoveCSS = '*:focus{outline:none!important;box-shadow:none!important}button:focus,select:focus,.dropdown:focus,.toolbar-item:focus{outline:none!important;box-shadow:none!important}';
if (!content.includes('*:focus{outline:none')) {
  content = content.replace('</style>', focusRemoveCSS + '</style>');
  console.log('✅ 已移除 focus 蓝框样式');
}

// 6. 暴露内部函数 (Safe Assignment)
let exposedCount = 0;
if (!content.includes('am=window.am')) {
  if (content.includes('am=(e,t,n)=>{')) { content = content.replace(/am=\(e,t,n\)=>{/g, 'am=window.am=(e,t,n)=>{'); exposedCount++; }
}
if (!content.includes('Va=window.Va')) {
  if (content.includes('Va=e=>{')) { content = content.replace(/Va=e=>{/g, 'Va=window.Va=e=>{'); exposedCount++; }
}
if (!content.includes('g1=window.g1')) {
  if (content.includes('g1=(e,t)=>{')) { content = content.replace(/g1=\(e,t\)=>{/g, 'g1=window.g1=(e,t)=>{'); exposedCount++; }
}
if (!content.includes('m1=window.m1')) {
  if (content.includes('m1=(e,t)=>{')) { content = content.replace(/m1=\(e,t\)=>{/g, 'm1=window.m1=(e,t)=>{'); exposedCount++; }
}
console.log(`✅ 已暴露内部 Formatting 函数: ${exposedCount}/4 (或已存在)`);


// 7. 注入功能 - 使用 event.code + event.key，✅去除所有注释✅
const setWindowActivePattern = 'window.setWindowActive=a=>{document.body.classList.toggle("inactive",!a)}';

const injectedFunctions = `
window.setWindowActive=a=>{document.body.classList.toggle("inactive",!a)},
window.setAlignment=a=>{e.dispatchCommand(wo,a)},
window.setListType=a=>{a==="number"?e.dispatchCommand(v0,void 0):a==="bullet"&&e.dispatchCommand(_0,void 0)},
window.clearFormatting=()=>{e.update(()=>{const s=$();if(O(s)||Df(s)){const l=s.getNodes();l.forEach(a=>{R(a)&&(a.setFormat(0),a.setStyle(""))})}})},
(!window._shortcutHandler && (
  window._shortcutHandler = (event) => {
    const { metaKey, ctrlKey, shiftKey, altKey, code, key } = event;
    const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
    const cmd = isMac ? metaKey : ctrlKey;
    if (!cmd && !ctrlKey) return;
    
    if (altKey) {
      if (code === 'Digit1') { event.preventDefault(); window.am && window.am(e, null, "h1"); return; }
      if (code === 'Digit2') { event.preventDefault(); window.am && window.am(e, null, "h2"); return; }
      if (code === 'Digit0') { event.preventDefault(); window.Va && window.Va(e); return; }
      if (code === 'KeyC') { event.preventDefault(); window.m1 && window.m1(e, null); return; }
    }

    if (code === 'BracketLeft' && !shiftKey) { event.preventDefault(); e.dispatchCommand(Kc, void 0); return; }
    if (code === 'BracketRight' && !shiftKey) { event.preventDefault(); e.dispatchCommand(V_, void 0); return; }
    
    if (cmd && shiftKey) {
       if (code === 'Digit7') { event.preventDefault(); e.dispatchCommand(v0, void 0); return; }
       if (code === 'Digit8') { event.preventDefault(); e.dispatchCommand(_0, void 0); return; }
       if (code === 'Digit9') { event.preventDefault(); e.dispatchCommand(m0, void 0); return; }
    }
    
    if ((ctrlKey || cmd) && shiftKey && code === 'KeyQ') {
        event.preventDefault(); window.g1 && window.g1(e, null); return;
    }
    
    if (cmd && shiftKey) {
        if (code === 'KeyL') { event.preventDefault(); e.dispatchCommand(wo, 'left'); return; }
        if (code === 'KeyE') { event.preventDefault(); e.dispatchCommand(wo, 'center'); return; }
        if (code === 'KeyR') { event.preventDefault(); e.dispatchCommand(wo, 'right'); return; }
        if (code === 'KeyJ') { event.preventDefault(); e.dispatchCommand(wo, 'justify'); return; }
    }
  },
  window.addEventListener('keydown', window._shortcutHandler, true)
))
`;

// 移除换行和首尾空格
const injectedOneLine = injectedFunctions.replace(/\n\s*/g, '');

if (content.includes(setWindowActivePattern) && !content.includes('window.setAlignment=')) {
  content = content.replace(setWindowActivePattern, injectedOneLine);
  console.log('✅ 右键菜单及快捷键功能已注入 (Fixed ReferenceError and Comments)');
} else {
  // 强制注入检测
  if (content.includes('window.setAlignment=')) {
    console.log('ℹ️ 注入代码已存在，但可能需要更新。由于每次从 bundled 复制，理论上是干净的。如果是干净的但没注入，检查 Pattern。');
    // 如果这里打印了，说明 bundled 文件可能就不干净。
  } else {
    console.log('⚠️ 警告：无法找到注入锚点 window.setWindowActive');
  }
}

fs.writeFileSync(filePath, content);
console.log('\n🎉 Patch Apply Complete!');
