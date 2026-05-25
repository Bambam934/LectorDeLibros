import * as crypto from 'crypto';

export enum MessageType {
  LOGIN = 'LOGIN',
  LOGIN_OK = 'LOGIN_OK',
  LOGIN_FAIL = 'LOGIN_FAIL',
  MESSAGE = 'MESSAGE',
  ACK = 'ACK',
  ERROR = 'ERROR',
  USER_LIST = 'USER_LIST',
  BROADCAST = 'BROADCAST',
}

export interface ProtocolMessage {
  type: MessageType;
  id?: string;
  from?: string;
  to?: string;
  content?: string;
  timestamp: number;
}

export const SERVER_PORT = 3500;
export const SERVER_HOST = '127.0.0.1';

export function generateId(): string {
  return crypto.randomBytes(4).toString('hex');
}

export function serialize(msg: ProtocolMessage): string {
  return JSON.stringify(msg) + '\n';
}

export function parseBuffer(buffer: string): { messages: ProtocolMessage[]; remaining: string } {
  const lines = buffer.split('\n');
  const remaining = lines.pop() || '';
  const messages: ProtocolMessage[] = [];

  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      messages.push(JSON.parse(line));
    } catch {
      // linea corrupta, ignorar
    }
  }

  return { messages, remaining };
}
