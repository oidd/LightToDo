/// <reference types="vite/client" />

interface Window {
    webkit?: {
        messageHandlers?: {
            editor?: {
                postMessage: (message: any) => void;
            };
        };
    };
    setContent?: (html: string) => void;
    setTitle?: (title: string) => void;
    setWindowActive?: (active: boolean) => void;
}
