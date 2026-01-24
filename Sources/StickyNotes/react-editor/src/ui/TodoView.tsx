import React, { useEffect, useState, useRef, useCallback } from 'react';
import { useLexicalComposerContext } from '@lexical/react/LexicalComposerContext';
import { $getRoot, $getNodeByKey, TextNode, LexicalNode, NodeKey, $nodesOfType } from 'lexical';
import { $isListItemNode, $isListNode, ListItemNode, $createListItemNode, $createListNode } from '@lexical/list';
import { $createReminderNode, $isReminderNode, ReminderNode, ReminderData } from '../nodes/ReminderNode';
import TodoDetailsPanel from './TodoDetailsPanel';
import DropDown, { DropDownItem } from './DropDown';
import { useDateDetection, DateSuggestionPopup, DateDetectionResult } from './DateDetector';
// TodoContextMenu removed - using native menu

export interface TodoItem {
    key: string;
    uuid: string;
    text: string;
    checked: boolean;
    reminder?: ReminderData;
    parentUuid?: string; // Stable parent ID
    parentKey?: string; // Legacy: Parent node key
    children?: TodoItem[];
    isSubItem?: boolean;
    deadlineInvalid?: boolean;
    index: number;
}

export default function TodoView() {
    const [editor] = useLexicalComposerContext();
    const [todos, setTodos] = useState<TodoItem[]>([]);
    const [filterMode, setFilterMode] = useState<string>('all');
    const [searchQuery, setSearchQuery] = useState<string>('');
    const pendingFocusKey = useRef<string | null>(null);
    const itemRefs = useRef<Record<string, HTMLTextAreaElement | null>>({});

    const cleanupEmptyTodos = useCallback((forceIgnoreFocus: boolean = false) => {
        editor.update(() => {
            const listItems = $nodesOfType(ListItemNode);
            listItems.forEach(node => {
                let text = node.getTextContent();
                // Strip priority markers for emptiness check
                text = text.replace(/^(!{1,3}\s*)/, '').trim();

                if (text === '') {
                    // Check if this node is currently focused
                    const isFocused = !forceIgnoreFocus && Object.entries(itemRefs.current).some(([key, el]) => {
                        return el === document.activeElement && key === node.getKey();
                    });

                    if (!isFocused) {
                        node.remove();
                    }
                }
            });
        });
    }, [editor]);

    // Dialog State
    const [isDialogOpen, setIsDialogOpen] = useState(false);
    const [dialogTargetKey, setDialogTargetKey] = useState<string | null>(null);
    const [dialogInitialData, setDialogInitialData] = useState<ReminderData | undefined>(undefined);

    // Optimistic UI State for recurring tasks
    const [optimisticIds, setOptimisticIds] = useState<Set<string>>(new Set());
    const [closingKeys, setClosingKeys] = useState<Set<string>>(new Set());
    const pendingTimeouts = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

    // Sticky display logic: once an item is shown in a view, keep showing it even if data changes, until view changes
    const displayedKeys = useRef<Set<string>>(new Set());

    // Sorting mode from settings
    const [sortMode, setSortMode] = useState<string>('byDeadline');

    // Bell ringing animation state
    const [ringingBells, setRingingBells] = useState<Set<string>>(new Set());
    const bellTimeouts = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

    // Date Detection
    const { detectionResult, detectDate, clearDetection, invalidateRequests } = useDateDetection();
    const detectTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

    // Multi-selection State
    const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
    const [lastClickedKey, setLastClickedKey] = useState<string | null>(null);
    const [contextMenu, setContextMenu] = useState<{ x: number, y: number, keys: string[] } | null>(null);

    const handleRowClick = useCallback((key: string, e: React.MouseEvent) => {
        const isShift = e.shiftKey;
        const isMeta = e.metaKey || e.ctrlKey;

        if (isShift && lastClickedKey) {
            const allKeys = todos.map(t => t.key);
            const currentIndex = allKeys.indexOf(key);
            const lastIndex = allKeys.indexOf(lastClickedKey);
            if (currentIndex !== -1 && lastIndex !== -1) {
                const start = Math.min(currentIndex, lastIndex);
                const end = Math.max(currentIndex, lastIndex);
                const newSelection = new Set(selectedKeys);
                for (let i = start; i <= end; i++) {
                    newSelection.add(allKeys[i]);
                }
                setSelectedKeys(newSelection);
            }
        } else if (isMeta) {
            const newSelection = new Set(selectedKeys);
            if (newSelection.has(key)) {
                newSelection.delete(key);
            } else {
                newSelection.add(key);
            }
            setSelectedKeys(newSelection);
        } else {
            // Normal click: if we were multi-selecting, clear it.
            if (selectedKeys.size > 0) {
                setSelectedKeys(new Set());
            }
            // Ensure focus on the textarea if not already clicking it
            const target = e.target as HTMLElement;
            if (target.tagName !== 'TEXTAREA') {
                itemRefs.current[key]?.focus();
            }
        }
        setLastClickedKey(key);
    }, [selectedKeys, lastClickedKey, todos]);

    const handleDeleteSelected = useCallback(() => {
        const keysToDelete = contextMenu ? contextMenu.keys : Array.from(selectedKeys);
        if (keysToDelete.length === 0) return;

        editor.update(() => {
            keysToDelete.forEach(key => {
                const node = $getNodeByKey(key);
                if (node) {
                    node.remove();
                }
            });
        });
        setSelectedKeys(new Set());
        setLastClickedKey(null);
        setContextMenu(null);
    }, [editor, selectedKeys, contextMenu]);

    // Close context menu on any global click
    useEffect(() => {
        const handleClick = () => setContextMenu(null);
        window.addEventListener('click', handleClick);
        return () => window.removeEventListener('click', handleClick);
    }, []);

    // Focus inputs on right-click (context menu) - always allow native menu
    // Update selection so Swift actions work on correct items.
    useEffect(() => {
        const handleContextMenu = (e: MouseEvent) => {
            const target = e.target as HTMLElement;
            const todoRow = target.closest('.todo-row');
            if (todoRow) {
                const rowKey = todoRow.getAttribute('data-todo-key');
                if (rowKey) {
                    // If multi-selecting and clicked inside selection, keep selection
                    if (selectedKeys.size > 1 && selectedKeys.has(rowKey)) {
                        // Keep selection as-is, native menu will appear
                        // Swift actions will use selectedKeys
                    } else {
                        // Single click or clicking outside selection: Select this item
                        setSelectedKeys(new Set([rowKey]));
                    }
                    // Do NOT prevent default - let native menu appear always.
                }
            }
        };

        document.addEventListener('contextmenu', handleContextMenu);
        return () => document.removeEventListener('contextmenu', handleContextMenu);
    }, [selectedKeys]);

    const updateTodos = useCallback(() => {
        editor.getEditorState().read(() => {
            const allItems: TodoItem[] = [];
            const root = $getRoot();

            function walkTree(node: LexicalNode) {
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
                            uuid: reminder ? (reminder as ReminderData).uuid : '',
                            text: text,
                            checked: node.getChecked() || false,
                            reminder,
                            index: allItems.length
                        });
                    }
                }

                if ('getChildren' in node && typeof (node as any).getChildren === 'function') {
                    (node as any).getChildren().forEach(walkTree);
                }
            }

            walkTree(root);

            const now = new Date();
            const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
            const endOfToday = startOfToday + 24 * 60 * 60 * 1000;

            // 1. First pass: Identify sub-items and populate extra fields
            allItems.forEach(item => {
                if (item.reminder?.parentUuid) {
                    item.parentUuid = item.reminder.parentUuid;
                    item.isSubItem = true;
                } else if (item.reminder?.parentKey) {
                    // Legacy migration
                    item.parentKey = item.reminder.parentKey;
                    item.isSubItem = true;
                }
            });

            // 1.1 Attach children to parents for counting and logical grouping
            // We need maps to find parents by UUID (stable) or Key (legacy)
            const itemMap = new Map<string, TodoItem>(); // by uuid
            const keyMap = new Map<string, TodoItem>(); // by lexical key
            allItems.forEach(item => {
                if (item.uuid) itemMap.set(item.uuid, item);
                keyMap.set(item.key, item);
            });

            allItems.forEach(item => {
                if (item.isSubItem) {
                    let parent: TodoItem | undefined;
                    if (item.parentUuid) {
                        parent = itemMap.get(item.parentUuid);
                    } else if (item.parentKey) {
                        parent = keyMap.get(item.parentKey);
                        // Potential migration path: if found by key, we could upgrade it later
                    }
                    if (parent) {
                        if (!parent.children) parent.children = [];
                        parent.children.push(item);

                        // Check deadline validity
                        const subTime = item.reminder?.time || 0;
                        const parentTime = parent.reminder?.time || 0;
                        if (subTime > 0 && parentTime > 0 && subTime > parentTime) {
                            item.deadlineInvalid = true;
                        }
                    } else {
                        // Orphaned sub-item: Parent is missing.
                        // Heal it by treating it as a root item.
                        item.isSubItem = false;
                        delete item.parentKey;
                        // Note: We don't update Lexical here to avoid recursive updates during read,
                        // but it will be "fixed" in the view and can be deleted/modified by user.
                    }
                }
            });

            // CRITICAL: Sort children by document index to guarantee order
            allItems.forEach(item => {
                if (item.children && item.children.length > 1) {
                    item.children.sort((a, b) => a.index - b.index);
                }
            });

            const counts = {
                all: allItems.filter(t => !t.checked).length,
                today: allItems.filter(t => !t.checked && t.reminder && t.reminder.time >= startOfToday && t.reminder.time < endOfToday).length,
                recurring: allItems.filter(t => !t.checked && t.reminder && t.reminder.repeatType !== 'none').length,
                important: allItems.filter(t => !t.checked && t.reminder && t.reminder.priority !== 'none').length,
                planned: allItems.filter(t => !t.checked && (!t.isSubItem ? (t.children && t.children.length > 0) : true)).length,
                completed: allItems.filter(t => t.checked).length
            };

            if (window.webkit?.messageHandlers?.editor) {
                window.webkit.messageHandlers.editor.postMessage({ type: 'counts', data: counts });
                const reminders = allItems.filter(t => !t.checked && t.reminder?.hasReminder).map(t => ({
                    key: t.key,
                    time: t.reminder?.time || 0,
                    hasReminder: t.reminder?.hasReminder || false
                }));
                window.webkit.messageHandlers.editor.postMessage({ type: 'reminders', data: reminders });
            }

            // 2. Filter logic (Identify matches for ALL items)
            const strictMatches = new Set<string>();
            allItems.forEach(t => {
                let matches = false;
                if (t.checked) {
                    matches = filterMode === 'completed';
                } else {
                    switch (filterMode) {
                        case 'today':
                            matches = !!(t.reminder && t.reminder.time >= startOfToday && t.reminder.time < endOfToday);
                            break;
                        case 'recurring':
                            matches = !!(t.reminder && t.reminder.repeatType !== 'none');
                            break;
                        case 'important':
                            matches = !!(t.reminder && t.reminder.priority !== 'none');
                            break;
                        case 'planned':
                            // Root matches if it has children OR if it was already displayed (sticky draft) OR if it was just created (pending focus)
                            matches = (!t.isSubItem ? (t.children && t.children.length > 0) : true) ||
                                (displayedKeys.current.has(t.key)) ||
                                (pendingFocusKey.current === t.key);
                            break;
                        case 'completed':
                            matches = false;
                            break;
                        case 'all':
                        default:
                            matches = true;
                            break;
                    }
                }
                if (matches) strictMatches.add(t.key);
            });

            // Search logic (further narrows/expands)
            const searchQueryTrim = searchQuery.trim().toLowerCase();
            const matchesSearch = (t: TodoItem) => !searchQueryTrim || t.text.toLowerCase().includes(searchQueryTrim);

            // Group Visibility logic:
            // A group (Parent + its Children) is visible if:
            // 1. Parent matches filter AND matches search
            // 2. OR any Child matches filter AND matches search
            const visibleKeys = new Set<string>();

            allItems.forEach(t => {
                if (!t.isSubItem) {
                    const parentMatches = strictMatches.has(t.key) && matchesSearch(t);
                    const anyChildMatches = t.children?.some(c => strictMatches.has(c.key) && matchesSearch(c));

                    if (parentMatches || anyChildMatches) {
                        visibleKeys.add(t.key); // Parent is visible
                        // Children are potentially visible if they specifically match
                        t.children?.forEach(c => {
                            if (strictMatches.has(c.key) && matchesSearch(c)) {
                                visibleKeys.add(c.key);
                            }
                        });

                        // Special case: If we are in 'All' or 'Search' and the parent matched,
                        // maybe we want all its children visible for context?
                        // "Today/Important/Recurring" usually only show relevant items.
                        if (filterMode === 'all' || searchQueryTrim) {
                            t.children?.forEach(c => visibleKeys.add(c.key));
                        }
                    }
                } else if (!t.parentKey) {
                    // Orphaned sub-item behaving as root
                    if (strictMatches.has(t.key) && matchesSearch(t)) {
                        visibleKeys.add(t.key);
                    }
                }
            });

            const finalFiltered = allItems.filter(t => visibleKeys.has(t.key));

            const priorityMap: Record<string, number> = {
                'high': 3, 'medium': 2, 'low': 1, 'none': 0
            };

            const hasPriority = (t: TodoItem) => t.reminder && t.reminder.priority && t.reminder.priority !== 'none';
            const hasDateTime = (t: TodoItem) => t.reminder && (t.reminder.hasDate || t.reminder.hasTime);

            // Sorting helper for all levels
            const robustSort = (a: TodoItem, b: TodoItem) => {
                // 1. Priority
                const pA = priorityMap[a.reminder?.priority || 'none'];
                const pB = priorityMap[b.reminder?.priority || 'none'];
                if (pA !== pB) return pB - pA;

                // 2. Deadline (if valid)
                const timeA = (a.reminder?.hasDate || a.reminder?.hasTime) ? (a.reminder?.time || 0) : 0;
                const timeB = (b.reminder?.hasDate || b.reminder?.hasTime) ? (b.reminder?.time || 0) : 0;
                if (timeA > 0 && timeB > 0) {
                    if (timeA !== timeB) return timeA - timeB;
                } else if (timeA > 0) return -1;
                else if (timeB > 0) return 1;

                // 3. Document Index
                return a.index - b.index;
            };

            const rootItems = finalFiltered.filter(t => !t.isSubItem);

            const priorityPool: TodoItem[] = [];
            const dateTimePool: TodoItem[] = [];
            const otherPool: TodoItem[] = [];

            rootItems.forEach(t => {
                if (hasPriority(t)) priorityPool.push(t);
                else if (hasDateTime(t)) dateTimePool.push(t);
                else otherPool.push(t);
            });

            priorityPool.sort(robustSort);
            dateTimePool.sort(robustSort);

            // Merge roots
            const sortedRoots: TodoItem[] = new Array(rootItems.length);
            const othersSet = new Set(otherPool.map(t => t.key));
            const sortedPool = [...priorityPool, ...dateTimePool];
            let poolIdx = 0;

            for (let i = 0; i < rootItems.length; i++) {
                const item = rootItems[i];
                if (othersSet.has(item.key)) {
                    sortedRoots[i] = item;
                } else {
                    sortedRoots[i] = sortedPool[poolIdx++];
                }
            }

            const finalFlatList: TodoItem[] = [];
            sortedRoots.forEach(root => {
                if (!root) return;
                finalFlatList.push(root);

                if (root.children && root.children.length > 0) {
                    const visibleChildren = root.children.filter(c => visibleKeys.has(c.key));
                    if (visibleChildren.length > 0) {
                        // Priority sort for children
                        visibleChildren.sort(robustSort);
                        finalFlatList.push(...visibleChildren);
                    }
                }
            });

            // Population of displayedKeys for stickiness
            finalFlatList.forEach(t => displayedKeys.current.add(t.key));
            setTodos(finalFlatList);
        });
    }, [editor, filterMode, searchQuery, sortMode]);

    useEffect(() => {
        updateTodos();
        return editor.registerUpdateListener(() => {
            updateTodos();
        });
    }, [editor, updateTodos]);

    useEffect(() => {
        (window as any).setFilterMode = (mode: string) => {
            cleanupEmptyTodos(true); // Force cleanup when switching tabs
            setFilterMode(mode);
            displayedKeys.current.clear();
        };

        (window as any).setSearchQuery = (query: string) => {
            setSearchQuery(query);
        };

        (window as any).setTodoSortMode = (mode: string) => {
            setSortMode(mode);
        };

        (window as any).triggerBellAnimation = (todoKey: string) => {
            setRingingBells(prev => {
                const next = new Set(prev);
                next.add(todoKey);
                return next;
            });
            const timeout = setTimeout(() => {
                setRingingBells(prev => {
                    const next = new Set(prev);
                    next.delete(todoKey);
                    return next;
                });
                bellTimeouts.current.delete(todoKey);
            }, 60000);
            bellTimeouts.current.set(todoKey, timeout);
        };

        (window as any).stopBellAnimation = (todoKey: string) => {
            if (bellTimeouts.current.has(todoKey)) {
                clearTimeout(bellTimeouts.current.get(todoKey));
                bellTimeouts.current.delete(todoKey);
            }
            setRingingBells(prev => {
                const next = new Set(prev);
                next.delete(todoKey);
                return next;
            });
        };

        (window as any).deleteFocusedTodo = () => {
            const activeElement = document.activeElement;
            if (activeElement && activeElement.classList.contains('todo-input')) {
                const todoRow = activeElement.closest('.todo-row');
                if (todoRow) {
                    for (const todo of todos) {
                        const ref = itemRefs.current[todo.key];
                        if (ref && ref === activeElement) {
                            editor.update(() => {
                                const node = $getNodeByKey(todo.key);
                                if (node) {
                                    node.remove();
                                }
                            });
                            break;
                        }
                    }
                }
            }
        };

        (window as any).getReminderData = () => {
            return JSON.stringify(todos.filter(t => !t.checked && t.reminder?.hasReminder).map(t => ({
                key: t.key,
                time: t.reminder?.time || 0,
                hasReminder: t.reminder?.hasReminder || false
            })));
        };

        (window as any).addNewTodo = () => {
            editor.getEditorState().read(() => {
                const lastItem = todos.length > 0 ? todos[todos.length - 1] : null;
                if (lastItem) {
                    handleEnter(lastItem.key);
                } else {
                    handleCreateFirst();
                }
            });
        };

        const handleGlobalMouseDown = (e: MouseEvent) => {
            const target = e.target as HTMLElement;
            if (!target.closest('.todo-row') && !target.closest('.todo-details-panel') && !target.closest('.dropdown') && !target.closest('.todo-fill-area')) {
                // Use a small timeout to allow focus to shift before checking emptiness
                setTimeout(() => cleanupEmptyTodos(), 100);
            }
        };

        document.addEventListener('mousedown', handleGlobalMouseDown);
        return () => {
            document.removeEventListener('mousedown', handleGlobalMouseDown);
        };
    }, [todos, editor, cleanupEmptyTodos]);

    // Expose sub-item actions for Swift context menu (MOVED DOWN)
    // Auto-flatten removed - prevention is in handleMakeSubItem instead

    useEffect(() => {
        if (pendingFocusKey.current) {
            const key = pendingFocusKey.current;
            const el = itemRefs.current[key];
            if (el) {
                el.focus();
                editor.getEditorState().read(() => {
                    const node = $getNodeByKey(key);
                    if ($isListItemNode(node)) {
                        const reminderNode = node.getChildren().find(c => $isReminderNode(c)) as ReminderNode | undefined;
                        if (reminderNode) {
                            const priority = reminderNode.getPriority();
                            let prefix = '';
                            if (priority === 'high') prefix = '!!! ';
                            else if (priority === 'medium') prefix = '!! ';
                            else if (priority === 'low') prefix = '! ';

                            if (prefix) {
                                el.setSelectionRange(prefix.length, prefix.length);
                            }
                        }
                    }
                });
                pendingFocusKey.current = null;
            }
        }
    });

    const handleToggle = (key: string, checked: boolean, todo: TodoItem) => {
        const isRecurring = todo.reminder && todo.reminder.repeatType !== 'none';

        // Synchronized closing animation
        if (!isRecurring && !isCompletedMode) {
            const keysToClose = new Set<string>([key]);
            if (todo.children) {
                todo.children.forEach(c => keysToClose.add(c.key));
            }

            setClosingKeys(prev => {
                const next = new Set(prev);
                keysToClose.forEach(k => next.add(k));
                return next;
            });

            setTimeout(() => {
                setClosingKeys(prev => {
                    const next = new Set(prev);
                    keysToClose.forEach(k => next.delete(k));
                    return next;
                });
                performToggle(key, checked, todo);
            }, 300);
        } else {
            performToggle(key, checked, todo);
        }
    };

    const performToggle = (key: string, checked: boolean, todo: TodoItem) => {
        if (checked && todo.reminder && todo.reminder.repeatType !== 'none') {
            setOptimisticIds(prev => {
                const next = new Set(prev);
                next.add(key);
                return next;
            });
            const timeoutId = setTimeout(() => {
                pendingTimeouts.current.delete(key);
                setOptimisticIds(prev => {
                    const next = new Set(prev);
                    next.delete(key);
                    return next;
                });
                calculateNextReminderAndReplace(key, todo);
            }, 800);
            pendingTimeouts.current.set(key, timeoutId);
        } else {
            editor.update(() => {
                const node = $getNodeByKey(key);
                if ($isListItemNode(node)) {
                    node.setChecked(checked);
                    const children = node.getChildren();
                    const existing = children.find(c => $isReminderNode(c)) as ReminderNode | undefined;

                    if (checked) {
                        if (existing) {
                            existing.setData({ ...existing.getData(), completedAt: Date.now() });
                        } else {
                            node.append($createReminderNode({
                                time: 0,
                                repeatType: 'none',
                                originalTime: 0,
                                completedAt: Date.now(),
                                priority: 'none',
                                hasReminder: false,
                                hasDate: false,
                                hasTime: false,
                                uuid: crypto.randomUUID()
                            }));
                        }
                    }

                    // Recursive check/uncheck for sub-items
                    if (todo.children) {
                        todo.children.forEach(child => {
                            const childNode = $getNodeByKey(child.key);
                            if ($isListItemNode(childNode)) {
                                childNode.setChecked(checked);
                                if (checked) {
                                    const cChildren = childNode.getChildren();
                                    const cExisting = cChildren.find(c => $isReminderNode(c)) as ReminderNode | undefined;
                                    if (cExisting) {
                                        cExisting.setData({ ...cExisting.getData(), completedAt: Date.now() });
                                    } else {
                                        childNode.append($createReminderNode({
                                            time: 0,
                                            repeatType: 'none',
                                            originalTime: 0,
                                            completedAt: Date.now(),
                                            priority: 'none',
                                            hasReminder: false,
                                            hasDate: false,
                                            hasTime: false,
                                            uuid: crypto.randomUUID(),
                                            parentUuid: todo.uuid
                                        }));
                                    }
                                }
                            }
                        });
                    }
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
                case 'daily': d.setDate(d.getDate() + 1); break;
                case 'weekly': d.setDate(d.getDate() + 7); break;
                case 'monthly': d.setMonth(d.getMonth() + 1); break;
                case 'yearly': d.setFullYear(d.getFullYear() + 1); break;
                case 'weekdays':
                    const day = d.getDay();
                    if (day === 5) d.setDate(d.getDate() + 3);
                    else if (day === 6) d.setDate(d.getDate() + 2);
                    else d.setDate(d.getDate() + 1);
                    break;
            }

            nextTime = d.getTime();
            const newReminder = { ...reminder, time: nextTime, autoRefreshedAt: Date.now() };

            node.setChecked(true);
            const children = node.getChildren();
            const oldReminderNode = children.find(c => $isReminderNode(c));
            if (oldReminderNode) oldReminderNode.remove();

            node.append($createReminderNode({
                ...reminder,
                repeatType: 'none',
                completedAt: Date.now(),
            }));

            const newNode = $createListItemNode();
            newNode.setChecked(false);
            newNode.append(new TextNode(todo.text));
            newNode.append($createReminderNode(newReminder));
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

        // Trigger Date Detection
        if (detectTimer.current) clearTimeout(detectTimer.current);
        detectTimer.current = setTimeout(() => {
            detectDate(key, text);
        }, 300);
    };

    const applyDateSuggestion = () => {
        if (!detectionResult) return;
        const { id, result } = detectionResult;

        // Clear any pending debounced detectDate calls to prevent race conditions (e.g. from onBlur)
        if (detectTimer.current) {
            clearTimeout(detectTimer.current);
            detectTimer.current = null;
        }

        // Invalidate any pending requests from concurrent events (like onBlur)
        invalidateRequests(id);
        clearDetection();

        editor.update(() => {
            const node = $getNodeByKey(id);
            if ($isListItemNode(node)) {
                const children = node.getChildren();
                let reminderNode = children.find(c => $isReminderNode(c)) as ReminderNode | undefined;
                const existingData = reminderNode ? reminderNode.getData() : getDefaultReminder('all')!;
                const hasTime = result.suggestedLabel.includes(":");

                const newData: ReminderData = {
                    ...existingData,
                    time: result.date,
                    hasDate: true,
                    hasTime: hasTime,
                    repeatType: result.repeatType as any,
                    hasReminder: true
                };

                if (reminderNode) {
                    reminderNode.setData(newData);
                } else {
                    node.append($createReminderNode(newData));
                }
            }
        });
        clearDetection();
    };

    const shouldShowSuggestion = (todo: TodoItem | undefined, result: DateDetectionResult) => {
        if (!todo || !todo.reminder) return true;

        // If the reminder already has the same date, time, and repeat type, don't show it again.
        const isSameTime = Math.abs(todo.reminder.time - result.date) < 1000;
        const isSameRepeat = todo.reminder.repeatType === result.repeatType;

        return !(isSameTime && isSameRepeat && todo.reminder.hasDate);
    };

    const handlePriorityChange = (key: string, priority: 'none' | 'low' | 'medium' | 'high') => {
        editor.update(() => {
            const node = $getNodeByKey(key);
            if ($isListItemNode(node)) {
                const children = node.getChildren();
                const reminderNode = children.find(c => $isReminderNode(c)) as ReminderNode | undefined;
                if (reminderNode) {
                    reminderNode.setPriority(priority);
                } else if (priority !== 'none') {
                    node.append($createReminderNode({
                        time: 0,
                        repeatType: 'none',
                        priority,
                        hasReminder: false,
                        hasDate: false,
                        hasTime: false,
                        originalTime: 0,
                        uuid: crypto.randomUUID()
                    }));
                }
            }
        });
    };

    const getDefaultReminder = (mode: string): ReminderData => {
        const now = new Date();
        const endOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 0).getTime();
        const uuid = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : Math.random().toString(36).substring(2, 15);

        if (mode === 'today') return { time: endOfToday, repeatType: 'none', originalTime: endOfToday, priority: 'none', hasReminder: false, hasDate: true, hasTime: true, uuid };
        if (mode === 'important') return { time: 0, repeatType: 'none', originalTime: 0, priority: 'medium', hasReminder: false, hasDate: false, hasTime: false, uuid };
        if (mode === 'recurring') return { time: endOfToday, repeatType: 'daily', originalTime: endOfToday, priority: 'none', hasReminder: false, hasDate: true, hasTime: true, uuid };

        return {
            time: 0,
            repeatType: 'none',
            originalTime: 0,
            priority: 'none',
            hasReminder: false,
            hasDate: false,
            hasTime: false,
            uuid
        };
    };

    const handleMakeSubItem = useCallback(() => {
        const keysToConvert = Array.from(selectedKeys);
        if (keysToConvert.length === 0) return;

        // Find the "anchor" item - the first one in the selection based on current visual order
        // `todos` is sort of the visual order.
        const indices = keysToConvert.map(k => todos.findIndex(t => t.key === k)).filter(i => i !== -1);
        if (indices.length === 0) return;

        const minIndex = Math.min(...indices);
        const parentTodo = todos[minIndex - 1]; // The item immediately above the first selected item

        if (!parentTodo || parentTodo.isSubItem) return; // Cannot indent the first item, or indent under a sub-item (max 1 level)

        // Prevent 3-level nesting: Check if any selected item ALREADY has children.
        // If an item has children, it cannot become a sub-item.
        const keysWithChildren = new Set(todos.filter(t => t.parentUuid || t.parentKey).map(t => t.parentUuid || t.parentKey));
        const hasChildren = keysToConvert.some(key => {
            const item = todos.find(t => t.key === key);
            return item && keysWithChildren.has(item.uuid);
        });
        if (hasChildren) {
            // Maybe notify user? For now just return.
            return;
        }

        editor.update(() => {
            // Pre-pass: Ensure parentTodo has a ReminderNode/UUID
            const parentNode = $getNodeByKey(parentTodo.key);
            let finalParentUuid = parentTodo.uuid;

            if ($isListItemNode(parentNode)) {
                const pChildren = parentNode.getChildren();
                let pReminder = pChildren.find(c => $isReminderNode(c)) as ReminderNode | undefined;
                if (!pReminder) {
                    const newUuid = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : Math.random().toString(36).substring(2, 15);
                    pReminder = $createReminderNode({
                        time: 0,
                        repeatType: 'none',
                        originalTime: 0,
                        priority: 'none',
                        hasReminder: false,
                        hasDate: false,
                        hasTime: false,
                        uuid: newUuid
                    });
                    parentNode.append(pReminder);
                    finalParentUuid = newUuid;
                } else {
                    finalParentUuid = pReminder.getData().uuid;
                }
            }

            if (!finalParentUuid) return;

            keysToConvert.forEach(key => {
                const node = $getNodeByKey(key);
                if ($isListItemNode(node)) {
                    const children = node.getChildren();
                    const reminderNode = children.find(c => $isReminderNode(c)) as ReminderNode | undefined;

                    if (reminderNode) {
                        const data = reminderNode.getData();
                        reminderNode.setData({ ...data, parentUuid: finalParentUuid });
                    } else {
                        // Should rare, but create one if missing
                        const itemUuid = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : Math.random().toString(36).substring(2, 15);
                        node.append($createReminderNode({
                            time: 0,
                            repeatType: 'none',
                            parentUuid: finalParentUuid,
                            originalTime: 0,
                            priority: 'none',
                            hasReminder: false,
                            hasDate: false,
                            hasTime: false,
                            uuid: itemUuid
                        }));
                    }
                }
            });
        });
        setSelectedKeys(new Set()); // Clear selection after action? Or keep it? Usually clear or keep. Let's clear to avoid confusion.
    }, [selectedKeys, todos, editor]);

    const handleRemoveSubItem = useCallback(() => {
        const keysToRemove = Array.from(selectedKeys);
        editor.update(() => {
            keysToRemove.forEach(key => {
                const node = $getNodeByKey(key);
                if ($isListItemNode(node)) {
                    const children = node.getChildren();
                    const reminderNode = children.find(c => $isReminderNode(c)) as ReminderNode | undefined;
                    if (reminderNode) {
                        const data = reminderNode.getData();
                        const newData = { ...data };
                        delete newData.parentKey;
                        delete newData.parentUuid;
                        reminderNode.setData(newData);
                    }
                }
            });
        });
        setSelectedKeys(new Set());
    }, [selectedKeys, editor]);

    // Expose sub-item actions for Swift context menu (Moved here)
    useEffect(() => {
        (window as any).makeSubItem = handleMakeSubItem;
        (window as any).removeSubItem = handleRemoveSubItem;
        (window as any).deleteSelected = handleDeleteSelected;
    }, [handleMakeSubItem, handleRemoveSubItem, handleDeleteSelected]);

    const handleEnter = (key: string) => {
        const currentTodo = todos.find(t => t.key === key);
        const parentUuid = currentTodo?.parentUuid;
        const parentKey = currentTodo?.parentKey;

        editor.update(() => {
            const node = $getNodeByKey(key);
            if ($isListItemNode(node)) {
                const newNode = $createListItemNode();
                newNode.setChecked(false);

                // Inherit parentKey if valid
                const defaultReminder = getDefaultReminder(filterMode);
                const reminderData: any = {
                    ...defaultReminder,
                    // If defaultReminder already had a uuid (it does now), we can keep it or refresh if we want uniqueness.
                    // But getDefaultReminder generates a fresh one.
                };

                if (parentUuid || parentKey) {
                    reminderData.parentUuid = parentUuid;
                    reminderData.parentKey = parentKey;
                    // Sub-tasks forced to repeatType: 'none' per requirements?
                    reminderData.repeatType = 'none';
                }

                newNode.append($createReminderNode(reminderData as ReminderData));
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
            const defaultReminder = getDefaultReminder(filterMode);
            listItem.append($createReminderNode(defaultReminder));
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
                let existingParentUuid: string | undefined;
                let existingParentKey: string | undefined;
                children.forEach(c => {
                    if ($isReminderNode(c)) {
                        const d = c.getData();
                        existingParentUuid = d.parentUuid;
                        existingParentKey = d.parentKey;
                        c.remove();
                    }
                });
                node.append($createReminderNode({ ...data, parentUuid: existingParentUuid, parentKey: existingParentKey }));
            }
        });
    };

    const removeReminder = () => {
        if (!dialogTargetKey) return;
        editor.update(() => {
            const node = $getNodeByKey(dialogTargetKey);
            if ($isListItemNode(node)) {
                const children = node.getChildren();
                children.forEach(c => { if ($isReminderNode(c)) c.remove(); });
            }
        });
    };

    const clearCompletedTasks = (mode: 'all' | '1month' | '6months' | '1year') => {
        editor.update(() => {
            const root = $getRoot();
            const now = Date.now();
            const threshold = {
                'all': 0, '1month': 30 * 24 * 3600 * 1000,
                '6months': 180 * 24 * 3600 * 1000, '1year': 365 * 24 * 3600 * 1000
            }[mode];

            function walkAndRemove(node: LexicalNode) {
                if ($isListItemNode(node) && node.getChecked()) {
                    let shouldRemove = false;
                    if (mode === 'all') shouldRemove = true;
                    else {
                        const children = node.getChildren();
                        const reminderNode = children.find(c => $isReminderNode(c)) as ReminderNode | undefined;
                        if (reminderNode) {
                            const data = reminderNode.getData();
                            if (data.completedAt && (now - data.completedAt) > threshold) shouldRemove = true;
                        }
                    }
                    if (shouldRemove) {
                        node.remove();
                        return;
                    }
                }
                if ('getChildren' in node && typeof (node as any).getChildren === 'function') {
                    const children = [...(node as any).getChildren()];
                    children.forEach(walkAndRemove);
                }
            }
            walkAndRemove(root);
        });
    };

    const setItemRef = useCallback((key: string, el: HTMLTextAreaElement | null) => {
        itemRefs.current[key] = el;
    }, []);

    const isCompletedMode = filterMode === 'completed';
    const headerConfig: Record<string, { text: string; color: string }> = {
        all: { text: '待办事项', color: '#007aff' },
        today: { text: '今天', color: '#08bcff' },
        recurring: { text: '周期', color: '#ff3b30' },
        important: { text: '重要', color: '#ff8d30' },
        planned: { text: '计划', color: '#f7cb00' },
        completed: { text: '完成', color: '#8e8e93' }
    };
    const currentHeader = headerConfig[filterMode] || headerConfig['all'];
    const hasChildlessRoots = filterMode === 'planned' && todos.some(t => !t.isSubItem && (!t.children || t.children.length === 0));

    return (
        <div className={`todo-view ${sortMode === 'byDeadline' ? 'sorted-by-deadline' : 'sorted-manual'} ${filterMode === 'completed' ? 'completed-mode' : ''}`}>
            <div className="todo-header" style={{ color: currentHeader.color }}>
                {currentHeader.text}
                <div className="todo-subheader">
                    <div className="todo-subheader-row">
                        {isCompletedMode ? `${todos.length}条已完成事项` : `${todos.length}条待办事项`}
                        {isCompletedMode && (
                            <>
                                <span className="dot-separator">&bull;</span>
                                <DropDown
                                    buttonLabel="清除"
                                    buttonClassName="todo-clear-btn"
                                    stopCloseOnClickSelf={true}
                                    hideChevron={true}
                                >
                                    <DropDownItem className="item" onClick={() => clearCompletedTasks('1month')}>超过1个月</DropDownItem>
                                    <DropDownItem className="item" onClick={() => clearCompletedTasks('6months')}>超过6个月</DropDownItem>
                                    <DropDownItem className="item" onClick={() => clearCompletedTasks('1year')}>超过1年</DropDownItem>
                                    <DropDownItem className="item" onClick={() => clearCompletedTasks('all')}>所有已完成事项</DropDownItem>
                                </DropDown>
                            </>
                        )}
                    </div>
                    {hasChildlessRoots && (
                        <div className="todo-warning-msg">
                            未设置“子事项”的待办事项稍后会被移动到“全部待办事项”
                        </div>
                    )}
                </div>
            </div>

            <div className="todo-list">
                {todos.map(todo => (
                    <TodoItemRow
                        key={todo.key}
                        todo={optimisticIds.has(todo.key) ? { ...todo, checked: true } : todo}
                        isCompletedMode={isCompletedMode}
                        isRinging={ringingBells.has(todo.key)}
                        registerRef={setItemRef}
                        onToggle={(checked) => handleToggle(todo.key, checked, todo)}
                        onTextChange={handleTextChange}
                        onPriorityChange={handlePriorityChange}
                        onEnter={handleEnter}
                        onDelete={handleDelete}
                        onOpenReminder={() => openReminderSettings(todo.key, todo.reminder)}
                        isSelected={selectedKeys.has(todo.key)}
                        isClosing={closingKeys.has(todo.key)}
                        onRowClick={(e) => handleRowClick(todo.key, e)}
                        highlightRange={
                            (!todo.checked && detectionResult && detectionResult.id === todo.key && shouldShowSuggestion(todo, detectionResult.result))
                                ? detectionResult.result.range
                                : undefined
                        }
                    />
                ))}
                {todos.length === 0 ? (
                    <div className="todo-empty" onClick={handleCreateFirst}>
                        点击空白处添加待办事项
                    </div>
                ) : filterMode !== 'completed' && (
                    <div className="todo-fill-area" onClick={() => {
                        const emptyDraft = todos.find(t => t.text === "");
                        if (emptyDraft) {
                            handleDelete(emptyDraft.key);
                        } else {
                            editor.update(() => {
                                const root = $getRoot();
                                let lastListItem: ListItemNode | null = null;
                                function findLastListItem(node: LexicalNode) {
                                    if ($isListItemNode(node)) {
                                        const parent = node.getParent();
                                        if ($isListNode(parent) && parent.getListType() === 'check') {
                                            lastListItem = node;
                                        }
                                    }
                                    if ('getChildren' in node && typeof (node as any).getChildren === 'function') {
                                        (node as any).getChildren().forEach(findLastListItem);
                                    }
                                }
                                findLastListItem(root);

                                if (lastListItem) {
                                    const newNode = $createListItemNode();
                                    newNode.setChecked(false);
                                    const defaultReminder = getDefaultReminder(filterMode);
                                    newNode.append($createReminderNode(defaultReminder));
                                    lastListItem.insertAfter(newNode);
                                    pendingFocusKey.current = newNode.getKey();
                                } else {
                                    handleCreateFirst();
                                }
                            });
                        }
                    }}>
                    </div>
                )}
            </div>

            <TodoDetailsPanel
                key={dialogTargetKey || 'new'}
                isOpen={isDialogOpen}
                initialData={dialogInitialData}
                onClose={() => setIsDialogOpen(false)}
                onSave={saveReminder}
            />

            {detectionResult && shouldShowSuggestion(todos.find(t => t.key === detectionResult.id), detectionResult.result) && (
                <DateSuggestionPopup
                    result={detectionResult.result}
                    targetRef={itemRefs.current[detectionResult.id]}
                    onApply={applyDateSuggestion}
                />
            )}


        </div>
    );
};

interface RowProps {
    todo: TodoItem;
    registerRef: (key: string, el: HTMLTextAreaElement | null) => void;
    onToggle: (checked: boolean) => void;
    onTextChange: (key: string, text: string) => void;
    onPriorityChange: (key: string, priority: 'none' | 'low' | 'medium' | 'high') => void;
    onEnter: (key: string, e: React.KeyboardEvent) => void;
    onDelete: (key: string) => void;
    onOpenReminder: () => void;
    isCompletedMode: boolean;
    isRinging: boolean;
    highlightRange?: [number, number] | undefined;
    isSelected?: boolean;
    isClosing?: boolean;
    onRowClick?: (e: React.MouseEvent) => void;
}

function TodoItemRow({ todo, registerRef, onToggle, onTextChange, onPriorityChange, onEnter, onDelete, onOpenReminder, isCompletedMode, isRinging, highlightRange, isSelected, isClosing, onRowClick }: RowProps) {
    const textareaRef = useRef<HTMLTextAreaElement>(null);
    const [localText, setLocalText] = useState(todo.text);
    const isComposing = useRef(false);
    const [showShimmer, setShowShimmer] = useState(false);

    useEffect(() => {
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
            onToggle(true);
        } else {
            onToggle(false);
        }
    };

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            if (todo.checked || isCompletedMode) return;
            if (localText === '') onDelete(todo.key);
            else onEnter(todo.key, e);
        } else if (e.key === 'Backspace') {
            const prefix = getPriorityPrefix() || '';
            if (prefix && textareaRef.current &&
                textareaRef.current.selectionStart === prefix.length &&
                textareaRef.current.selectionEnd === prefix.length) {
                e.preventDefault();
                const currentPriority = todo.reminder?.priority || 'none';
                let nextPriority: 'none' | 'low' | 'medium' | 'high' = 'none';
                if (currentPriority === 'high') nextPriority = 'medium';
                else if (currentPriority === 'medium') nextPriority = 'low';
                else if (currentPriority === 'low') nextPriority = 'none';
                onPriorityChange(todo.key, nextPriority);
                return;
            }
            if (localText === '') {
                e.preventDefault();
                onDelete(todo.key);
            }
        }
    };

    const getMetaInfo = () => {
        if (!todo.reminder) return null;
        const r = todo.reminder;
        if (!r.hasDate && !r.hasTime && r.repeatType === 'none') return null;

        const d = new Date(r.time);
        const now = new Date();
        // const isOverdue = r.hasDate && now.getTime() > r.time; // Calculated outside

        const m = d.getMonth() + 1;
        const day = d.getDate();
        const h = String(d.getHours()).padStart(2, '0');
        const min = String(d.getMinutes()).padStart(2, '0');

        const todayDate = new Date();
        todayDate.setHours(0, 0, 0, 0);
        const tomorrowDate = new Date(todayDate);
        tomorrowDate.setDate(todayDate.getDate() + 1);

        const targetDate = new Date(r.time);
        targetDate.setHours(0, 0, 0, 0);

        let dateLabel = `${m}月${day}日`;
        if (targetDate.getTime() === todayDate.getTime()) {
            dateLabel = '今天';
        } else if (targetDate.getTime() === tomorrowDate.getTime()) {
            dateLabel = '明天';
        }

        let timeStr = '';
        if (r.hasDate) {
            if (r.hasTime) timeStr = `${dateLabel} ${h}:${min}`;
            else timeStr = dateLabel;
        } else if (r.hasTime) {
            timeStr = `${h}:${min}`;
        }

        const isOverdue = r.hasDate && now.getTime() > r.time && !todo.checked && r.repeatType === 'none';

        let cycleStr = '';
        if (isOverdue) cycleStr = '已过期';
        else {
            const map: Record<string, string> = {
                'none': '', 'daily': '每天', 'weekdays': '工作日',
                'weekly': '每周', 'monthly': '每月', 'yearly': '每年'
            };
            cycleStr = map[r.repeatType] || '';
            if (r.repeatType === 'none' && (r.hasDate || r.hasTime)) cycleStr = '一次性';
        }

        if (!cycleStr && !timeStr) return null;
        if (!cycleStr) return timeStr;
        if (!timeStr) return cycleStr;
        return `${timeStr}，${cycleStr}`;
    };

    const getPriorityPrefix = () => {
        if (!todo.reminder) return null;
        switch (todo.reminder.priority) {
            case 'high': return '!!! ';
            case 'medium': return '!! ';
            case 'low': return '! ';
            default: return null;
        }
    };

    // New: Calculate Progress
    const progress = (() => {
        if (!todo.children || todo.children.length === 0) return null;
        const total = todo.children.length;
        const completed = todo.children.filter(c => c.checked).length;
        return { total, completed };
    })();

    // New: Invalid Deadline Warning Logic
    const deadlineWarning = (() => {
        // Placeholder for future logic if needed
        return todo.deadlineInvalid ? "截止时间不合理" : null;
    })();

    const metaText = getMetaInfo();
    const isOverdue = todo.reminder && todo.reminder.hasDate && new Date().getTime() > todo.reminder.time && !todo.checked && todo.reminder.repeatType === 'none';

    const renderMirrorContent = () => {
        const prefix = getPriorityPrefix() || '';
        const fullText = (prefix + (localText || ""));

        if (!highlightRange) {
            return <>{(fullText || '\u00A0') + "\n"}</>;
        }

        const start = highlightRange[0] + prefix.length;
        const len = highlightRange[1];

        if (start < 0 || start >= fullText.length) return <>{fullText + "\n"}</>;

        const before = fullText.slice(0, start);
        const match = fullText.slice(start, start + len);
        const after = fullText.slice(start + len);

        return (
            <>
                {before}
                <span style={{ color: '#007aff' }}>{match}</span>
                {after || (fullText === "" ? '\u00A0' : '')}
                {"\n"}
            </>
        );
    };

    return (
        <div
            className={`todo-row ${todo.checked ? 'completed' : ''} ${todo.reminder ? 'has-reminder' : ''} ${isSelected ? 'selected' : ''} ${todo.isSubItem ? 'sub-item' : ''}`}
            data-todo-key={todo.key}
            onClick={onRowClick}
            style={{
                transform: isClosing ? 'scale(0.95)' : 'scale(1)',
                opacity: isClosing ? 0 : 1,
                transition: 'opacity 0.3s ease-out, transform 0.3s ease-out, height 0.3s ease-out 0.1s, min-height 0.3s ease-out 0.1s, padding 0.3s ease-out 0.1s',
                height: isClosing ? 0 : 'auto',
                minHeight: 0,
                paddingTop: isClosing ? 0 : 7,
                paddingBottom: isClosing ? 0 : 7,
                display: 'flex',
                alignItems: 'flex-start',
                overflow: 'hidden',
                backgroundColor: isSelected ? 'rgba(0, 122, 255, 0.1)' : 'transparent'
            }}
        >
            <div className="todo-checkbox-wrapper">
                <input
                    type="checkbox"
                    className={`todo-checkbox ${(!localText && !todo.checked) ? 'draft' : ''} ${(isCompletedMode && todo.isSubItem) ? 'sub-item-disabled' : ''}`}
                    checked={todo.checked}
                    onChange={handleCheckboxChange}
                    disabled={isCompletedMode && todo.isSubItem}
                />
            </div>

            <div className="todo-content-wrapper">
                <div className="todo-input-mirror-container">
                    <div
                        className="todo-input-mirror"
                        aria-hidden="true"
                        style={{
                            visibility: 'visible',
                            color: 'inherit',
                            zIndex: 0,
                            pointerEvents: 'none'
                        }}
                    >
                        {renderMirrorContent()}
                    </div>

                    <textarea
                        ref={el => {
                            textareaRef.current = el;
                            if (registerRef) registerRef(todo.key, el);
                        }}
                        className="todo-input"
                        rows={1}
                        data-priority={getPriorityPrefix() ? 'true' : 'false'}
                        value={(getPriorityPrefix() || '') + localText}
                        onChange={(e) => {
                            const val = e.target.value;
                            const prefix = getPriorityPrefix() || '';
                            let newText = val;
                            if (val.startsWith(prefix)) {
                                newText = val.substring(prefix.length);
                            }
                            setLocalText(newText);
                            if (!isComposing.current) onTextChange(todo.key, newText);
                        }}
                        onCompositionStart={() => isComposing.current = true}
                        onCompositionEnd={(e) => {
                            isComposing.current = false;
                            const val = (e.target as any).value;
                            const prefix = getPriorityPrefix() || '';
                            let newText = val;
                            if (val.startsWith(prefix)) {
                                newText = val.substring(prefix.length);
                            }
                            onTextChange(todo.key, newText);
                        }}
                        onKeyDown={handleKeyDown}
                        onMouseDown={(e) => {
                            if (e.shiftKey || e.metaKey || e.ctrlKey) {
                                e.preventDefault();
                            }
                        }}
                        onBlur={() => onTextChange(todo.key, localText)}
                        placeholder="输入待办事项"
                        spellCheck={false}
                        readOnly={todo.checked || isCompletedMode}
                        style={{
                            color: highlightRange ? 'transparent' : 'inherit',
                            caretColor: 'var(--text-color, #1a1a1a)'
                        }}
                    />
                </div>

                {(metaText || progress || deadlineWarning) && (
                    <div className={`todo-meta-info ${isOverdue ? 'overdue' : ''} ${showShimmer ? 'shimmer' : ''}`}>
                        {metaText}

                        {deadlineWarning && (
                            <span className="deadline-warning">{deadlineWarning}</span>
                        )}

                        {progress && (
                            <div className="todo-progress-indicator">
                                <span>进度 {progress.completed}/{progress.total}</span>
                                <div className="todo-progress-bar">
                                    <div
                                        className="todo-progress-bar-fill"
                                        style={{ width: `${(progress.completed / progress.total) * 100}%` }}
                                    />
                                </div>
                            </div>
                        )}
                    </div>
                )}
            </div>

            <div className="todo-icon-group">
                {!isCompletedMode && localText.trim() !== '' && (
                    <div className={`info-btn ${todo.reminder?.hasReminder ? 'has-reminder' : ''}`} onClick={onOpenReminder}>
                        {todo.reminder?.hasReminder && (
                            <div className={`bell-ripple-container ${isRinging ? 'bell-ringing' : ''}`}>
                                <svg className="bell-icon-display" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                                    <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path>
                                    <path className="bell-clapper" d="M13.73 21a2 2 0 0 1-3.46 0"></path>
                                </svg>
                                {isRinging && (
                                    <>
                                        <span className="bell-ripple"></span>
                                        <span className="bell-ripple"></span>
                                        <span className="bell-ripple"></span>
                                    </>
                                )}
                            </div>
                        )}
                        <svg className="info-icon-display" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                            <circle cx="12" cy="12" r="10"></circle>
                            <line x1="12" y1="16" x2="12" y2="12"></line>
                            <line x1="12" y1="8" x2="12.01" y2="8"></line>
                        </svg>
                    </div>
                )}
            </div>
        </div >
    );
}
