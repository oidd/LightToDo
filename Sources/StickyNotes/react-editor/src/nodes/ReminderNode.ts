
import {
  EditorConfig,
  ElementNode,
  LexicalNode,
  NodeKey,
  SerializedElementNode,
  Spread,
  DOMConversionMap,
  DOMConversionOutput,
  DOMExportOutput,
} from 'lexical';

export type RepeatType = 'none' | 'daily' | 'weekdays' | 'weekly' | 'monthly' | 'yearly';

export interface ReminderData {
  time: number; // Timestamp
  repeatType: RepeatType;
  // We store the original configuration to recalculate correctly
  originalTime: number;
  autoRefreshedAt?: number; // Timestamp when this was auto-created
  completedAt?: number; // Timestamp when task was completed
}

export type SerializedReminderNode = Spread<
  {
    reminderData: ReminderData;
  },
  SerializedElementNode
>;

export class ReminderNode extends ElementNode {
  __data: ReminderData;

  static getType(): string {
    return 'reminder';
  }

  static clone(node: ReminderNode): ReminderNode {
    return new ReminderNode(node.__data, node.__key);
  }

  constructor(data: ReminderData, key?: NodeKey) {
    super(key);
    this.__data = data;
  }

  getData(): ReminderData {
    return this.__data;
  }

  setData(data: ReminderData): void {
    const writable = this.getWritable();
    writable.__data = data;
  }

  createDOM(config: EditorConfig): HTMLElement {
    const span = document.createElement('span');
    span.style.display = 'none';
    span.className = 'reminder-node';
    span.dataset.reminder = JSON.stringify(this.__data);
    return span;
  }

  updateDOM(prevNode: ReminderNode, dom: HTMLElement): boolean {
    const newData = JSON.stringify(this.__data);
    if (dom.dataset.reminder !== newData) {
      dom.dataset.reminder = newData;
      return true;
    }
    return false;
  }

  static importDOM(): DOMConversionMap | null {
    return {
      span: (node: HTMLElement) => {
        if (node.classList.contains('reminder-node') && node.dataset.reminder) {
          try {
            const data = JSON.parse(node.dataset.reminder);
            return {
              conversion: () => {
                const reminderNode = $createReminderNode(data);
                return { node: reminderNode };
              },
              priority: 2, // Higher than ExtendedTextNode
            };
          } catch (e) {
            return null;
          }
        }
        return null;
      },
    };
  }

  exportDOM(): DOMExportOutput {
    const element = document.createElement('span');
    element.className = 'reminder-node';
    element.style.display = 'none';
    element.dataset.reminder = JSON.stringify(this.__data);
    return { element };
  }

  static importJSON(serializedNode: SerializedReminderNode): ReminderNode {
    return $createReminderNode(serializedNode.reminderData);
  }

  exportJSON(): SerializedReminderNode {
    return {
      ...super.exportJSON(),
      type: 'reminder',
      reminderData: this.__data,
      version: 1,
    };
  }
}

export function $createReminderNode(data: ReminderData): ReminderNode {
  return new ReminderNode(data);
}

export function $isReminderNode(node: LexicalNode | null | undefined): node is ReminderNode {
  return node instanceof ReminderNode;
}
