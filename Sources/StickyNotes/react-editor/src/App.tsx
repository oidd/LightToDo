import { LexicalComposer } from '@lexical/react/LexicalComposer';
import { RichTextPlugin } from '@lexical/react/LexicalRichTextPlugin';
import { ContentEditable } from '@lexical/react/LexicalContentEditable';
import { HistoryPlugin } from '@lexical/react/LexicalHistoryPlugin';
import { AutoFocusPlugin } from '@lexical/react/LexicalAutoFocusPlugin';
import { LexicalErrorBoundary } from '@lexical/react/LexicalErrorBoundary';
import { CheckListPlugin } from '@lexical/react/LexicalCheckListPlugin';
import { ListPlugin } from '@lexical/react/LexicalListPlugin';
import { TablePlugin } from '@lexical/react/LexicalTablePlugin';
import { useLexicalComposerContext } from '@lexical/react/LexicalComposerContext';
import { OnChangePlugin } from '@lexical/react/LexicalOnChangePlugin';
import { $generateHtmlFromNodes, $generateNodesFromDOM } from '@lexical/html';
import { $getRoot, EditorState, TextNode, $setSelection, FORMAT_ELEMENT_COMMAND, FORMAT_TEXT_COMMAND } from 'lexical';
import { INSERT_ORDERED_LIST_COMMAND, INSERT_UNORDERED_LIST_COMMAND } from '@lexical/list';
import { clearFormatting } from './plugins/ToolbarPlugin/utils';

import CodeHighlightPlugin from './plugins/CodeHighlightPlugin';
import { SettingsContext } from './context/SettingsContext';
import { ToolbarContext } from './context/ToolbarContext';
import { SharedHistoryContext } from './context/SharedHistoryContext';
import ToolbarPlugin from './plugins/ToolbarPlugin';
import ImagesPlugin from './plugins/ImagesPlugin';
import TableActionMenuPlugin from './plugins/TableActionMenuPlugin';
import TableCellResizerPlugin from './plugins/TableCellResizer';
import TableHoverActionsPlugin from './plugins/TableHoverActionsV2Plugin';
import DraggableBlockPlugin from './plugins/DraggableBlockPlugin';
import DragDropPastePlugin from './plugins/DragDropPastePlugin';
import PlaygroundNodes from './nodes/PlaygroundNodes';
import PlaygroundEditorTheme from './themes/PlaygroundEditorTheme';
import CaretFixPlugin from './plugins/CaretFixPlugin';
import NewNoteButton from './ui/NewNoteButton';
import ShortcutsPlugin from './plugins/ShortcutsPlugin';

import { useState, useEffect } from 'react';
import TodoView from './ui/TodoView';
import { ExtendedTextNode } from './nodes/ExtendedTextNode';

export type ViewMode = 'note' | 'todo';

function Editor() {
    const [editor] = useLexicalComposerContext();
    const [activeEditor, setActiveEditor] = useState(editor);
    const [isLinkEditMode, setIsLinkEditMode] = useState(false);
    const [viewMode, setViewMode] = useState<ViewMode>('note');

    // Sync with Swift
    const onChange = (editorState: EditorState) => {
        editorState.read(() => {
            const html = $generateHtmlFromNodes(editor, null);
            if (window.webkit?.messageHandlers?.editor) {
                window.webkit.messageHandlers.editor.postMessage({ type: 'update', html: html });
            }
        });
    };

    useEffect(() => {
        (window as any).setContent = (html: string) => {
            editor.update(() => {
                const parser = new DOMParser();
                const dom = parser.parseFromString(html, 'text/html');
                const nodes = $generateNodesFromDOM(editor, dom);
                const root = $getRoot();
                root.clear();
                root.append(...nodes);

                // Clear selection state during node swap to prevent cross-note style leaks
                $setSelection(null);
            });
        };

        (window as any).setViewMode = (mode: ViewMode) => {
            setViewMode(mode);
        };

        // 关键修复：Swift 端调用的是 setMode 而非 setViewMode
        (window as any).setMode = (window as any).setViewMode;

        (window as any).setTitle = () => { };
        (window as any).setWindowActive = (active: boolean) => {
            document.body.classList.toggle('inactive', !active);
        };

        // Context Menu Handlers
        (window as any).clearFormatting = () => {
            clearFormatting(editor);
        };

        (window as any).setAlignment = (alignment: 'left' | 'center' | 'right' | 'justify') => {
            editor.dispatchCommand(FORMAT_ELEMENT_COMMAND, alignment);
        };

        (window as any).setListType = (type: 'number' | 'bullet') => {
            if (type === 'number') {
                editor.dispatchCommand(INSERT_ORDERED_LIST_COMMAND, undefined);
            } else if (type === 'bullet') {
                editor.dispatchCommand(INSERT_UNORDERED_LIST_COMMAND, undefined);
            }
        };

        (window as any).toggleInlineCode = () => {
            editor.dispatchCommand(FORMAT_TEXT_COMMAND, 'code');
        };

        if (window.webkit?.messageHandlers?.editor) {
            window.webkit.messageHandlers.editor.postMessage({ type: 'ready' });
        }
    }, [editor]);

    const [floatingAnchorElem, setFloatingAnchorElem] = useState<HTMLDivElement | null>(null);

    const onRef = (_floatingAnchorElem: HTMLDivElement) => {
        if (_floatingAnchorElem !== null) {
            setFloatingAnchorElem(_floatingAnchorElem);
        }
    };

    return (
        <div className={`editor-shell ${viewMode}-mode-active`} data-view-mode={viewMode}>
            <div className="toolbar-wrapper">
                <NewNoteButton />
                <ToolbarPlugin
                    editor={editor}
                    activeEditor={activeEditor}
                    setActiveEditor={setActiveEditor}
                    setIsLinkEditMode={setIsLinkEditMode}
                />
            </div>

            <div className="mode-container">
                <div className="editor-container" ref={onRef}>
                    <RichTextPlugin
                        contentEditable={
                            <div className="editor-scroller">
                                <div className="editor">
                                    <ContentEditable className="editor-input" />
                                </div>
                            </div>
                        }
                        placeholder={<div className="editor-placeholder">输入内容...</div>}
                        ErrorBoundary={LexicalErrorBoundary}
                    />
                    <HistoryPlugin />
                    <AutoFocusPlugin />
                    <ListPlugin />
                    <CheckListPlugin />
                    <TablePlugin />
                    <ImagesPlugin />
                    <CodeHighlightPlugin />
                    <DragDropPastePlugin />
                    <TableActionMenuPlugin />
                    <TableCellResizerPlugin />
                    {floatingAnchorElem && (
                        <>
                            <TableHoverActionsPlugin anchorElem={floatingAnchorElem} />
                            <DraggableBlockPlugin anchorElem={floatingAnchorElem} />
                        </>
                    )}
                    <CaretFixPlugin />
                    <ShortcutsPlugin
                        editor={editor}
                        setIsLinkEditMode={setIsLinkEditMode}
                    />
                    <OnChangePlugin onChange={onChange} />
                </div>
                {viewMode === 'todo' && <TodoView />}
            </div>
        </div>
    );
}

export default function App() {
    const initialConfig = {
        namespace: 'StickyNotes',
        nodes: [
            ...PlaygroundNodes,
            ExtendedTextNode,
        ],
        onError: (error: Error) => { console.error(error); },
        theme: PlaygroundEditorTheme,
    };

    return (
        <SettingsContext>
            <ToolbarContext>
                <SharedHistoryContext>
                    <LexicalComposer initialConfig={initialConfig}>
                        <Editor />
                    </LexicalComposer>
                </SharedHistoryContext>
            </ToolbarContext>
        </SettingsContext>
    );
}
