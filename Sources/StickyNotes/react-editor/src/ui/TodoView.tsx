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
    const [filterMode, setFilterMode] = useState<string>('all');
    const [searchQuery, setSearchQuery] = useState<string>('');
    const pendingFocusKey = useRef<string | null>(null);
    const itemRefs = useRef<Record<string, HTMLTextAreaElement | null>>({});

    // Dialog State
    const [isDialogOpen, setIsDialogOpen] = useState(false);
    const [dialogTargetKey, setDialogTargetKey] = useState<string | null>(null);
    const [dialogInitialData, setDialogInitialData] = useState<ReminderData | undefined>(undefined);

    // Optimistic UI State for recurring tasks
    const [optimisticIds, setOptimisticIds] = useState<Set<string>>(new Set());
    const pendingTimeouts = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

    // Sticky display logic: once an item is shown in a view, keep showing it even if data changes, until view changes
    const displayedKeys = useRef<Set<string>>(new Set());

    const updateTodos = useCallback(() => {
        editor.getEditorState().read(() => {
            const allItems: TodoItem[] = [];
            const root = $getRoot();

            function walkTree(node: LexicalNode) {
                // Check if it's a list item in a checklist
                if ($isListItemNode(node)) {
                    const parent = node.getParent();
                    if ($isListNode(parent) && parent.getListType() === 'check') {
                        let text = "";
                        let reminder: ReminderData | undefined = undefined;

                        node.getChildren().forEach(child => {
                            if ($isReminderNode(child)) {
                                reminder = child.getData();
                            } else {
                                text += child.getTextContent();
                            }
                        });

                        allItems.push({
                            key: node.getKey(),
                            text: text,
                            checked: node.getChecked() || false,
                            reminder
                        });
                    }
                }

                // Recursively walk through all children of any type
                if ('getChildren' in node && typeof (node as any).getChildren === 'function') {
                    (node as any).getChildren().forEach(walkTree);
                }
            }

            walkTree(root);

            // Calculate counts for all modes
            const now = new Date();
            const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
            const endOfToday = startOfToday + 24 * 60 * 60 * 1000;

            const counts = {
                all: allItems.filter(t => !t.checked).length,
                today: allItems.filter(t => !t.checked && t.reminder && t.reminder.time >= startOfToday && t.reminder.time < endOfToday).length,
                recurring: allItems.filter(t => t.reminder && t.reminder.repeatType !== 'none').length,
                completed: allItems.filter(t => t.checked).length
            };

            console.log('📊 Total Items Found:', allItems.length);
            console.log('📊 Generated Counts:', counts);

            // Send counts back to Swift
            if (window.webkit?.messageHandlers?.editor) {
                window.webkit.messageHandlers.editor.postMessage({ type: 'counts', data: counts });
            } else {
                console.warn('⚠️ window.webkit.messageHandlers.editor NOT FOUND');
            }

            // Filter todos based on current mode
            // We implement "sticky" logic: if an item is currently displayed, keep it displayed 
            // even if it no longer strictly matches the filter (e.g. user changed date), 
            // until the user switches views.

            const strictMatches = allItems.filter(t => {
                if (t.checked) {
                    // Check if it's optimistically kept
                    return filterMode === 'completed';
                    // Note: Optimistic checked items are handled by optimisticIds overlay in render, 
                    // but here we filter raw data. Raw data 'checked' is false for optimistic items usually.
                    // If raw data is checked, it belongs in completed.
                }

                switch (filterMode) {
                    case 'today':
                        return t.reminder && t.reminder.time >= startOfToday && t.reminder.time < endOfToday;
                    case 'recurring':
                        return t.reminder && t.reminder.repeatType !== 'none';
                    case 'completed':
                        return false; // Should satisfy t.checked check above
                    case 'all':
                    default:
                        return true;
                }
            });

            // Update displayed keys with current strict matches
            strictMatches.forEach(t => displayedKeys.current.add(t.key));

            // Final filter: strict matches OR (was displayed AND still exists)
            // But we must exclude checked items if mode is not completed (unless optimistic)
            let finalFiltered = allItems.filter(t => {
                if (filterMode === 'completed') {
                    return t.checked;
                }

                // For non-completed modes:
                if (t.checked) return false;

                const isStrict = strictMatches.some(m => m.key === t.key);
                const isSticky = displayedKeys.current.has(t.key);

                return isStrict || isSticky;
            });

            // Apply search filter (overrides all logic, searches within the current view content)
            if (searchQuery.trim()) {
                const lowerQuery = searchQuery.toLowerCase();
                finalFiltered = finalFiltered.filter(t => t.text.toLowerCase().includes(lowerQuery));
            }

            setTodos(finalFiltered);
        });
    }, [editor, filterMode, searchQuery]);

    useEffect(() => {
        updateTodos();
        return editor.registerUpdateListener(() => {
            updateTodos();
        });
    }, [editor, updateTodos]);

    useEffect(() => {
        (window as any).setFilterMode = (mode: string) => {
            setFilterMode(mode);
            // Clear sticky keys on mode switch
            displayedKeys.current.clear();
        };

        (window as any).setSearchQuery = (query: string) => {
            setSearchQuery(query);
        };

        (window as any).addNewTodo = () => {
            // Logic similar to handleCreateFirst but context aware
            editor.getEditorState().read(() => {
                const root = $getRoot();
                // Check if we have any list items to append after, or if we need to create first
                // We'll simulate a click on the "fill area" if items exist, or create first if empty
                // But since we are outside the render loop, we need direct node access

                // Simplest: use handleCreateFirst logic if empty, or handleEnter on last item
                // However, handleEnter needs a key.
                // Let's use a robust approach: find the last ListItemNode and insert after, or create new list.

                const lastItem = todos.length > 0 ? todos[todos.length - 1] : null;
                if (lastItem) {
                    handleEnter(lastItem.key);
                } else {
                    handleCreateFirst();
                }
            });
        };
    }, [todos, editor]); // Add deps to ensure handleEnter/handleCreateFirst work with current state

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
            // If user unchecked while we were waiting for the recurring task to complete (optimistic state)
            if (pendingTimeouts.current.has(key)) {
                clearTimeout(pendingTimeouts.current.get(key));
                pendingTimeouts.current.delete(key);
                setOptimisticIds(prev => {
                    const next = new Set(prev);
                    next.delete(key);
                    return next;
                });
                return; // Do nothing else, Lexical state was never changed
            }

            // Normal uncheck
            editor.update(() => {
                const node = $getNodeByKey(key);
                if ($isListItemNode(node)) {
                    node.setChecked(false);
                }
            });
            return;
        }

        if (todo.reminder && todo.reminder.repeatType !== 'none') {
            // For recurring todos, use Optimistic UI to keep it in the list (visually checked)
            // instead of removing it immediately via filter logic.
            setOptimisticIds(prev => {
                const next = new Set(prev);
                next.add(key);
                return next;
            });

            const timeoutId = setTimeout(() => {
                pendingTimeouts.current.delete(key);
                // Clear optimistic state exactly when we are about to replace data
                setOptimisticIds(prev => {
                    const next = new Set(prev);
                    next.delete(key);
                    return next;
                });
                calculateNextReminderAndReplace(key, todo);
            }, 800);

            pendingTimeouts.current.set(key, timeoutId);
        } else {
            // For normal todos, just mark as checked.
            editor.update(() => {
                const node = $getNodeByKey(key);
                if ($isListItemNode(node)) {
                    node.setChecked(true);
                }
            });
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
            const newReminder = { ...reminder, time: nextTime, autoRefreshedAt: Date.now() };

            // 1. Archive the old task: remove repeat logic so it stays as a simple completed task
            // We must explicitly set it to checked now, because handleToggle didn't do it (it was optimistic)
            node.setChecked(true);

            const children = node.getChildren();
            const oldReminderNode = children.find(c => $isReminderNode(c));
            if (oldReminderNode) {
                oldReminderNode.remove();
                // Add back a reminder node but with no repeat, preserving history
                node.append($createReminderNode({ ...reminder, repeatType: 'none' }));
            }

            // 2. Create new task for next cycle
            const newNode = $createListItemNode();
            newNode.setChecked(false);
            newNode.append(new TextNode(todo.text));
            newNode.append($createReminderNode(newReminder));

            // Insert new task after the old one
            node.insertAfter(newNode);
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

    const getDefaultReminder = (mode: string): ReminderData | undefined => {
        const now = Date.now();
        const oneHourLater = now + 60 * 60 * 1000;

        if (mode === 'today') {
            return {
                time: oneHourLater,
                repeatType: 'none',
                originalTime: oneHourLater
            };
        }

        if (mode === 'recurring') {
            return {
                time: oneHourLater,
                repeatType: 'daily',
                originalTime: oneHourLater
            };
        }

        return undefined;
    };

    const handleEnter = (key: string) => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if ($isListItemNode(node)) {
                const newNode = $createListItemNode();
                newNode.setChecked(false);

                // Apply default reminder based on current view
                const defaultReminder = getDefaultReminder(filterMode);
                if (defaultReminder) {
                    newNode.append($createReminderNode(defaultReminder));
                }

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

            // Apply default reminder based on current view
            const defaultReminder = getDefaultReminder(filterMode);
            if (defaultReminder) {
                listItem.append($createReminderNode(defaultReminder));
            }

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

    const isCompletedMode = filterMode === 'completed';

    const headerConfig: Record<string, { text: string; color: string }> = {
        all: { text: '待办事项', color: '#007aff' }, // Keep default blue
        today: { text: '今天', color: '#ff8d30' },
        recurring: { text: '周期', color: '#ff3b30' },
        completed: { text: '完成', color: '#8e8e93' }
    };

    const currentHeader = headerConfig[filterMode] || headerConfig['all'];

    return (
        <div className={`todo-view ${filterMode}-mode`}>
            <div className="todo-header" style={{ color: currentHeader.color }}>
                {currentHeader.text}
            </div>
            <div className="todo-list">
                {todos.map(todo => (
                    <TodoItemRow
                        key={todo.key}
                        todo={optimisticIds.has(todo.key) ? { ...todo, checked: true } : todo}
                        isCompletedMode={isCompletedMode}
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
                        点击空白处添加待办事项
                    </div>
                ) : filterMode !== 'completed' && (
                    <div className="todo-fill-area" onClick={() => {
                        const lastItem = todos[todos.length - 1];
                        if (lastItem && lastItem.text === "") {
                            // 如果最后一项是空的，点击空白处则删除它（取消新增）
                            handleDelete(lastItem.key);
                        } else {
                            // 否则正常新增
                            handleEnter(todos[todos.length - 1].key);
                        }
                    }}>
                        {/* Invisible clickable area */}
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
    isCompletedMode: boolean;
}

function TodoItemRow({ todo, registerRef, onToggle, onTextChange, onEnter, onDelete, onOpenReminder, isCompletedMode }: RowProps) {
    const textareaRef = useRef<HTMLTextAreaElement>(null);
    const [localText, setLocalText] = useState(todo.text);
    const isComposing = useRef(false);

    // Animation state
    const [isClosing, setIsClosing] = useState(false);
    const [showShimmer, setShowShimmer] = useState(false);

    useEffect(() => {
        // Disable shimmer if in completed mode
        // Only show shimmer if the task was auto-refreshed recently (within 5 seconds)
        if (!isCompletedMode && todo.reminder?.autoRefreshedAt) {
            const isRecent = Date.now() - todo.reminder.autoRefreshedAt < 5000;
            if (isRecent) {
                setShowShimmer(true);
                const timer = setTimeout(() => setShowShimmer(false), 1000);
                return () => clearTimeout(timer);
            }
        }
    }, [todo.reminder?.autoRefreshedAt, isCompletedMode]);

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
            const isRecurring = todo.reminder && todo.reminder.repeatType !== 'none';
            if (isRecurring) {
                // For recurring todos, don't trigger the closing animation
                // handleToggle will manage the delay and replacement
                onToggle(true);
            } else {
                setIsClosing(true);
                setTimeout(() => {
                    onToggle(true);
                    setIsClosing(false);
                }, 300);
            }
        } else {
            onToggle(false);
        }
    };

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            if (todo.checked || isCompletedMode) {
                // 已完成项目或在完成视图中，禁止回车新增逻辑
                return;
            }
            if (localText === '') {
                // 如果用户没有输入就直接回车，则该空白待办消失（取消新增）
                onDelete(todo.key);
            } else {
                onEnter(todo.key);
            }
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
                transition: 'opacity 0.3s ease-out, transform 0.3s ease-out, height 0.3s ease-out 0.1s, min-height 0.3s ease-out 0.1s, padding 0.3s ease-out 0.1s',
                height: isClosing ? 0 : 'auto',
                minHeight: isClosing ? 0 : 32,
                paddingTop: isClosing ? 0 : 3,
                paddingBottom: isClosing ? 0 : 6,
                overflow: 'hidden'
            }}
        >
            <div className="todo-checkbox-wrapper">
                <input
                    type="checkbox"
                    className={`todo-checkbox ${(!localText && !todo.checked) ? 'draft' : ''}`}
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
                        readOnly={todo.checked || isCompletedMode}
                    />
                </div>

                {metaText && (
                    <div className={`todo-meta-info ${isOverdue ? 'overdue' : ''} ${showShimmer ? 'shimmer' : ''}`}>
                        {metaText}
                    </div>
                )}
            </div>

            <div className="todo-icon-group">
                {!isCompletedMode && (
                    <div className="reminder-btn" onClick={onOpenReminder}>
                        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path>
                            <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
                        </svg>
                    </div>
                )}
                <div className="todo-delete-btn" onClick={() => onDelete(todo.key)}>✕</div>
            </div>
        </div>
    );
}
