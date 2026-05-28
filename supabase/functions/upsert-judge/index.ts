type AnyRow = Record<string, unknown>;

type UpsertJudgePayload = {
  event_id?: string;
  judge_id?: string;
  name?: string;
  role?: string;
  hero_image_name?: string;
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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
    const payload = await request.json() as UpsertJudgePayload;
    const eventID = cleanText(payload.event_id);
    const name = cleanText(payload.name).toUpperCase();
    const judgeID = stableID(payload.judge_id || name);
    const requestedRole = cleanText(payload.role).toLowerCase() === "admin" ? "admin" : "judge";
    const heroImageName = cleanText(payload.hero_image_name);

    if (!eventID) {
      throw new HTTPError(400, "Falta event_id.");
    }
    if (!name) {
      throw new HTTPError(400, "Falta name.");
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

    const existingRows = await supabaseRequest(
      "GET",
      `judges?select=event_id,judge_id,name,role,sort_order,hero_image_name&event_id=eq.${encodeURIComponent(eventID)}&judge_id=eq.${encodeURIComponent(judgeID)}&limit=1`,
    ) as AnyRow[];
    const existing = existingRows[0];
    const role = cleanText(existing?.role) === "admin" || judgeID === "ati" ? "admin" : requestedRole;
    const sortOrder = Number(existing?.sort_order) || await nextSortOrder(eventID);

    const rows = await supabaseRequest(
      "POST",
      "judges?on_conflict=event_id,judge_id",
      [{
        event_id: eventID,
        judge_id: judgeID,
        name,
        role,
        sort_order: sortOrder,
        hero_image_name: heroImageName,
      }],
      "resolution=merge-duplicates,return=representation",
    ) as AnyRow[];
    const judge = rows[0] ?? {};

    return jsonResponse({
      event_id: eventID,
      judge_id: cleanText(judge.judge_id) || judgeID,
      judge_name: cleanText(judge.name) || name,
      role: cleanText(judge.role) || role,
      saved: true,
    });
  } catch (error) {
    const status = error instanceof HTTPError ? error.status : 500;
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, status);
  }
});

async function nextSortOrder(eventID: string): Promise<number> {
  const rows = await supabaseRequest(
    "GET",
    `judges?select=sort_order&event_id=eq.${encodeURIComponent(eventID)}&order=sort_order.desc&limit=1`,
  ) as AnyRow[];
  return (Number(rows[0]?.sort_order) || 0) + 1;
}

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

function stableID(value: unknown): string {
  const base = cleanText(value)
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return base || "sin-dato";
}

function cleanText(value: unknown): string {
  return String(value ?? "").trim();
}
