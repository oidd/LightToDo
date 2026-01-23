
import React, { useState, useEffect } from 'react';
import { ReminderData, RepeatType } from '../nodes/ReminderNode';
import Switch from './Switch';

interface TodoDetailsPanelProps {
    isOpen: boolean;
    initialData?: ReminderData;
    onClose: () => void;
    onSave: (data: ReminderData) => void;
}

export default function TodoDetailsPanel({ isOpen, initialData, onClose, onSave }: TodoDetailsPanelProps) {
    const [hasDateTime, setHasDateTime] = useState(false);
    const [hasReminder, setHasReminder] = useState(false);
    const [date, setDate] = useState('');
    const [time, setTime] = useState('');
    const [repeatType, setRepeatType] = useState<RepeatType>('none');
    const [priority, setPriority] = useState<'none' | 'low' | 'medium' | 'high'>('none');
    const [reminderError, setReminderError] = useState('');

    // Expansion state for the combined DateTime picker
    const [isDateTimeExpanded, setIsDateTimeExpanded] = useState(false);

    useEffect(() => {
        if (isOpen) {
            if (initialData) {
                const hasAny = initialData.hasDate || initialData.hasTime || false;
                setHasDateTime(hasAny);
                setHasReminder(initialData.hasReminder || false);
                setPriority(initialData.priority || 'none');
                setRepeatType(initialData.repeatType || 'none');

                if (initialData.time > 0) {
                    const d = new Date(initialData.time);
                    setDate(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`);
                    setTime(`${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`);
                } else {
                    const d = new Date();
                    d.setHours(d.getHours() + 1, 0, 0, 0);
                    setDate(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`);
                    setTime(`${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`);
                }
            } else {
                setHasDateTime(false);
                setHasReminder(false);
                setPriority('none');
                setRepeatType('none');
                const d = new Date();
                d.setHours(d.getHours() + 1, 0, 0, 0);
                setDate(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`);
                setTime(`${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`);
            }
            // Reset expansion on open
            setIsDateTimeExpanded(false);
        }
    }, [isOpen, initialData]);

    const handleSave = () => {
        let timestamp = 0;
        if (date && time) {
            timestamp = new Date(`${date}T${time}:00`).getTime();
        }

        onSave({
            time: timestamp,
            repeatType,
            originalTime: timestamp,
            priority,
            hasReminder,
            hasDate: hasDateTime,
            hasTime: hasDateTime
        });
    };

    // Auto-save on any change
    useEffect(() => {
        if (isOpen) {
            handleSave();
        }
    }, [hasReminder, hasDateTime, date, time, repeatType, priority]);

    if (!isOpen) return null;

    const formatDateDisplay = (dateStr: string) => {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        const weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
        return `${d.getMonth() + 1}月${d.getDate()}日 ${weekdays[d.getDay()]}`;
    };

    const formatTimeDisplay = (timeStr: string) => {
        if (!timeStr) return '';
        return timeStr;
    };

    const getRepeatOptions = () => {
        const d = new Date(date || Date.now());
        const weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
        const dayOfWeek = weekdays[d.getDay()];
        const dayOfMonth = d.getDate();
        const month = d.getMonth() + 1;

        return [
            { value: 'none', label: '一次性' },
            { value: 'daily', label: '每天' },
            { value: 'weekdays', label: '工作日' },
            { value: 'weekly', label: `每周（${dayOfWeek}）` },
            { value: 'monthly', label: `每月（${dayOfMonth}日）` },
            { value: 'yearly', label: `每年（${month}月${dayOfMonth}日）` }
        ];
    };

    // Handle close: auto-complete if needed
    const handleClose = () => {
        onClose();
    };

    // Confirm button handler for DateTime picker
    const handleDateTimeConfirm = () => {
        setIsDateTimeExpanded(false);
    };

    return (
        <div className="todo-details-panel-overlay" onClick={handleClose}>
            <div className="todo-details-panel apple-style" onClick={e => e.stopPropagation()}>
                {/* Combined Date & Time Section */}
                <div className={`panel-section ${isDateTimeExpanded ? 'expanded' : ''}`}>
                    <div className="panel-row clickable" onClick={() => hasDateTime && setIsDateTimeExpanded(!isDateTimeExpanded)}>
                        <div className="panel-icon-box datetime-bg">
                            <span className="panel-icon calendar-clock-icon"></span>
                        </div>
                        <div className="panel-label-group">
                            <span className="panel-label">日期与时间</span>
                            {hasDateTime && !isDateTimeExpanded && (
                                <span className="panel-sub-label">
                                    {formatDateDisplay(date)} {formatTimeDisplay(time)}
                                </span>
                            )}
                        </div>
                        <Switch
                            text=""
                            checked={hasDateTime}
                            onClick={(e) => {
                                e.stopPropagation();
                                const newState = !hasDateTime;
                                setHasDateTime(newState);
                                if (newState) setIsDateTimeExpanded(true);
                                else {
                                    setIsDateTimeExpanded(false);
                                    setHasReminder(false);
                                    setReminderError('');
                                }
                            }}
                        />
                    </div>
                    {hasDateTime && isDateTimeExpanded && (
                        <div className="panel-datetime-picker">
                            <div className="datetime-picker-row">
                                <label className="datetime-label">日期</label>
                                <input
                                    type="date"
                                    className="datetime-input"
                                    value={date}
                                    onChange={e => setDate(e.target.value)}
                                />
                            </div>
                            <div className="datetime-picker-row">
                                <label className="datetime-label">时间</label>
                                <input
                                    type="time"
                                    className="datetime-input"
                                    value={time}
                                    onChange={e => setTime(e.target.value)}
                                />
                            </div>
                            <div className="datetime-footer">
                                <button className="datetime-confirm-btn" onClick={handleDateTimeConfirm}>
                                    确定
                                </button>
                            </div>
                        </div>
                    )}
                </div>

                {/* Reminder Toggle */}
                <div className="panel-section">
                    <div className="panel-row">
                        <div className="panel-icon-box reminder-bg">
                            <span className="panel-icon bell-icon"></span>
                        </div>
                        <div className="panel-label-group">
                            <span className="panel-label">提醒</span>
                            {reminderError && (
                                <span className="panel-error-text">{reminderError}</span>
                            )}
                        </div>
                        <div className="panel-actions">
                            {hasReminder && (
                                <button
                                    className="panel-preview-btn-circle"
                                    title="预览提醒效果"
                                    onClick={(e) => {
                                        e.stopPropagation();
                                        if (window.webkit?.messageHandlers?.editor) {
                                            window.webkit.messageHandlers.editor.postMessage({ type: 'previewReminder' });
                                        }
                                    }}
                                >
                                    <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M8 5v14l11-7z" />
                                    </svg>
                                </button>
                            )}
                            <Switch
                                text=""
                                checked={hasReminder}
                                onClick={() => {
                                    if (!hasReminder) {
                                        if (!hasDateTime) {
                                            setReminderError('请先设置日期和时间');
                                            // Auto-clear after 2 seconds
                                            setTimeout(() => setReminderError(''), 2000);
                                            return;
                                        }
                                    }
                                    setReminderError('');
                                    setHasReminder(!hasReminder);
                                }}
                            />
                        </div>
                    </div>
                </div>

                <div className="panel-divider"></div>

                {/* Repeat Section */}
                <div className="panel-section">
                    <div className="panel-row">
                        <div className="panel-icon-box repeat-bg">
                            <span className="panel-icon repeat-icon"></span>
                        </div>
                        <div className="panel-label-group">
                            <span className="panel-label">重复周期</span>
                        </div>
                        <select
                            className="apple-select"
                            value={repeatType}
                            onChange={e => setRepeatType(e.target.value as RepeatType)}
                        >
                            {getRepeatOptions().map(opt => (
                                <option key={opt.value} value={opt.value}>{opt.label}</option>
                            ))}
                        </select>
                    </div>
                </div>

                {/* Priority Section */}
                <div className="panel-section">
                    <div className="panel-row">
                        <div className="panel-icon-box priority-bg">
                            <span className="panel-icon priority-icon"></span>
                        </div>
                        <div className="panel-label-group">
                            <span className="panel-label">优先级</span>
                        </div>
                        <select
                            className="apple-select"
                            value={priority}
                            onChange={e => setPriority(e.target.value as any)}
                        >
                            <option value="none">无</option>
                            <option value="low">低</option>
                            <option value="medium">中</option>
                            <option value="high">高</option>
                        </select>
                    </div>
                </div>

                <div className="panel-footer">
                    <button className="apple-done-btn" onClick={handleClose}>完成</button>
                </div>
            </div>
        </div>
    );
}
