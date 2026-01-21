import React, { useEffect, useState, useRef, useCallback } from 'react';
import { useLexicalComposerContext } from '@lexical/react/LexicalComposerContext';
import { $getRoot, $getNodeByKey, TextNode, LexicalNode, NodeKey } from 'lexical';
import { $isListItemNode, $isListNode, ListItemNode, $createListItemNode, $createListNode } from '@lexical/list';
import { $createReminderNode, $isReminderNode, ReminderNode, ReminderData } from '../nodes/ReminderNode';
import ReminderSettingsDialog from './ReminderSettingsDialog';

interface TodoItem {
    key: string;
    text: string;
    checked: boolean;
    reminder?: ReminderData;
}

export default function TodoView() {
    const [editor] = useLexicalComposerContext();
    const [todos, setTodos] = useState<TodoItem[]>([]);
    const pendingFocusKey = useRef<string | null>(null);
    const itemRefs = useRef<Record<string, HTMLTextAreaElement | null>>({});

    // Dialog State
    const [isDialogOpen, setIsDialogOpen] = useState(false);
    const [dialogTargetKey, setDialogTargetKey] = useState<string | null>(null);
    const [dialogInitialData, setDialogInitialData] = useState<ReminderData | undefined>(undefined);

    const updateTodos = useCallback(() => {
        editor.getEditorState().read(() => {
            const newTodos: TodoItem[] = [];
            const root = $getRoot();

            const walk = (node: LexicalNode) => {
                if ($isListItemNode(node)) {
                    const parent = node.getParent();
                    if ($isListNode(parent) && parent.getListType() === 'check') {
                        // Extract text and reminder
                        let text = "";
                        let reminder: ReminderData | undefined = undefined;

                        const children = node.getChildren();
                        children.forEach(child => {
                            if ($isReminderNode(child)) {
                                reminder = child.getData();
                            } else {
                                text += child.getTextContent();
                            }
                        });

                        newTodos.push({
                            key: node.getKey(),
                            text: text,
                            checked: node.getChecked() || false,
                            reminder
                        });
                    }
                }

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
        return editor.registerUpdateListener(() => {
            updateTodos();
        });
    }, [editor, updateTodos]);

    useEffect(() => {
        if (pendingFocusKey.current) {
            const key = pendingFocusKey.current;
            const el = itemRefs.current[key];
            if (el) {
                el.focus();
                pendingFocusKey.current = null;
            }
        }
    });

    const handleToggle = (key: string, checked: boolean, todo: TodoItem) => {
        if (!checked) {
            editor.update(() => {
                const node = $getNodeByKey(key);
                if ($isListItemNode(node)) {
                    node.setChecked(false);
                }
            });
            return;
        }

        if (todo.reminder && todo.reminder.repeatType !== 'none') {
            calculateNextReminderAndReplace(key, todo);
        } else {
            deleteNode(key);
        }
    };

    const calculateNextReminderAndReplace = (key: string, todo: TodoItem) => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if (!$isListItemNode(node)) return;

            const reminder = todo.reminder!;
            let nextTime = reminder.time;
            const d = new Date(nextTime);

            switch (reminder.repeatType) {
                case 'daily':
                    d.setDate(d.getDate() + 1);
                    break;
                case 'weekly':
                    d.setDate(d.getDate() + 7);
                    break;
                case 'monthly':
                    d.setMonth(d.getMonth() + 1);
                    break;
                case 'yearly':
                    d.setFullYear(d.getFullYear() + 1);
                    break;
                case 'weekdays':
                    const day = d.getDay();
                    if (day === 5) d.setDate(d.getDate() + 3);
                    else if (day === 6) d.setDate(d.getDate() + 2);
                    else d.setDate(d.getDate() + 1);
                    break;
            }

            nextTime = d.getTime();
            const newReminder = { ...reminder, time: nextTime };

            const newNode = $createListItemNode();
            newNode.setChecked(false);
            newNode.append(new TextNode(todo.text));
            newNode.append($createReminderNode(newReminder));

            node.replace(newNode);
        });
    };

    const deleteNode = (key: string) => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if (node) node.remove();
        });
    };

    const handleTextChange = (key: string, text: string) => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if ($isListItemNode(node)) {
                const children = node.getChildren();
                const reminderNode = children.find(c => $isReminderNode(c));

                node.clear();
                node.append(new TextNode(text));
                if (reminderNode) {
                    node.append(reminderNode);
                }
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
        deleteNode(key);
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

    const openReminderSettings = (key: string, currentWarning?: ReminderData) => {
        setDialogTargetKey(key);
        setDialogInitialData(currentWarning);
        setIsDialogOpen(true);
    };

    const saveReminder = (data: ReminderData) => {
        if (!dialogTargetKey) return;
        editor.update(() => {
            const node = $getNodeByKey(dialogTargetKey);
            if ($isListItemNode(node)) {
                const children = node.getChildren();
                children.forEach(c => {
                    if ($isReminderNode(c)) c.remove();
                });
                node.append($createReminderNode(data));
            }
        });
    };

    const removeReminder = () => {
        if (!dialogTargetKey) return;
        editor.update(() => {
            const node = $getNodeByKey(dialogTargetKey);
            if ($isListItemNode(node)) {
                const children = node.getChildren();
                children.forEach(c => {
                    if ($isReminderNode(c)) c.remove();
                });
            }
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
                        onToggle={(checked) => handleToggle(todo.key, checked, todo)}
                        onTextChange={handleTextChange}
                        onEnter={handleEnter}
                        onDelete={handleDelete}
                        onOpenReminder={() => openReminderSettings(todo.key, todo.reminder)}
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
                        <div className="todo-content-wrapper">
                            <div className="todo-input-mirror-container">
                                <div className="todo-input" style={{ color: '#8e8e93', cursor: 'pointer' }}>新增待办事项</div>
                            </div>
                        </div>
                    </div>
                )}
            </div>

            <ReminderSettingsDialog
                isOpen={isDialogOpen}
                initialData={dialogInitialData}
                onClose={() => setIsDialogOpen(false)}
                onSave={saveReminder}
                onRemove={removeReminder}
            />
        </div>
    );
}

interface RowProps {
    todo: TodoItem;
    registerRef: (key: string, el: HTMLTextAreaElement | null) => void;
    onToggle: (checked: boolean) => void;
    onTextChange: (key: string, text: string) => void;
    onEnter: (key: string) => void;
    onDelete: (key: string) => void;
    onOpenReminder: () => void;
}

function TodoItemRow({ todo, registerRef, onToggle, onTextChange, onEnter, onDelete, onOpenReminder }: RowProps) {
    const textareaRef = useRef<HTMLTextAreaElement>(null);
    const [localText, setLocalText] = useState(todo.text);
    const isComposing = useRef(false);

    // Animation state
    const [isClosing, setIsClosing] = useState(false);

    useEffect(() => {
        registerRef(todo.key, textareaRef.current);
        return () => registerRef(todo.key, null);
    }, [registerRef, todo.key]);

    useEffect(() => {
        if (!isComposing.current && todo.text !== localText) {
            setLocalText(todo.text);
        }
    }, [todo.text]);

    const handleCheckboxChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const checked = e.target.checked;
        if (checked) {
            setIsClosing(true);
            setTimeout(() => {
                onToggle(true);
                setIsClosing(false);
            }, 300);
        } else {
            onToggle(false);
        }
    };

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            onEnter(todo.key);
        } else if (e.key === 'Backspace' && localText === '') {
            e.preventDefault();
            onDelete(todo.key);
        }
    };

    const getMetaInfo = () => {
        if (!todo.reminder) return null;
        const r = todo.reminder;
        const d = new Date(r.time);
        const now = new Date();
        const isOverdue = now.getTime() > r.time;
        const m = d.getMonth() + 1;
        const day = d.getDate();
        const h = String(d.getHours()).padStart(2, '0');
        const min = String(d.getMinutes()).padStart(2, '0');
        const timeStr = `${m}月${day}日 ${h}:${min}`;
        let cycleStr = '';
        if (isOverdue) {
            cycleStr = '已过期';
        } else {
            const map: Record<string, string> = {
                'none': '', 'daily': '每天', 'weekdays': '工作日',
                'weekly': '每周', 'monthly': '每月', 'yearly': '每年'
            };
            cycleStr = map[r.repeatType] || '';
        }
        if (!cycleStr) return timeStr;
        return `${timeStr}，${cycleStr}`;
    };

    const metaText = getMetaInfo();
    const isOverdue = todo.reminder && new Date().getTime() > todo.reminder.time;

    return (
        <div
            className={`todo-row ${todo.checked ? 'completed' : ''} ${todo.reminder ? 'has-reminder' : ''}`}
            style={{
                transform: isClosing ? 'scale(0.95)' : 'scale(1)',
                opacity: isClosing ? 0 : 1,
                // Transition all layout properties to ensure smooth upward shift
                transition: 'opacity 0.3s ease-out, transform 0.3s ease-out, height 0.3s ease-out 0.1s, min-height 0.3s ease-out 0.1s, padding 0.3s ease-out 0.1s, margin 0.3s ease-out 0.1s',
                height: isClosing ? 0 : 'auto',
                minHeight: isClosing ? 0 : 40,
                paddingTop: isClosing ? 0 : 8,
                paddingBottom: isClosing ? 0 : 8,
                marginBottom: isClosing ? 0 : 8,
                overflow: 'hidden'
            }}
        >
            <div className="todo-checkbox-wrapper">
                <input
                    type="checkbox"
                    className="todo-checkbox"
                    checked={todo.checked}
                    onChange={handleCheckboxChange}
                />
            </div>

            <div className="todo-content-wrapper">
                <div className="todo-input-mirror-container">
                    {/* Mirroring element that drives the height */}
                    <div className="todo-input-mirror" aria-hidden="true">
                        {localText || " "}{"\n"}
                    </div>

                    <textarea
                        ref={el => {
                            textareaRef.current = el;
                            if (registerRef) registerRef(todo.key, el);
                        }}
                        className="todo-input"
                        value={localText}
                        onChange={(e) => {
                            setLocalText(e.target.value);
                            if (!isComposing.current) onTextChange(todo.key, e.target.value);
                        }}
                        onCompositionStart={() => isComposing.current = true}
                        onCompositionEnd={(e) => {
                            isComposing.current = false;
                            onTextChange(todo.key, (e.target as any).value);
                        }}
                        onKeyDown={handleKeyDown}
                        onBlur={() => onTextChange(todo.key, localText)}
                        rows={1}
                        placeholder="输入待办事项"
                        spellCheck={false}
                    />
                </div>

                {metaText && (
                    <div className={`todo-meta-info ${isOverdue ? 'overdue' : ''}`}>
                        {metaText}
                    </div>
                )}
            </div>

            <div className="todo-icon-group">
                <div className="reminder-btn" onClick={onOpenReminder}>
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path>
                        <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
                    </svg>
                </div>
                <div className="todo-delete-btn" onClick={() => onDelete(todo.key)}>✕</div>
            </div>
        </div>
    );
}
