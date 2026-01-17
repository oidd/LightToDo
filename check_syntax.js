
        // Keep bridge error logging but silent on UI
        window.onerror = function (message, source, lineno, colno, error) {
            console.error(message);
            if (window.webkit?.messageHandlers?.editor) {
                window.webkit.messageHandlers.editor.postMessage({ type: 'error', message: message });
            }
        };
    