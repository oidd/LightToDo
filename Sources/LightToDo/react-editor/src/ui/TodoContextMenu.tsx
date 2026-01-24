import React from 'react';
import { TodoItem } from './TodoView';

interface ContextMenuProps {
    x: number;
    y: number;
    selectedKeys: Set<string>;
    todos: TodoItem[];
    filterMode: string;
    onClose: () => void;
    onDelete: () => void;
    onMakeSubItem: () => void;
    onRemoveSubItem: () => void;
}

export default function TodoContextMenu({
    x,
    y,
    selectedKeys,
    todos,
    filterMode,
    onClose,
    onDelete,
    onMakeSubItem,
    onRemoveSubItem
}: ContextMenuProps) {
    const isAllMode = filterMode === 'all';
    const keysArray = Array.from(selectedKeys);

    // Check if we can make sub-item
    // 1. Must be in 'all' mode
    // 2. Must not select the very first visible item (cannot indent first item)
    // 3. Selection must not already be sub-items? The requirement says:
    // "设为上一条的子事项”只能在用户选择除第一条待办事项外的其他待办事项，才能选择"
    // And ideally they should be contiguous? Or we just indent them under their respective predecessors?
    // User req: "设为上一条的子事项".

    // Let's implement robust check:
    // At least one selected item must have a predecessor that is NOT in the selection (to be the parent).
    // Or simplified: Just check if the first selected item is NOT the first item in the list.

    const firstSelectedIndex = todos.findIndex(t => t.key === keysArray[0]);
    const isFirstItem = firstSelectedIndex === 0;

    // Also check if any selected item is already a sub-item?
    // "默认情况下...不可点击"
    // "只能在用户选择除第一条...才能选择"
    // If it's already a sub-item, can it be a sub-sub-item? No, only 1 level.
    const hasExistingSubItems = keysArray.some(k => todos.find(t => t.key === k)?.isSubItem);

    const canMakeSubItem = isAllMode && !isFirstItem && !hasExistingSubItems;

    // Check if we can remove sub-item
    // "用户在某条子事项或者选中多条子事项后右击，“移出子事项”从灰色变为可点击状态"
    // So all selected must be sub-items? Or at least one?
    // Usually "Remove Sub-item" works if ANY or ALL are sub-items.
    // Let's go with: if any selected item is a sub-item, enable it.
    const hasSubItems = keysArray.some(k => todos.find(t => t.key === k)?.isSubItem);
    const canRemoveSubItem = isAllMode && hasSubItems;

    return (
        <>
            <div className="todo-context-menu-overlay" onClick={onClose} />
            <div
                className="todo-context-menu"
                style={{
                    left: Math.min(x, window.innerWidth - 220),
                    top: Math.min(y, window.innerHeight - 150)
                }}
            >
                <div
                    className={`menu-item ${!canMakeSubItem ? 'disabled' : ''}`}
                    onClick={() => { if (canMakeSubItem) { onMakeSubItem(); onClose(); } }}
                >
                    设为上一条的子事项
                </div>
                <div
                    className={`menu-item ${!canRemoveSubItem ? 'disabled' : ''}`}
                    onClick={() => { if (canRemoveSubItem) { onRemoveSubItem(); onClose(); } }}
                >
                    移出子事项
                </div>
                <div className="menu-divider" />
                <div
                    className="menu-item delete"
                    onClick={() => { onDelete(); onClose(); }}
                >
                    删除
                </div>
            </div>
        </>
    );
}
