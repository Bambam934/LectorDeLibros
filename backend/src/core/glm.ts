import OpenAI from 'openai';
import type { ChatCompletionMessageParam } from 'openai/resources/chat/completions.js';
import { env } from './env.js';

export type GlmMessage = {
  role: 'user' | 'assistant' | 'system';
  content: string;
};

export type GlmOptions = {
  temperature?: number;
  maxTokens?: number;
};

function createClient(): OpenAI {
  if (!env.NVIDIA_API_KEY) {
    throw new Error('NVIDIA_API_KEY no está configurada en .env');
  }
  return new OpenAI({
    baseURL: env.NVIDIA_API_BASE_URL,
    apiKey: env.NVIDIA_API_KEY,
  });
}

export async function glmChat(
  messages: GlmMessage[],
  options: GlmOptions = {}
): Promise<string> {
  const client = createClient();
  const { temperature = 0.7, maxTokens = 4096 } = options;

  const completion = await client.chat.completions.create({
    model: 'z-ai/glm-5.1',
    messages: messages as ChatCompletionMessageParam[],
    temperature,
    top_p: 1,
    max_tokens: maxTokens,
  });

  return completion.choices[0]?.message?.content ?? '';
}

export async function* glmStream(
  messages: GlmMessage[],
  options: GlmOptions = {}
): AsyncGenerator<string> {
  const client = createClient();
  const { temperature = 0.7, maxTokens = 4096 } = options;

  const stream = await client.chat.completions.create({
    model: 'z-ai/glm-5.1',
    messages: messages as ChatCompletionMessageParam[],
    temperature,
    top_p: 1,
    max_tokens: maxTokens,
    stream: true,
  });

  for await (const chunk of stream) {
    const delta = chunk.choices[0]?.delta;
    if (delta?.content) yield delta.content;
  }
}

export async function summarizeChapter(text: string): Promise<string> {
  return glmChat([
    {
      role: 'system',
      content:
        'Eres un asistente literario. Resume el capítulo en 3-5 oraciones claras, ' +
        'conservando los puntos clave del argumento y el tono del texto.',
    },
    { role: 'user', content: text.slice(0, 8000) },
  ]);
}

export async function detectDialogues(
  text: string
): Promise<{ character: string; lines: string[] }[]> {
  const raw = await glmChat(
    [
      {
        role: 'system',
        content:
          'Analiza el texto y extrae los diálogos agrupados por personaje. ' +
          'Responde ÚNICAMENTE con JSON válido, sin explicaciones. ' +
          'Formato: [{"character":"Nombre","lines":["línea1","línea2"]}]',
      },
      { role: 'user', content: text.slice(0, 6000) },
    ],
    { temperature: 0.3 }
  );

  try {
    const json = raw.match(/\[[\s\S]*\]/)?.[0] ?? '[]';
    return JSON.parse(json);
  } catch {
    return [];
  }
}

export async function cleanTextForTts(raw: string): Promise<string> {
  return glmChat([
    {
      role: 'system',
      content:
        'Recibirás texto extraído de un EPUB. Elimina notas al pie, números de página, ' +
        'encabezados repetidos y artefactos de formato. Devuelve solo el texto limpio, ' +
        'listo para ser leído en voz alta. No agregues ninguna explicación.',
    },
    { role: 'user', content: raw.slice(0, 8000) },
  ]);
}
