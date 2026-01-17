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
import { $getRoot, EditorState } from 'lexical';

import { SettingsContext } from './context/SettingsContext';
import { ToolbarContext } from './context/ToolbarContext';
import { SharedHistoryContext } from './context/SharedHistoryContext';
import ToolbarPlugin from './plugins/ToolbarPlugin';
import ImagesPlugin from './plugins/ImagesPlugin';
import TableActionMenuPlugin from './plugins/TableActionMenuPlugin';
import DragDropPastePlugin from './plugins/DragDropPastePlugin';
import PlaygroundNodes from './nodes/PlaygroundNodes';
import PlaygroundEditorTheme from './themes/PlaygroundEditorTheme';
import { useState, useEffect } from 'react';

function Editor() {
    const [editor] = useLexicalComposerContext();
    const [activeEditor, setActiveEditor] = useState(editor);
    const [isLinkEditMode, setIsLinkEditMode] = useState(false);

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
        window.setContent = (html: string) => {
            editor.update(() => {
                const parser = new DOMParser();
                const dom = parser.parseFromString(html, 'text/html');
                const nodes = $generateNodesFromDOM(editor, dom);
                const root = $getRoot();
                root.clear();
                root.append(...nodes);
            });
        };

        window.setTitle = () => { };
        window.setWindowActive = (active: boolean) => {
            // Handle visual state
            document.body.classList.toggle('inactive', !active);
        };

        if (window.webkit?.messageHandlers?.editor) {
            window.webkit.messageHandlers.editor.postMessage({ type: 'ready' });
        }
    }, [editor]);

    return (
        <div className="editor-shell">
            <ToolbarPlugin
                editor={editor}
                activeEditor={activeEditor}
                setActiveEditor={setActiveEditor}
                setIsLinkEditMode={setIsLinkEditMode}
            />
            <div className="editor-container">
                <div className="editor-scroller">
                    <RichTextPlugin
                        contentEditable={<ContentEditable className="editor-input" />}
                        placeholder={<div className="editor-placeholder">Start typing...</div>}
                        ErrorBoundary={LexicalErrorBoundary}
                    />
                    <HistoryPlugin />
                    <AutoFocusPlugin />
                    <ListPlugin />
                    <CheckListPlugin />
                    <TablePlugin />
                    <ImagesPlugin />
                    <DragDropPastePlugin />
                    <TableActionMenuPlugin />
                    <OnChangePlugin onChange={onChange} />
                </div>
            </div>
        </div>
    );
}

export default function App() {
    const initialConfig = {
        namespace: 'StickyNotes',
        nodes: [...PlaygroundNodes],
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
