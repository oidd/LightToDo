/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 */

import {
    $isTextNode,
    DOMConversionMap,
    DOMConversionOutput,
    DOMExportOutput,
    LexicalEditor,
    TextNode,
    SerializedTextNode,
    NodeKey,
} from 'lexical';

export class ExtendedTextNode extends TextNode {
    static getType(): string {
        return 'extended-text';
    }

    static clone(node: ExtendedTextNode): ExtendedTextNode {
        return new ExtendedTextNode(node.__text, node.__key);
    }

    static importDOM(): DOMConversionMap | null {
        // Only handle <span> to capture colors. 
        // We rely on standard TextNode importers for everything else to ensure stability.
        const newSetters: DOMConversionMap = {};

        newSetters['span'] = (node: HTMLElement) => {
            const style = node.getAttribute('style');
            if (!style) return null; // Let other handlers (or default) handle it if no style
            return {
                conversion: (element: HTMLElement) => {
                    const node = $createExtendedTextNode(element.textContent || '');
                    if (style) {
                        node.setStyle(style);
                    }
                    return { node };
                },
                priority: 1 // Higher priority to catch spans with styles
            };
        };

        return newSetters;
    }

    static importJSON(serializedNode: SerializedTextNode): TextNode {
        const node = new ExtendedTextNode(serializedNode.text);
        node.setFormat(serializedNode.format);
        node.setDetail(serializedNode.detail);
        node.setMode(serializedNode.mode);
        node.setStyle(serializedNode.style);
        return node;
    }

    exportJSON(): SerializedTextNode {
        return {
            ...super.exportJSON(),
            type: 'extended-text',
            version: 1,
        };
    }

    exportDOM(editor: LexicalEditor): DOMExportOutput {
        const { element } = super.exportDOM(editor);
        const style = this.getStyle();

        if (style !== '') {
            if (element instanceof HTMLElement) {
                element.style.cssText += style;
                return { element };
            } else {
                const span = document.createElement('span');
                span.style.cssText = style;
                if (element instanceof Text) {
                    span.appendChild(element);
                } else {
                    span.textContent = this.getTextContent();
                }
                return { element: span };
            }
        }
        return { element };
    }
}

export function $createExtendedTextNode(text: string): ExtendedTextNode {
    return new ExtendedTextNode(text);
}
