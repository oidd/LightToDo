import { LexicalComposer } from '@lexical/react/LexicalComposer';
import { RichTextPlugin } from '@lexical/react/LexicalRichTextPlugin';
import { ContentEditable } from '@lexical/react/LexicalContentEditable';
import { HistoryPlugin } from '@lexical/react/LexicalHistoryPlugin';
import { AutoFocusPlugin } from '@lexical/react/LexicalAutoFocusPlugin';
import { LexicalErrorBoundary } from '@lexical/react/LexicalErrorBoundary';
import { CheckListPlugin } from '@lexical/react/LexicalCheckListPlugin';
import { ListPlugin } from '@lexical/react/LexicalListPlugin';
import { useLexicalComposerContext } from '@lexical/react/LexicalComposerContext';
import { OnChangePlugin } from '@lexical/react/LexicalOnChangePlugin';
import { $generateHtmlFromNodes, $generateNodesFromDOM } from '@lexical/html';
import { $getRoot, EditorState, $setSelection } from 'lexical';

import { SettingsContext } from './context/SettingsContext';
import { ToolbarContext } from './context/ToolbarContext';
import { SharedHistoryContext } from './context/SharedHistoryContext';
import PlaygroundNodes from './nodes/PlaygroundNodes';
import PlaygroundEditorTheme from './themes/PlaygroundEditorTheme';

import { useEffect } from 'react';
import TodoView from './ui/TodoView';
import { ExtendedTextNode } from './nodes/ExtendedTextNode';
import { ReminderNode } from './nodes/ReminderNode';

function TodoEditor() {
    const [editor] = useLexicalComposerContext();

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
                $setSelection(null);
            });
        };

        (window as any).setTitle = () => { };
        (window as any).setWindowActive = (active: boolean) => {
            document.body.classList.toggle('inactive', !active);
        };
        (window as any).setMode = (mode: string) => {
            console.log('Mode set to:', mode);
        };

        if (window.webkit?.messageHandlers?.editor) {
            window.webkit.messageHandlers.editor.postMessage({ type: 'ready' });
        }
    }, [editor]);

    return (
        <div className="editor-shell todo-mode-active" data-view-mode="todo">
            <div className="mode-container">
                <div className="editor-container">
                    {/* Keep Lexical engine active for Todo management */}
                    <div style={{ display: 'none' }}>
                        <RichTextPlugin
                            contentEditable={<ContentEditable />}
                            placeholder={null}
                            ErrorBoundary={LexicalErrorBoundary}
                        />
                    </div>
                    <HistoryPlugin />
                    <AutoFocusPlugin />
                    <ListPlugin />
                    <CheckListPlugin />
                    <OnChangePlugin onChange={onChange} />

                    {/* Main UI is now exclusively TodoView */}
                    <TodoView />
                </div>
            </div>
        </div>
    );
}

export default function App() {
    const initialConfig = {
        namespace: 'LightToDo',
        nodes: [
            ...PlaygroundNodes,
            ExtendedTextNode,
            ReminderNode,
        ],
        onError: (error: Error) => { console.error(error); },
        theme: PlaygroundEditorTheme,
    };

    return (
        <SettingsContext>
            <ToolbarContext>
                <SharedHistoryContext>
                    <LexicalComposer initialConfig={initialConfig}>
                        <TodoEditor />
                    </LexicalComposer>
                </SharedHistoryContext>
            </ToolbarContext>
        </SettingsContext>
    );
}
