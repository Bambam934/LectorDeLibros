import OpenAI from 'openai';
import { env } from './env.js';

export type GlmMessage = {
  role: 'user' | 'assistant' | 'system';
  content: string;
};

export type GlmOptions = {
  temperature?: number;
  maxTokens?: number;
  stream?: boolean;
  enableThinking?: boolean;
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

/**
 * Llamada simple: devuelve el texto de respuesta.
 */
export async function glmChat(
  messages: GlmMessage[],
  options: GlmOptions = {}
): Promise<string> {
  const client = createClient();
  const { temperature = 0.7, maxTokens = 4096, enableThinking = false } = options;

  const completion = await client.chat.completions.create({
    model: 'z-ai/glm-5.1',
    messages,
    temperature,
    top_p: 1,
    max_tokens: maxTokens,
    ...(({ extra_body: { chat_template_kwargs: { enable_thinking: enableThinking, clear_thinking: false } } }) as Record<string, unknown>),
  });

  return completion.choices[0]?.message?.content ?? '';
}

/**
 * Llamada con streaming: emite chunks de texto a medida que llegan.
 */
export async function* glmStream(
  messages: GlmMessage[],
  options: GlmOptions = {}
): AsyncGenerator<string> {
  const client = createClient();
  const { temperature = 0.7, maxTokens = 4096, enableThinking = false } = options;

  const stream = await client.chat.completions.create({
    model: 'z-ai/glm-5.1',
    messages,
    temperature,
    top_p: 1,
    max_tokens: maxTokens,
    stream: true,
    ...(({ extra_body: { chat_template_kwargs: { enable_thinking: enableThinking, clear_thinking: false } } }) as Record<string, unknown>),
  });

  for await (const chunk of stream) {
    const delta = chunk.choices[0]?.delta;
    if (delta?.content) yield delta.content;
  }
}

// ─── Funciones de alto nivel para LectorSync ───────────────────────────────

/**
 * Genera un resumen corto de un capítulo de libro.
 */
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

/**
 * Detecta personajes y sus diálogos en un fragmento de texto.
 * Devuelve JSON con estructura { character: string, lines: string[] }[].
 */
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
    { temperature: 0.3, enableThinking: true }
  );

  try {
    const json = raw.match(/\[[\s\S]*\]/)?.[0] ?? '[]';
    return JSON.parse(json);
  } catch {
    return [];
  }
}

/**
 * Limpia y normaliza texto de EPUB antes de enviarlo a TTS.
 */
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
