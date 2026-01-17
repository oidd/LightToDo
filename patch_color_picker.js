const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'Sources/StickyNotes/Resources/lexical-editor.html');
let content = fs.readFileSync(filePath, 'utf8');

// 1. 替换颜色数组 (15色 -> 8色)
const oldColors = '["#d0021b","#f5a623","#f8e71c","#8b572a","#7ed321","#417505","#bd10e0","#9013fe","#4a90e2","#50e3c2","#b8e986","#000000","#4a4a4a","#9b9b9b","#ffffff"]';
const newColors = '["","#989898","#e14a54","#ef8834","#f2c343","#58b05c","#5bb5f7","#d24be2"]';
if (content.includes(oldColors)) {
  content = content.replace(oldColors, newColors);
  console.log('✅ 颜色数组已替换');
} else {
  console.log('ℹ️ 颜色数组已经是新版本');
}

// 2. 替换 CSS 样式 (复杂布局 -> 2x4网格)
const oldCSS = '.color-picker-wrapper{padding:20px}.color-picker-basic-color{display:flex;flex-wrap:wrap;gap:10px;margin:0;padding:0}.color-picker-basic-color button{border:1px solid #ccc;border-radius:4px;height:16px;width:16px;cursor:pointer;list-style-type:none}.color-picker-basic-color button.active{box-shadow:0 0 2px 2px #0000004d}';
const newCSS = '.color-picker-wrapper{padding:12px}.color-picker-basic-color{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:0;padding:0}.color-picker-basic-color button{border:1px solid #ccc;border-radius:6px;height:28px;width:28px;cursor:pointer;list-style-type:none;transition:transform .1s ease,box-shadow .1s ease}.color-picker-basic-color button:hover{transform:scale(1.1)}.color-picker-basic-color button.active{box-shadow:0 0 0 2px #0000004d;transform:scale(1.1)}.color-picker-basic-color button.transparent{background-image:linear-gradient(45deg,#ccc 25%,transparent 25%),linear-gradient(-45deg,#ccc 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#ccc 75%),linear-gradient(-45deg,transparent 75%,#ccc 75%);background-size:8px 8px;background-position:0 0,0 4px,4px -4px,-4px 0px;background-color:#fff}';
if (content.includes(oldCSS)) {
  content = content.replace(oldCSS, newCSS);
  console.log('✅ CSS 样式已替换');
} else {
  console.log('ℹ️ CSS 样式已经是新版本');
}

// 3. 简化颜色选择器渲染（移除复杂的色轮、滑块等，只保留颜色按钮）
const oldRenderPart = 'T.jsxs("div",{className:"color-picker-wrapper",style:{width:go},ref:s,children:[T.jsx(t1,{label:"Hex",onChange:c,value:i}),T.jsx("div",{className:"color-picker-basic-color",children:n1.map(m=>T.jsx("button",{className:m===n.hex?" active":"",style:{backgroundColor:m},onClick:_=>y(_,m)},m))}),T.jsx(Xg,{className:"color-picker-saturation",style:{backgroundColor:`hsl(${n.hsv.h}, 100%, 50%)`},onChange:f,children:T.jsx("div",{className:"color-picker-saturation_cursor",style:{backgroundColor:n.hex,left:l.x,top:l.y}})}),T.jsx(Xg,{className:"color-picker-hue",onChange:d,children:T.jsx("div",{className:"color-picker-hue_cursor",style:{backgroundColor:`hsl(${n.hsv.h}, 100%, 50%)`,left:a.x}})}),T.jsx("div",{className:"color-picker-color",style:{backgroundColor:n.hex}})]})';
const newRenderPart = 'T.jsx("div",{className:"color-picker-wrapper",ref:s,children:T.jsx("div",{className:"color-picker-basic-color",children:n1.map((m,idx)=>T.jsx("button",{className:(m===n.hex?" active":"")+(idx===0?" transparent":""),style:idx===0?{}:{backgroundColor:m},onClick:_=>y(_,m)},m||"transparent"))})})';
if (content.includes(oldRenderPart)) {
  content = content.replace(oldRenderPart, newRenderPart);
  console.log('✅ 颜色选择器渲染已简化');
} else {
  console.log('ℹ️ 颜色选择器渲染已经是新版本');
}

// 4. 完全替换背景色组件为 Highlight 按钮
const bgColorRegex = /T\.jsx\(rm,\{disabled:!a,buttonClassName:"toolbar-item color-picker",buttonAriaLabel:"Formatting background color",buttonIconClassName:"icon bg-color",color:s\.bgColor,onChange:d=>c\(\{"background-color":d\},!0\),title:"Background color"\}\)/g;
const highlightButton = 'T.jsx("button",{disabled:!a,onClick:()=>{t.dispatchCommand(Tt,"highlight")},className:"toolbar-item spaced "+(s.isHighlight?"active":""),title:"Highlight",type:"button","aria-label":"Highlight text",children:T.jsx("i",{className:"format highlight"})})';

if (bgColorRegex.test(content)) {
  content = content.replace(bgColorRegex, highlightButton);
  console.log('✅ 背景色组件已完全替换为 Highlight 按钮');
} else {
  console.log('ℹ️ 背景色组件已经是新版本');
}

// 5. 去除 focus 蓝框
const focusRemoveCSS = '*:focus{outline:none!important;box-shadow:none!important}button:focus,select:focus,.dropdown:focus,.toolbar-item:focus{outline:none!important;box-shadow:none!important}';
if (!content.includes('*:focus{outline:none')) {
  content = content.replace('</style>', focusRemoveCSS + '</style>');
  console.log('✅ 已移除 focus 蓝框样式');
} else {
  console.log('ℹ️ focus 样式已移除');
}

// 6. 移除之前添加的任何脚本
content = content.replace(/<script>\s*\(function\(\)\s*\{[\s\S]*?<\/script>/g, '');

// 7. 在 useEffect 块中注入右键菜单功能
const setWindowActivePattern = 'window.setWindowActive=a=>{document.body.classList.toggle("inactive",!a)}';
const injectedFunctions = `window.setWindowActive=a=>{document.body.classList.toggle("inactive",!a)},window.setAlignment=a=>{e.dispatchCommand(wo,a)},window.setListType=a=>{a==="number"?e.dispatchCommand(v0,void 0):a==="bullet"&&e.dispatchCommand(_0,void 0)},window.clearFormatting=()=>{e.update(()=>{const s=$();if(O(s)||Df(s)){const l=s.getNodes();l.forEach(a=>{R(a)&&(a.setFormat(0),a.setStyle(""))})}})}`;

if (content.includes(setWindowActivePattern) && !content.includes('window.setAlignment=')) {
  content = content.replace(setWindowActivePattern, injectedFunctions);
  console.log('✅ 右键菜单功能已注入到 useEffect 块');
} else if (content.includes('window.setAlignment=')) {
  console.log('ℹ️ 右键菜单功能已存在');
} else {
  console.log('⚠️ 未找到注入点');
}

fs.writeFileSync(filePath, content);
console.log('\n🎉 Patch 应用完成!');
console.log('📁 File size:', (content.length / 1024).toFixed(2) + 'KB');
