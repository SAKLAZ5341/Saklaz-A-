// OpenAI Responses API istemcisi (POST /v1/responses).
// Eski Assistants API KULLANILMAZ.

export interface ChatMessage {
  role: 'user' | 'assistant';
  text: string;
}

export interface RespondInput {
  model: string;
  instructions: string;
  messages: ChatMessage[];
  maxOutputTokens: number;
  webSearch: boolean;
}

export interface RespondOutput {
  text: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

export class UpstreamError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

export function buildResponsesPayload(input: RespondInput): Record<string, unknown> {
  return {
    model: input.model,
    instructions: input.instructions,
    input: input.messages.map((m) => ({ role: m.role, content: m.text })),
    max_output_tokens: input.maxOutputTokens,
    // Konuşmalar OpenAI tarafında saklanmasın.
    store: false,
    ...(input.webSearch ? { tools: [{ type: 'web_search' }] } : {}),
  };
}

/** Responses API çıktısındaki tüm `output_text` parçalarını birleştirir. */
export function extractText(body: unknown): string {
  if (typeof body !== 'object' || body === null) return '';
  const b = body as { output_text?: unknown; output?: unknown };
  if (typeof b.output_text === 'string') return b.output_text;
  if (!Array.isArray(b.output)) return '';
  const parts: string[] = [];
  for (const item of b.output) {
    if (item?.type !== 'message' || !Array.isArray(item.content)) continue;
    for (const c of item.content) {
      if (c?.type === 'output_text' && typeof c.text === 'string') parts.push(c.text);
    }
  }
  return parts.join('').trim();
}

export async function callResponses(
  fetchImpl: FetchLike,
  baseUrl: string,
  apiKey: string,
  input: RespondInput,
  timeoutMs: number,
): Promise<RespondOutput> {
  let res: Response;
  try {
    res = await fetchImpl(`${baseUrl}/responses`, {
      method: 'POST',
      headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify(buildResponsesPayload(input)),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (e) {
    const timeout = e instanceof Error && (e.name === 'TimeoutError' || e.name === 'AbortError');
    throw new UpstreamError(timeout ? 504 : 502, timeout ? 'upstream timeout' : 'upstream unreachable');
  }
  const body: unknown = await res.json().catch(() => null);
  if (!res.ok) {
    // Hata gövdesi istemciye AKTARILMAZ (anahtar/hesap bilgisi sızmasın); yalnızca durum kodu.
    throw new UpstreamError(res.status === 429 ? 429 : 502, `upstream status ${res.status}`);
  }
  const usage = (body as { usage?: { input_tokens?: number; output_tokens?: number } } | null)?.usage;
  return {
    text: extractText(body),
    model: (body as { model?: string } | null)?.model ?? input.model,
    inputTokens: usage?.input_tokens ?? 0,
    outputTokens: usage?.output_tokens ?? 0,
  };
}
