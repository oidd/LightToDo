#!/usr/bin/env node

/**
 * post-build-inject.cjs
 * 
 * 构建后自动注入脚本
 * 在 react-editor 构建完成后，自动将自定义的CSS样式、翻译逻辑、新建笔记按钮等注入到生成的 HTML 中
 * 
 * 使用方法: node post-build-inject.cjs
 */

const fs = require('fs');
const path = require('path');

const DIST_HTML = path.join(__dirname, 'dist', 'index.html');
const OUTPUT_HTML = path.join(__dirname, '..', 'Resources', 'lexical-editor.html');

// ============================================
// 自定义 CSS 样式 (您的原始主题和布局 - 完整版)
// ============================================
const CUSTOM_STYLES = `
/* =========================================
   VARIABLES & THEME CONFIGURATION
   ========================================= */
:root {
    --app-bg: #ffffff;
    --module-bg: #ffffff;
    --text-color: #1a1a1a;
    --border-color: #f0f0f0;
    --active-bg: #f5f5f5;
    --shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
    --gap-size: 12px;
}

@media (prefers-color-scheme: dark) {
    :root {
        --app-bg: #1c1c1e;
        --module-bg: #2c2c2e;
        --text-color: #ffffff;
        --border-color: rgba(255, 255, 255, 0.1);
        --active-bg: #404040;
        --shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
    }

    .icon,
    button.toolbar-item i,
    .editor-dev-button:after,
    .test-recorder-button:after,
    .new-note-btn svg {
        filter: invert(1);
    }

    button.toolbar-item.active i {
        filter: invert(1);
    }

    .new-note-btn {
        border: 1px solid rgba(255, 255, 255, 0.1) !important;
    }
}

/* =========================================
   INACTIVE STATE (IDLE)
   ========================================= */
body.inactive .toolbar,
body.inactive .new-note-btn {
    box-shadow: none !important;
    background-color: #f7f7f7 !important;
    border: none !important;
}

@media (prefers-color-scheme: dark) {

    body.inactive .toolbar,
    body.inactive .new-note-btn {
        background-color: #252527 !important;
        border: none !important;
    }
}

/* =========================================
   LAYOUT ARCHITECTURE - RIGID RESET
   ========================================= */
html,
body {
    margin: 0 !important;
    padding: 0 !important;
    width: 100% !important;
    height: 100% !important;
    overflow: hidden !important;
    background-color: var(--app-bg) !important;
}

#root {
    margin: 0 !important;
    /* BASE 20px PADDING - CORE ANCHOR */
    padding: 4px 20px 24px 20px !important;
    width: 100% !important;
    height: 100% !important;
    display: flex !important;
    flex-direction: column !important;
    box-sizing: border-box !important;
}

.editor-shell {
    margin: 0 !important;
    padding: 0 !important;
    width: 100% !important;
    height: 100% !important; /* Force height */
    display: flex !important;
    flex-direction: column !important;
    flex: 1 !important;
    align-items: flex-start !important;
    box-sizing: border-box !important;
    min-height: 0 !important;
}

/* =========================================
   TOOLBAR WRAPPER - PHYSICS ALIGNMENT
   ========================================= */
.toolbar-wrapper {
    display: flex !important;
    align-items: center !important;
    gap: 16px !important;

    /* FIX: LOCALIZED WIDTH ONLY - ENSURES NO TEXT SHIFT */
    width: fit-content !important;

    margin-top: 0 !important;
    margin-bottom: 8px !important;
    padding: 10px !important;

    /* ALIGNMENT: Landing at 20px exactly on the red line */
    margin-left: -10px !important;
    margin-right: auto !important;

    box-sizing: border-box !important;
}

.new-note-btn {
    width: 44px !important;
    height: 44px !important;
    border-radius: 50% !important;
    background-color: var(--module-bg) !important;
    border: none !important;
    box-shadow: var(--shadow) !important;
    display: flex !important;
    align-items: center !important;
    justify-content: center !important;
    cursor: pointer !important;
    flex-shrink: 0 !important;
}

.new-note-btn:hover {
    background-color: var(--active-bg) !important;
    transform: scale(1.05) !important;
}

.new-note-btn:active {
    transform: scale(0.95) !important;
}

/* =========================================
   TOOLBAR - FIXED SIZE (NON-DEFORMABLE)
   ========================================= */
.toolbar {
    background-color: var(--module-bg) !important;
    border: none !important;
    border-radius: 999px !important;
    margin: 0 !important;
    box-shadow: var(--shadow) !important;
    z-index: 100 !important;

    /* PREVENTS DEFORMATION */
    min-width: max-content !important;
    flex-shrink: 0 !important;

    display: flex !important;
    padding: 4px 16px !important;
    height: auto !important;
    white-space: nowrap !important;
    overflow: visible !important;
}

@media (prefers-color-scheme: dark) {
    .toolbar:not(.inactive *) {
        border: 1px solid rgba(255, 255, 255, 0.1) !important;
    }
}

/* =========================================
   EDITOR CONTENT - PRECISION 44px PADDING
   ========================================= */
.editor-shell .editor-container {
    background: transparent !important;
    border: none !important;
    box-shadow: none !important;
    display: flex !important;
    flex-direction: column !important;
    flex: 1 !important;
    width: 100% !important;
    height: 100% !important; /* Force height */
    margin: 0 !important;
    padding: 0 !important;
    box-sizing: border-box !important;
    overflow: hidden !important;
    min-height: 0 !important;
}

.editor-scroller {
    background-color: transparent !important;
    border: none !important;
    box-shadow: none !important;
    margin: 0 !important;

    /* Zero padding for strict alignment - relies on #root padding */
    padding: 0 !important;

    flex: 1 !important;
    display: flex !important;
    flex-direction: column !important;
    width: 100% !important;
    height: 100% !important; /* Force height */
    box-sizing: border-box !important;
    outline: none !important;
    
    /* ENABLE SCROLLING */
    overflow-y: auto !important;
    overflow-x: hidden !important;
    min-height: 0 !important;
}

.editor-input,
.ContentEditable__root,
[contenteditable] {
    padding: 0 !important;
    margin: 0 !important;
    width: 100% !important;
    box-sizing: border-box !important;
    outline: none !important;
}

.editor {
    flex: 1 !important;
    outline: none !important;
    width: 100% !important;
}

@media (prefers-color-scheme: dark) {

    .ContentEditable__root,
    .ContentEditable__root *,
    .ContentEditable__root span[style],
    [contenteditable] * {
        color: #ffffff !important;
        caret-color: #ffffff !important;
    }
}

/* =========================================
   FEATURE TOGGLES - HIDE UNWANTED BUTTONS
   ========================================= */
.editor-placeholder {
    display: none !important;
}

button.toolbar-item:has(i.undo),
button.toolbar-item:has(i.redo) {
    display: none !important;
}

.font-size-input,
button.font-decrement,
button.font-increment,
button.toolbar-item:has(i.minus-icon),
button.toolbar-item:has(i.plus-icon) {
    display: none !important;
}

button.toolbar-item.font-family,
.font-family {
    display: none !important;
}

button.toolbar-item:has(i.code),
button.toolbar-item:has(i.link) {
    display: none !important;
}

.toolbar .divider {
    display: none !important;
}

.ContentEditable__root:focus,
[contenteditable]:focus {
    outline: none !important;
}

/* =========================================
   COLOR PICKER STYLES
   ========================================= */
.color-picker-wrapper{padding:12px}
.color-picker-basic-color{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:0;padding:0}
.color-picker-basic-color button{border:1px solid #ccc;border-radius:6px;height:28px;width:28px;cursor:pointer;list-style-type:none;transition:transform .1s ease,box-shadow .1s ease}
.color-picker-basic-color button:hover{transform:scale(1.1)}
.color-picker-basic-color button.active{box-shadow:0 0 0 2px #0000004d;transform:scale(1.1)}
.color-picker-basic-color button.transparent{background-image:linear-gradient(45deg,#ccc 25%,transparent 25%),linear-gradient(-45deg,#ccc 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#ccc 75%),linear-gradient(-45deg,transparent 75%,#ccc 75%);background-size:8px 8px;background-position:0 0,0 4px,4px -4px,-4px 0px;background-color:#fff}

/* =========================================
   FOCUS REMOVAL
   ========================================= */
*:focus{outline:none!important;box-shadow:none!important}
button:focus,select:focus,.dropdown:focus,.toolbar-item:focus{outline:none!important;box-shadow:none!important}
`;

// ============================================
// 自定义脚本 (翻译、新建按钮注入、窗口状态)
// ============================================
const CUSTOM_SCRIPTS = `
<script>
    (function () {
        // ==========================================
        // TRANSLATION LOGIC (Preserved)
        // ==========================================
        const TRANSLATIONS = {
            "Normal": "正文", "Heading 1": "标题 1", "Heading 2": "标题 2", "Heading 3": "标题 3",
            "Check List": "待办列表", "Bullet List": "无序列表", "Numbered List": "有序列表",
            "Quote": "引用", "Code Block": "代码块",
            "Left Align": "左对齐", "Center Align": "居中对齐", "Right Align": "右对齐", "Justify Align": "两端对齐",
            "Outdent": "减少缩进", "Indent": "增加缩进",
            "Bold": "加粗", "Italic": "斜体", "Underline": "下划线", "Strikethrough": "删除线",
            "Subscript": "下标", "Superscript": "上标",
            "Insert Link": "插入链接", "Insert Image": "插入图片",
            "Enter some text...": "输入内容...",
            "Enter text...": "输入内容...",
            "Start typing...": "输入内容..."
        };

        function walk(node) {
            if (node.nodeType === 3) {
                const text = node.nodeValue.trim();
                if (text && TRANSLATIONS[text]) node.nodeValue = node.nodeValue.replace(text, TRANSLATIONS[text]);
            } else if (node.nodeType === 1) {
                if (node.placeholder && TRANSLATIONS[node.placeholder]) node.placeholder = TRANSLATIONS[node.placeholder];
                Array.from(node.childNodes).forEach(walk);
                if (node.title && TRANSLATIONS[node.title]) node.title = TRANSLATIONS[node.title];
                if (node.getAttribute('aria-label') && TRANSLATIONS[node.getAttribute('aria-label')]) {
                    node.setAttribute('aria-label', TRANSLATIONS[node.getAttribute('aria-label')]);
                }
            }
        }

        const observer = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                for (const node of mutation.addedNodes) walk(node);
                if (mutation.type === 'attributes' && (mutation.attributeName === 'title' || mutation.attributeName === 'aria-label')) {
                    const node = mutation.target;
                    const val = node.getAttribute(mutation.attributeName);
                    if (val && TRANSLATIONS[val]) node.setAttribute(mutation.attributeName, TRANSLATIONS[val]);
                }
            }
        });

        observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['title', 'aria-label'] });
        walk(document.body);

        // ==========================================
        // NEW NOTE BUTTON INJECTION & LAYOUT WRAPPER
        // ==========================================
        function injectNewNoteButton() {
            const toolbar = document.querySelector('.toolbar');
            if (!toolbar) return;

            // Avoid double injection
            if (document.querySelector('.toolbar-wrapper')) return;

            // Create Wrapper
            const wrapper = document.createElement('div');
            wrapper.className = 'toolbar-wrapper';

            // Insert Wrapper before Toolbar
            toolbar.parentNode.insertBefore(wrapper, toolbar);

            // Create New Note Button
            const btn = document.createElement('button');
            btn.className = 'new-note-btn';
            btn.innerHTML = \`<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M11 4H4C3.46957 4 2.96086 4.21071 2.58579 4.58579C2.21071 4.96086 2 5.46957 2 6V20C2 20.5304 2.21071 21.0391 2.58579 21.4142C2.96086 21.7893 3.46957 22 4 22H18C18.5304 22 19.0391 21.7893 19.4142 21.4142C19.7893 21.0391 20 20.5304 20 20V13" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M18.5 2.50001C18.8978 2.10219 19.4374 1.87869 20 1.87869C20.5626 1.87869 21.1022 2.10219 21.5 2.50001C21.8978 2.89784 22.1213 3.4374 22.1213 4.00001C22.1213 4.56262 21.8978 5.10219 21.5 5.50001L12 15L8 16L9 12L18.5 2.50001Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>\`;
            btn.onclick = function () {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editor) {
                    window.webkit.messageHandlers.editor.postMessage({ type: 'newNote' });
                }
            };

            // Add Button and Toolbar to Wrapper
            wrapper.appendChild(btn);
            wrapper.appendChild(toolbar);
        }

        // Try to inject immediately and then observe for toolbar appearance
        document.addEventListener('DOMContentLoaded', () => {
            injectNewNoteButton();

            // Fallback observer in case toolbar loads late (React)
            const layoutObserver = new MutationObserver((mutations) => {
                if (document.querySelector('.toolbar') && !document.querySelector('.toolbar-wrapper')) {
                    injectNewNoteButton();
                }
            });
            layoutObserver.observe(document.body, { childList: true, subtree: true });

            // IDLE STATE DETECTION
            window.addEventListener('focus', () => {
                document.body.classList.remove('inactive');
            });
            window.addEventListener('blur', () => {
                document.body.classList.add('inactive');
            });

            // Set initial state
            if (!document.hasFocus()) {
                document.body.classList.add('inactive');
            }
        });

    })();
</script>
`;

// ============================================
// 配色器脚本
// ============================================
const COLOR_PICKER_SCRIPT = `
    <script>
        // 颜色选择器脚本 (从 patch_color_picker.js 提取)
        window.onerror = function (message, source, lineno, colno, error) {
            console.error(message);
            if (window.webkit?.messageHandlers?.editor) {
                window.webkit.messageHandlers.editor.postMessage({ type: 'error', message: message });
            }
        };
    </script>
`;

// ============================================
// 主逻辑
// ============================================
function main() {
    console.log('📦 开始构建后注入...');

    // 1. 读取构建产物
    if (!fs.existsSync(DIST_HTML)) {
        console.error('❌ 错误: 找不到构建产物 dist/index.html');
        console.error('   请先运行 npm run build');
        process.exit(1);
    }

    let html = fs.readFileSync(DIST_HTML, 'utf-8');
    console.log('✅ 读取构建产物成功');

    // 2. 注入自定义 CSS 到 <head>
    // 找到 </head> 标签，在其前面插入自定义样式
    const headEndIndex = html.indexOf('</head>');
    if (headEndIndex === -1) {
        // 如果是 single-file 模式，样式可能在 <style> 标签中
        // 找到第一个 <style> 标签并在其开头添加
        const styleStartIndex = html.indexOf('<style>');
        if (styleStartIndex !== -1) {
            html = html.slice(0, styleStartIndex + 7) + CUSTOM_STYLES + html.slice(styleStartIndex + 7);
            console.log('✅ 注入自定义 CSS (style 标签内)');
        } else {
            console.warn('⚠️ 警告: 无法找到 </head> 或 <style> 标签');
        }
    } else {
        html = html.slice(0, headEndIndex) + '<style>' + CUSTOM_STYLES + '</style>' + html.slice(headEndIndex);
        console.log('✅ 注入自定义 CSS (head 标签内)');
    }

    // 3. 注入配色器脚本
    const bodyStartIndex = html.indexOf('<body>');
    if (bodyStartIndex !== -1) {
        html = html.slice(0, bodyStartIndex + 6) + COLOR_PICKER_SCRIPT + html.slice(bodyStartIndex + 6);
        console.log('✅ 注入配色器脚本');
    }

    // 4. 注入自定义脚本到 </body> 前
    const bodyEndIndex = html.lastIndexOf('</body>');
    if (bodyEndIndex !== -1) {
        html = html.slice(0, bodyEndIndex) + CUSTOM_SCRIPTS + html.slice(bodyEndIndex);
        console.log('✅ 注入自定义脚本 (翻译、新建按钮)');
    } else {
        // 如果没有 </body>，添加到文件末尾
        html += CUSTOM_SCRIPTS;
        console.log('✅ 注入自定义脚本 (文件末尾)');
    }

    // 5. 写入最终文件
    fs.writeFileSync(OUTPUT_HTML, html);
    console.log('✅ 写入完成: ' + OUTPUT_HTML);
    console.log('🎉 构建后注入完成!');
}

main();
