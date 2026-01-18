import React, { useEffect, useState, useRef, useCallback } from 'react';
import { useLexicalComposerContext } from '@lexical/react/LexicalComposerContext';
import { $getRoot, $getNodeByKey, TextNode, LexicalNode } from 'lexical';
import { $isListItemNode, $isListNode, ListItemNode, $createListItemNode, $createListNode } from '@lexical/list';

interface TodoItem {
    key: string;
    text: string;
    checked: boolean;
}


export default function TodoView() {
    const [editor] = useLexicalComposerContext();
    const [todos, setTodos] = useState<TodoItem[]>([]);
    const pendingFocusKey = useRef<string | null>(null);
    const itemRefs = useRef<Record<string, HTMLTextAreaElement | null>>({});

    const updateTodos = useCallback(() => {
        editor.getEditorState().read(() => {
            const newTodos: TodoItem[] = [];
            const root = $getRoot();

            // Deep scan for all list items in checklist
            const walk = (node: LexicalNode) => {
                if ($isListItemNode(node)) {
                    const parent = node.getParent();
                    if ($isListNode(parent) && parent.getListType() === 'check') {
                        newTodos.push({
                            key: node.getKey(),
                            text: node.getTextContent(),
                            checked: node.getChecked() || false,
                        });
                    }
                }

                // Use getChildren logic for nodes that support it
                if ('getChildren' in node && typeof (node as any).getChildren === 'function') {
                    (node as any).getChildren().forEach(walk);
                }
            };

            root.getChildren().forEach(walk);
            setTodos(newTodos);
        });
    }, [editor]);

    useEffect(() => {
        updateTodos();
        // Listen for internal changes to keep view synced
        return editor.registerUpdateListener(() => {
            updateTodos();
        });
    }, [editor, updateTodos]);

    // Focus management effect - runs after every render
    useEffect(() => {
        if (pendingFocusKey.current) {
            const key = pendingFocusKey.current;
            // Attempt to focus
            const el = itemRefs.current[key];
            if (el) {
                el.focus();
                pendingFocusKey.current = null; // Clear trigger
            }
        }
    });

    const handleToggle = (key: string, checked: boolean) => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if ($isListItemNode(node)) {
                node.setChecked(checked);
            }
        });
    };

    const handleTextChange = (key: string, text: string) => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if ($isListItemNode(node)) {
                node.clear();
                node.append(new TextNode(text));
            }
        });
    };

    const handleEnter = (key: string) => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if ($isListItemNode(node)) {
                const newNode = $createListItemNode();
                newNode.setChecked(false);
                node.insertAfter(newNode);
                pendingFocusKey.current = newNode.getKey();
            }
        });
    };

    const handleDelete = (key: string) => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if ($isListItemNode(node)) {
                const parent = node.getParent();
                node.remove();
                // Clean up empty list
                if (parent && $isListNode(parent) && parent.getChildrenSize() === 0) {
                    parent.remove();
                }
            }
        });
    };

    const handleCreateFirst = () => {
        editor.update(() => {
            const root = $getRoot();
            const listNode = $createListNode('check');
            const listItem = $createListItemNode();
            listNode.append(listItem);
            root.append(listNode);
            pendingFocusKey.current = listItem.getKey();
        });
    };

    const setItemRef = useCallback((key: string, el: HTMLTextAreaElement | null) => {
        itemRefs.current[key] = el;
    }, []);

    return (
        <div className="todo-view">
            <div className="todo-header">待办事项</div>
            <div className="todo-list">
                {todos.map(todo => (
                    <TodoItemRow
                        key={todo.key}
                        todo={todo}
                        registerRef={setItemRef}
                        onToggle={handleToggle}
                        onTextChange={handleTextChange}
                        onEnter={handleEnter}
                        onDelete={handleDelete}
                    />
                ))}
                {todos.length === 0 ? (
                    <div className="todo-empty" onClick={handleCreateFirst}>
                        点击添加您的第一条待办事项...
                    </div>
                ) : (
                    <div className="todo-row add-new" onClick={() => handleEnter(todos[todos.length - 1].key)}>
                        <div className="todo-checkbox-wrapper">
                            <div className="todo-checkbox" style={{ borderColor: 'transparent', opacity: 0.3 }}></div>
                        </div>
                        <div className="todo-input" style={{ color: '#8e8e93', cursor: 'pointer' }}>新增待办事项</div>
                    </div>
                )}
            </div>
        </div>
    );
}

interface RowProps {
    todo: TodoItem;
    registerRef: (key: string, el: HTMLTextAreaElement | null) => void;
    onToggle: (key: string, checked: boolean) => void;
    onTextChange: (key: string, text: string) => void;
    onEnter: (key: string) => void;
    onDelete: (key: string) => void;
}

function TodoItemRow({ todo, registerRef, onToggle, onTextChange, onEnter, onDelete }: RowProps) {
    const textareaRef = useRef<HTMLTextAreaElement>(null);
    const [localText, setLocalText] = useState(todo.text);
    const isComposing = useRef(false);

    // Sync ref to parent
    // Sync ref to parent
    useEffect(() => {
        registerRef(todo.key, textareaRef.current);
        // cleanup not strictly necessary as map key change handles it, but good practice
        return () => registerRef(todo.key, null);
    }, [registerRef, todo.key]);

    // Sync from props only if not composing and value actually changed elsewhere
    useEffect(() => {
        if (!isComposing.current && todo.text !== localText) {
            setLocalText(todo.text);
        }
    }, [todo.text]);

    // Auto-resize height based on content
    useEffect(() => {
        if (textareaRef.current) {
            textareaRef.current.style.height = 'auto';
            textareaRef.current.style.height = textareaRef.current.scrollHeight + 'px';
        }
    }, [localText]);

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            onEnter(todo.key);
        } else if (e.key === 'Backspace' && localText === '') {
            e.preventDefault();
            onDelete(todo.key);
        }
    };

    const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
        const value = e.target.value;
        setLocalText(value);
        if (!isComposing.current) {
            onTextChange(todo.key, value);
        }
    };

    const handleCompositionStart = () => {
        isComposing.current = true;
    };

    const handleCompositionEnd = (e: React.CompositionEvent<HTMLTextAreaElement>) => {
        isComposing.current = false;
        onTextChange(todo.key, (e.target as any).value);
    };

    return (
        <div className={`todo-row ${todo.checked ? 'completed' : ''}`}>
            <div className="todo-checkbox-wrapper">
                <input
                    type="checkbox"
                    className="todo-checkbox"
                    checked={todo.checked}
                    onChange={(e) => onToggle(todo.key, e.target.checked)}
                />
            </div>
            <textarea
                ref={textareaRef}
                className="todo-input"
                value={localText}
                onChange={handleChange}
                onCompositionStart={handleCompositionStart}
                onCompositionEnd={handleCompositionEnd}
                onKeyDown={handleKeyDown}
                onBlur={() => onTextChange(todo.key, localText)}
                rows={1}
                placeholder="输入待办事项"
                spellCheck={false}
            />
            {/* Delete button (X) */}
            <div className="todo-delete-btn" onClick={() => onDelete(todo.key)}>
                ✕
            </div>
        </div>
    );
}
