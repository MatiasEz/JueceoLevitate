type AnyRow = Record<string, unknown>;

type UpdateRoutinePayload = {
  event_id?: string;
  routine_id?: string;
  division?: string;
  genre?: string;
  level?: string;
  category?: string;
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
    const payload = await request.json() as UpdateRoutinePayload;
    const eventID = cleanText(payload.event_id);
    const routineID = cleanText(payload.routine_id);

    if (!eventID) {
      throw new HTTPError(400, "Falta event_id.");
    }
    if (!routineID) {
      throw new HTTPError(400, "Falta routine_id.");
    }

    const updates: Record<string, string> = {};
    if (payload.division !== undefined) updates.division = cleanText(payload.division);
    if (payload.genre !== undefined) updates.genre = cleanText(payload.genre);
    if (payload.level !== undefined) updates.level = cleanText(payload.level);
    if (payload.category !== undefined) updates.category = cleanText(payload.category);

    if (Object.keys(updates).length === 0) {
      throw new HTTPError(400, "No hay campos para actualizar.");
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

    const routineRows = await supabaseRequest(
      "PATCH",
      `routines?event_id=eq.${encodeURIComponent(eventID)}&routine_id=eq.${encodeURIComponent(routineID)}`,
      updates,
      "return=representation",
    ) as AnyRow[];
    const routine = routineRows[0];
    if (!routine) {
      throw new HTTPError(404, "No se encontro la coreografia.");
    }

    return jsonResponse({
      event_id: eventID,
      routine_id: cleanText(routine.routine_id) || routineID,
      routine_name: cleanText(routine.name),
      division: cleanText(routine.division),
      genre: cleanText(routine.genre),
      level: cleanText(routine.level),
      category: cleanText(routine.category),
      updated: true,
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
