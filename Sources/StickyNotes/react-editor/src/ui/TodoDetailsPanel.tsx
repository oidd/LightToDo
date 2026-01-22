
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
    const [hasDate, setHasDate] = useState(false);
    const [hasTime, setHasTime] = useState(false);
    const [hasReminder, setHasReminder] = useState(false);
    const [date, setDate] = useState('');
    const [time, setTime] = useState('');
    const [repeatType, setRepeatType] = useState<RepeatType>('none');
    const [priority, setPriority] = useState<'none' | 'low' | 'medium' | 'high'>('none');

    // Expansion states
    const [isDateExpanded, setIsDateExpanded] = useState(false);
    const [isTimeExpanded, setIsTimeExpanded] = useState(false);

    useEffect(() => {
        if (isOpen) {
            if (initialData) {
                setHasDate(initialData.hasDate || false);
                setHasTime(initialData.hasTime || false);
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
                setHasDate(false);
                setHasTime(false);
                setHasReminder(false);
                setPriority('none');
                setRepeatType('none');
                const d = new Date();
                d.setHours(d.getHours() + 1, 0, 0, 0);
                setDate(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`);
                setTime(`${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`);
            }
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
            hasDate,
            hasTime
        });
    };

    // Auto-save on any change
    useEffect(() => {
        if (isOpen) {
            handleSave();
        }
    }, [hasReminder, hasDate, hasTime, date, time, repeatType, priority]);

    if (!isOpen) return null;

    const formatDateDisplay = (dateStr: string) => {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        const weekdays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
        return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 ${weekdays[d.getDay()]}`;
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

    // Handle close: if time is on but date is off, auto-enable date with today's value
    const handleClose = () => {
        if (hasTime && !hasDate) {
            // Auto-enable date and set it to today
            const today = new Date();
            const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
            setHasDate(true);
            setDate(todayStr);
            // Save with the updated values
            let timestamp = 0;
            if (todayStr && time) {
                timestamp = new Date(`${todayStr}T${time}:00`).getTime();
            }
            onSave({
                time: timestamp,
                repeatType,
                originalTime: timestamp,
                priority,
                hasReminder,
                hasDate: true,
                hasTime
            });
        }
        onClose();
    };

    return (
        <div className="todo-details-panel-overlay" onClick={handleClose}>
            <div className="todo-details-panel apple-style" onClick={e => e.stopPropagation()}>
                {/* Date Section */}
                <div className={`panel-section ${isDateExpanded ? 'expanded' : ''}`}>
                    <div className="panel-row clickable" onClick={() => hasDate && setIsDateExpanded(!isDateExpanded)}>
                        <div className="panel-icon-box date-bg">
                            <span className="panel-icon calendar-icon"></span>
                        </div>
                        <div className="panel-label-group">
                            <span className="panel-label">日期</span>
                            {hasDate && (
                                <span className="panel-sub-label" style={{ display: isDateExpanded ? 'none' : 'block' }}>
                                    {formatDateDisplay(date)}
                                </span>
                            )}
                        </div>
                        <Switch
                            text=""
                            checked={hasDate}
                            onClick={(e) => {
                                e.stopPropagation();
                                const newState = !hasDate;
                                setHasDate(newState);
                                if (newState) setIsDateExpanded(true);
                                else setIsDateExpanded(false);
                            }}
                        />
                    </div>
                    {hasDate && isDateExpanded && (
                        <div className="panel-expanded-picker">
                            <input
                                type="date"
                                autoFocus
                                className="apple-date-picker"
                                value={date}
                                onChange={e => setDate(e.target.value)}
                            />
                        </div>
                    )}
                </div>

                {/* Time Section */}
                <div className={`panel-section ${isTimeExpanded ? 'expanded' : ''}`}>
                    <div className="panel-row clickable" onClick={() => hasTime && setIsTimeExpanded(!isTimeExpanded)}>
                        <div className="panel-icon-box time-bg">
                            <span className="panel-icon clock-icon"></span>
                        </div>
                        <div className="panel-label-group">
                            <span className="panel-label">时间</span>
                            {hasTime && (
                                <span className="panel-sub-label" style={{ display: isTimeExpanded ? 'none' : 'block' }}>
                                    {time}
                                </span>
                            )}
                        </div>
                        <Switch
                            text=""
                            checked={hasTime}
                            onClick={(e) => {
                                e.stopPropagation();
                                const newState = !hasTime;
                                setHasTime(newState);
                                if (newState) setIsTimeExpanded(true);
                                else setIsTimeExpanded(false);
                            }}
                        />
                    </div>
                    {hasTime && isTimeExpanded && (
                        <div className="panel-expanded-picker">
                            <input
                                type="time"
                                autoFocus
                                className="apple-time-picker"
                                value={time}
                                onChange={e => setTime(e.target.value)}
                            />
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
                        </div>
                        <Switch
                            text=""
                            checked={hasReminder}
                            onClick={() => setHasReminder(!hasReminder)}
                        />
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
