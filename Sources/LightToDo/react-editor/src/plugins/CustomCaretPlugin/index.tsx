/**
 * Custom Caret Plugin
 * 
 * 解决 contenteditable 中光标高度跟随行高变化的问题。
 * 当行内有图片或 line-height > 1 时，浏览器默认光标会变得很高。
 * 此插件使用自定义光标来替代系统光标，保持固定高度。
 */

import { useLexicalComposerContext } from '@lexical/react/LexicalComposerContext';
import { useEffect, useRef, useCallback } from 'react';

import './styles.css';

export default function CustomCaretPlugin(): null {
    const [editor] = useLexicalComposerContext();
    const caretRef = useRef<HTMLDivElement | null>(null);
    const animationFrameRef = useRef<number | null>(null);

    const updateCaretPosition = useCallback(() => {
        const rootElement = editor.getRootElement();
        if (!rootElement) return;

        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) {
            // 没有选区，隐藏光标
            if (caretRef.current) {
                caretRef.current.style.display = 'none';
            }
            return;
        }

        // 只在光标闪烁时显示自定义光标（不是选区）
        if (!selection.isCollapsed) {
            if (caretRef.current) {
                caretRef.current.style.display = 'none';
            }
            return;
        }

        // 检查选区是否在编辑器内
        const anchorNode = selection.anchorNode;
        if (!anchorNode || !rootElement.contains(anchorNode)) {
            if (caretRef.current) {
                caretRef.current.style.display = 'none';
            }
            return;
        }

        // 创建光标元素（如果不存在）
        if (!caretRef.current) {
            const caret = document.createElement('div');
            caret.className = 'custom-caret';
            rootElement.parentElement?.appendChild(caret);
            caretRef.current = caret;
        }

        // 获取光标位置
        const range = selection.getRangeAt(0);
        const rects = range.getClientRects();

        if (rects.length === 0) {
            // 如果没有 rects，尝试用 range 的 boundingClientRect
            const rect = range.getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) {
                caretRef.current.style.display = 'none';
                return;
            }
        }

        // 使用第一个 rect（光标位置）
        const rect = rects.length > 0 ? rects[0] : range.getBoundingClientRect();
        const rootRect = rootElement.getBoundingClientRect();
        const editorScrollTop = rootElement.scrollTop;
        const containerRect = rootElement.parentElement?.getBoundingClientRect();

        if (!containerRect) return;

        // 计算光标的正确高度（基于字体大小，而不是行高）
        // 获取当前字体大小
        let fontSize = 15; // 默认字体大小
        if (anchorNode.nodeType === Node.TEXT_NODE && anchorNode.parentElement) {
            const computedStyle = window.getComputedStyle(anchorNode.parentElement);
            fontSize = parseFloat(computedStyle.fontSize) || 15;
        } else if (anchorNode.nodeType === Node.ELEMENT_NODE) {
            const computedStyle = window.getComputedStyle(anchorNode as Element);
            fontSize = parseFloat(computedStyle.fontSize) || 15;
        }

        // 光标高度 = 字体大小 * 1.2（略高于字体，看起来更自然）
        const caretHeight = fontSize * 1.2;

        // 计算光标位置（相对于编辑器容器）
        const left = rect.left - containerRect.left;
        // 垂直居中对齐到行框
        const top = rect.top - containerRect.top + (rect.height - caretHeight) / 2;

        // 更新光标样式
        caretRef.current.style.display = 'block';
        caretRef.current.style.left = `${left}px`;
        caretRef.current.style.top = `${top}px`;
        caretRef.current.style.height = `${caretHeight}px`;
    }, [editor]);

    useEffect(() => {
        const rootElement = editor.getRootElement();
        if (!rootElement) return;

        // 添加隐藏原生光标的类
        rootElement.classList.add('hide-native-caret');

        // 监听选区变化
        const handleSelectionChange = () => {
            // 使用 requestAnimationFrame 来确保在 DOM 更新后执行
            if (animationFrameRef.current) {
                cancelAnimationFrame(animationFrameRef.current);
            }
            animationFrameRef.current = requestAnimationFrame(updateCaretPosition);
        };

        document.addEventListener('selectionchange', handleSelectionChange);

        // 也监听编辑器的 focus/blur 事件
        const handleFocus = () => {
            handleSelectionChange();
        };

        const handleBlur = () => {
            if (caretRef.current) {
                caretRef.current.style.display = 'none';
            }
        };

        rootElement.addEventListener('focus', handleFocus);
        rootElement.addEventListener('blur', handleBlur);

        // 初始更新
        handleSelectionChange();

        return () => {
            document.removeEventListener('selectionchange', handleSelectionChange);
            rootElement.removeEventListener('focus', handleFocus);
            rootElement.removeEventListener('blur', handleBlur);
            rootElement.classList.remove('hide-native-caret');

            if (animationFrameRef.current) {
                cancelAnimationFrame(animationFrameRef.current);
            }

            if (caretRef.current) {
                caretRef.current.remove();
                caretRef.current = null;
            }
        };
    }, [editor, updateCaretPosition]);

    return null;
}
