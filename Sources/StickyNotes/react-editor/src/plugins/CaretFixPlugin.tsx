import { useLexicalComposerContext } from '@lexical/react/LexicalComposerContext';
import { useEffect } from 'react';

export default function CaretFixPlugin(): null {
    const [editor] = useLexicalComposerContext();

    useEffect(() => {
        let caret: HTMLDivElement | null = null;
        let style: HTMLStyleElement | null = null;

        const updateCaret = () => {
            const sel = window.getSelection();
            if (!sel || sel.rangeCount === 0 || !sel.isCollapsed) {
                if (caret) caret.style.display = 'none';
                return;
            }

            const range = sel.getRangeAt(0);

            // 检查选区是否在编辑器内
            const rootElement = editor.getRootElement();
            if (!rootElement || !rootElement.contains(range.commonAncestorContainer)) {
                if (caret) caret.style.display = 'none';
                return;
            }

            if (!caret) {
                caret = document.createElement('div');
                caret.id = 'custom-caret-pure';
                caret.style.cssText = 'position:fixed;width:1.5px;pointer-events:none;z-index:1;animation:caret-blink-pure 1s step-end infinite;';
                document.body.appendChild(caret);

                const animStyle = document.createElement('style');
                animStyle.textContent = `
          @keyframes caret-blink-pure { 0%, 100% { opacity: 1; } 50% { opacity: 0; } }
          /* 全局强制隐藏原生光标 - 覆盖所有可能的样式 */
          * { caret-color: transparent !important; }
          .ContentEditable__root, .editor-input, [contenteditable], [contenteditable] * { 
            caret-color: transparent !important; 
          }
          /* 自定义光标颜色：使用应用图标的主题色 #f2a941 */
          #custom-caret-pure { 
            background: #f2a941 !important; 
            box-shadow: 0 0 3px rgba(242, 169, 65, 0.5); /* 增加一点微光，更精致 */
          }
        `;
                document.head.appendChild(animStyle);
                style = animStyle;
            }

            let rects = range.getClientRects();
            let rect: DOMRect | null = rects.length > 0 ? rects[0] : null;

            // 如果没有精准矩形，尝试判断是否为空行
            if (!rect) {
                const container = range.startContainer;
                const element = container.nodeType === 3 ? container.parentElement : (container as HTMLElement);

                // 只有在段落内容完全为空（或只有一个 <br>）时才使用保底逻辑
                if (element && (element.textContent === '' || element.innerHTML === '<br>')) {
                    const elementRect = element.getBoundingClientRect();
                    const style = window.getComputedStyle(element);
                    const paddingLeft = parseFloat(style.paddingLeft) || 0;

                    rect = {
                        left: elementRect.left + paddingLeft,
                        top: elementRect.top,
                        height: parseFloat(style.lineHeight) || elementRect.height || 20,
                        width: 0,
                        bottom: elementRect.bottom,
                        right: elementRect.left + paddingLeft,
                        x: elementRect.left + paddingLeft,
                        y: elementRect.top,
                    } as DOMRect;
                }
            }

            // 如果依然拿不到位置，或者是过渡状态（宽高度均为0且不在行首），则隐藏
            if (!rect || (rect.left === 0 && rect.top === 0)) {
                if (caret) caret.style.display = 'none';
                return;
            }

            // 计算高度
            let fs = 15;
            try {
                const el = range.startContainer.nodeType === 3 ? range.startContainer.parentElement : (range.startContainer as HTMLElement);
                fs = parseFloat(window.getComputedStyle(el!).fontSize) || 15;
            } catch (e) { }

            const h = fs * 1.2;
            caret.style.display = 'block';
            caret.style.left = rect.left + 'px';
            caret.style.top = (rect.top + (rect.height - h) / 2) + 'px';
            caret.style.height = h + 'px';
        };

        const interval = setInterval(updateCaret, 40);

        return () => {
            clearInterval(interval);
            if (caret) caret.remove();
            if (style) style.remove();
        };
    }, [editor]);

    return null;
}
