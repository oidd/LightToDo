
import React, { useState, useEffect } from 'react';
import { ReminderData, RepeatType } from '../nodes/ReminderNode';

interface ReminderSettingsDialogProps {
    isOpen: boolean;
    initialData?: ReminderData;
    onClose: () => void;
    onSave: (data: ReminderData) => void;
}

export default function ReminderSettingsDialog({ isOpen, initialData, onClose, onSave, onRemove }: ReminderSettingsDialogProps & { onRemove?: () => void }) {
    if (!isOpen) return null;

    // Default to nearest next hour if no initial data
    const getDefaultTime = () => {
        const now = new Date();
        now.setMinutes(0);
        now.setSeconds(0);
        now.setHours(now.getHours() + 1);
        return now;
    };

    const [date, setDate] = useState('');
    const [time, setTime] = useState('');
    const [repeatType, setRepeatType] = useState<RepeatType>('none');

    useEffect(() => {
        if (isOpen) {
            let d: Date;
            if (initialData) {
                d = new Date(initialData.time);
                setRepeatType(initialData.repeatType);
            } else {
                d = getDefaultTime();
                setRepeatType('none');
            }
            // Format YYYY-MM-DD
            const yyyy = d.getFullYear();
            const mm = String(d.getMonth() + 1).padStart(2, '0');
            const dd = String(d.getDate()).padStart(2, '0');
            setDate(`${yyyy}-${mm}-${dd}`);

            // Format HH:mm
            const hh = String(d.getHours()).padStart(2, '0');
            const min = String(d.getMinutes()).padStart(2, '0');
            setTime(`${hh}:${min}`);
        }
    }, [isOpen, initialData]);

    const getWeekDay = (dateStr: string) => {
        const d = new Date(dateStr);
        const days = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
        return days[d.getDay()];
    };

    const getDayOfMonth = (dateStr: string) => {
        const d = new Date(dateStr);
        return `${d.getDate()}日`;
    };

    const getDateOfYear = (dateStr: string) => {
        const d = new Date(dateStr);
        return `${d.getMonth() + 1}月${d.getDate()}日`;
    };

    // Calculate dynamic labels
    const weekDayLabel = date ? `每周 (${getWeekDay(date)})` : '每周';
    const monthDayLabel = date ? `每月 (${getDayOfMonth(date)})` : '每月';
    const yearDayLabel = date ? `每年 (${getDateOfYear(date)})` : '每年';

    const handleSave = () => {
        if (!date || !time) return;
        const dateTimeStr = `${date}T${time}:00`;
        const timestamp = new Date(dateTimeStr).getTime();

        onSave({
            time: timestamp,
            repeatType,
            originalTime: timestamp
        });
        onClose();
    };

    return (
        <div className="reminder-dialog-overlay" onClick={onClose}>
            <div className="reminder-dialog" onClick={e => e.stopPropagation()}>
                {/* Header removed per request */}

                <div className="reminder-dialog-body">
                    <div className="form-group">
                        <div className="form-header">
                            <label className="dialog-label">提醒时间</label>
                            <span className="datetime-preview">
                                {date && time ? (() => {
                                    const d = new Date(`${date}T${time}:00`);
                                    const m = d.getMonth() + 1;
                                    const day = d.getDate();
                                    const wd = getWeekDay(date);
                                    const h = String(d.getHours()).padStart(2, '0');
                                    const min = String(d.getMinutes()).padStart(2, '0');
                                    return `${m}月${day}日 ${wd} ${h}时${min}分`;
                                })() : ''}
                            </span>
                        </div>
                        <div className="datetime-inputs">
                            <input
                                type="date"
                                className="date-input"
                                value={date}
                                onChange={e => setDate(e.target.value)}
                            />
                            <input
                                type="time"
                                className="time-input"
                                value={time}
                                onChange={e => setTime(e.target.value)}
                            />
                        </div>
                    </div>

                    <div className="form-group">
                        <label className="dialog-label">重复周期</label>
                        <select
                            value={repeatType}
                            onChange={e => setRepeatType(e.target.value as RepeatType)}
                        >
                            <option value="none">仅一次</option>
                            <option value="daily">每天</option>
                            <option value="weekdays">工作日 (周一至周五)</option>
                            <option value="weekly">{weekDayLabel}</option>
                            <option value="monthly">{monthDayLabel}</option>
                            <option value="yearly">{yearDayLabel}</option>
                        </select>
                    </div>

                    <div className="form-group">
                        <label className="dialog-label">提醒方式</label>
                        <div className="radio-group">
                            <label className="radio-option selected">
                                <input type="radio" checked readOnly />
                                <span>波纹</span>
                            </label>
                            {/* Dev option removed per request */}
                        </div>
                    </div>
                </div>

                <div className="reminder-dialog-footer">
                    {initialData && onRemove && (
                        <button className="btn-remove" onClick={() => {
                            onRemove();
                            onClose();
                        }}>移除提醒</button>
                    )}
                    <div style={{ flex: 1 }}></div>
                    <button className="btn-cancel" onClick={onClose}>取消</button>
                    <button className="btn-save" onClick={handleSave}>确定</button>
                </div>
            </div>
        </div>
    );
}
