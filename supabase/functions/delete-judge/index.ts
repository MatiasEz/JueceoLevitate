type AnyRow = Record<string, unknown>;

type DeleteJudgePayload = {
  event_id?: string;
  judge_id?: string;
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-import-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class HTTPError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Metodo no permitido." }, 405);
  }

  try {
    const payload = await request.json() as DeleteJudgePayload;
    const eventID = cleanText(payload.event_id);
    const judgeID = cleanText(payload.judge_id);
    if (!eventID) {
      throw new HTTPError(400, "Falta event_id.");
    }
    if (!judgeID) {
      throw new HTTPError(400, "Falta judge_id.");
    }
    if (judgeID === "ati") {
      throw new HTTPError(409, "No se puede borrar ATI.");
    }

    const eventRows = await supabaseRequest(
      "GET",
      `events?select=id,name,event_type&id=eq.${encodeURIComponent(eventID)}&limit=1`,
    ) as AnyRow[];
    const event = eventRows[0];
    if (!event) {
      throw new HTTPError(404, "No se encontro el programa.");
    }
    if (cleanText(event.event_type) === "archived") {
      throw new HTTPError(409, "El programa ya esta archivado.");
    }

    const judgeRows = await supabaseRequest(
      "GET",
      `judges?select=event_id,judge_id,name,role&event_id=eq.${encodeURIComponent(eventID)}&judge_id=eq.${encodeURIComponent(judgeID)}&limit=1`,
    ) as AnyRow[];
    const judge = judgeRows[0];
    if (!judge) {
      throw new HTTPError(404, "No se encontro el juez.");
    }
    if (cleanText(judge.role) === "admin") {
      throw new HTTPError(409, "No se puede borrar un admin.");
    }

    for (const table of ["routine_favorites", "penalties", "feedback", "scores"]) {
      await supabaseRequest(
        "DELETE",
        `${table}?event_id=eq.${encodeURIComponent(eventID)}&judge_id=eq.${encodeURIComponent(judgeID)}`,
        undefined,
        "return=minimal",
      );
    }

    await supabaseRequest(
      "DELETE",
      `judges?event_id=eq.${encodeURIComponent(eventID)}&judge_id=eq.${encodeURIComponent(judgeID)}`,
      undefined,
      "return=minimal",
    );

    return jsonResponse({
      event_id: eventID,
      judge_id: judgeID,
      judge_name: cleanText(judge.name),
      deleted: true,
    });
  } catch (error) {
    const status = error instanceof HTTPError ? error.status : 500;
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, status);
  }
});

async function supabaseRequest(method: string, path: string, payload?: unknown, prefer?: string): Promise<unknown> {
  const baseURL = cleanText(Deno.env.get("SUPABASE_URL")).replace(/\/+$/, "");
  const serviceKey = supabaseSecretKey();
  if (!baseURL || !serviceKey) {
    throw new HTTPError(500, "Faltan SUPABASE_URL y una secret key en la Edge Function.");
  }

  const response = await fetch(`${baseURL}/rest/v1/${path.replace(/^\/+/, "")}`, {
    method,
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      ...(prefer ? { Prefer: prefer } : {}),
    },
    body: payload === undefined ? undefined : JSON.stringify(payload),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new HTTPError(response.status, `Supabase ${method} ${path} fallo: ${response.status} ${text}`);
  }
  return text ? JSON.parse(text) : null;
}

function supabaseSecretKey(): string {
  const directKey = cleanText(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY"));
  if (directKey) {
    return directKey;
  }

  const encodedKeys = cleanText(Deno.env.get("SUPABASE_SECRET_KEYS"));
  if (!encodedKeys) {
    return "";
  }

  try {
    const keys = JSON.parse(encodedKeys) as Record<string, unknown>;
    const preferred = cleanText(keys.service_role) || cleanText(keys.default);
    if (preferred) {
      return preferred;
    }
    const firstKey = Object.values(keys).map(cleanText).find(Boolean);
    return firstKey || "";
  } catch {
    return "";
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

function cleanText(value: unknown): string {
  return String(value ?? "").trim();
}
