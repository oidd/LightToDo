import React, { useEffect, useState, useRef } from 'react';

export interface DateDetectionResult {
    matchedText: String;
    date: number; // ms
    range: [number, number]; // [location, length]
    repeatType: string;
    suggestedLabel: string;
}

export const useDateDetection = () => {
    const [detectionResult, setDetectionResult] = useState<{ id: string, result: DateDetectionResult } | null>(null);
    const requestMap = useRef<Map<string, number>>(new Map());

    useEffect(() => {
        // Register global callback for Swift
        (window as any).onDateDetected = (compositeId: string, jsonResult: string | null) => {
            if (!compositeId) return;

            // Parse composite ID "key|counter"
            const parts = compositeId.split('|');
            if (parts.length !== 2) return;

            const key = parts[0];
            const counter = parseInt(parts[1], 10);

            // Check if this is the latest request for this key
            const latest = requestMap.current.get(key);
            if (latest !== counter) {
                // Stale response, ignore
                return;
            }

            if (!jsonResult) {
                setDetectionResult(null);
                return;
            }
            try {
                const result = JSON.parse(jsonResult) as DateDetectionResult;
                setDetectionResult({ id: key, result });
            } catch (e) {
                console.error("Failed to parse date result", e);
                setDetectionResult(null);
            }
        };

        return () => {
            (window as any).onDateDetected = undefined;
        };
    }, []);

    const detectDate = (id: string, text: string) => {
        // Increment counter
        const next = (requestMap.current.get(id) || 0) + 1;
        requestMap.current.set(id, next);
        const compositeId = `${id}|${next}`;

        if (window.webkit?.messageHandlers?.editor) {
            window.webkit.messageHandlers.editor.postMessage({
                type: 'detectDate',
                id: compositeId,
                text: text
            });
        }
    };

    const invalidateRequests = (id: string) => {
        const next = (requestMap.current.get(id) || 0) + 1;
        requestMap.current.set(id, next);
    };

    return {
        detectionResult,
        detectDate,
        clearDetection: () => setDetectionResult(null),
        invalidateRequests
    };
};

interface PopupProps {
    result: DateDetectionResult;
    targetRef: HTMLTextAreaElement | null;
    onApply: () => void;
}

export const DateSuggestionPopup: React.FC<PopupProps> = ({ result, targetRef, onApply }) => {
    if (!targetRef) return null;

    const rect = targetRef.getBoundingClientRect();

    const style: React.CSSProperties = {
        position: 'fixed',
        top: rect.bottom + 5,
        left: rect.left + 20,
        zIndex: 1000,
        backgroundColor: 'rgba(255, 255, 255, 0.95)',
        backdropFilter: 'blur(10px)',
        borderRadius: '12px',
        boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
        padding: '8px 12px',
        display: 'flex',
        flexDirection: 'column',
        border: '1px solid rgba(0,0,0,0.05)',
        cursor: 'pointer',
        animation: 'popIn 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275)'
    };

    return (
        <div style={style} onMouseDown={(e) => {
            e.preventDefault(); // Prevent blurring the textarea, ensuring the popup stays until onApply clears it
            e.stopPropagation();
            onApply();
        }}>
            <div style={{ fontSize: '11px', color: '#888', marginBottom: '2px' }}>建议时间</div>
            <div style={{ fontSize: '15px', fontWeight: 600, color: '#333' }}>
                {result.suggestedLabel}
                {result.repeatType !== 'none' && <span style={{ marginLeft: '6px', fontSize: '12px', color: '#666', fontWeight: 400 }}>
                    {translateRepeat(result.repeatType)}
                </span>}
            </div>
        </div>
    );
};

const translateRepeat = (type: string) => {
    const map: Record<string, string> = {
        'daily': '每天',
        'weekly': '每周',
        'monthly': '每月',
        'yearly': '每年',
        'weekdays': '工作日'
    };
    return map[type] || type;
};
