type AnyRow = Record<string, unknown>;

type MoveRoutinePayload = {
  event_id?: string;
  routine_id?: string;
  target_block_id?: string;
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
    const payload = await request.json() as MoveRoutinePayload;
    const eventID = cleanText(payload.event_id);
    const routineID = cleanText(payload.routine_id);
    const targetBlockID = cleanText(payload.target_block_id);

    if (!eventID) {
      throw new HTTPError(400, "Falta event_id.");
    }
    if (!routineID) {
      throw new HTTPError(400, "Falta routine_id.");
    }
    if (!targetBlockID) {
      throw new HTTPError(400, "Falta target_block_id.");
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

    const targetBlockRows = await supabaseRequest(
      "GET",
      `blocks?select=block_id,name,title&event_id=eq.${encodeURIComponent(eventID)}&block_id=eq.${encodeURIComponent(targetBlockID)}&limit=1`,
    ) as AnyRow[];
    const targetBlock = targetBlockRows[0];
    if (!targetBlock) {
      throw new HTTPError(404, "No se encontro el bloque destino.");
    }

    const routineRows = await supabaseRequest(
      "GET",
      `routines?select=event_id,routine_id,block_id,block,block_title,name&event_id=eq.${encodeURIComponent(eventID)}&routine_id=eq.${encodeURIComponent(routineID)}&limit=1`,
    ) as AnyRow[];
    const routine = routineRows[0];
    if (!routine) {
      throw new HTTPError(404, "No se encontro la coreografia.");
    }

    const previousBlockID = cleanText(routine.block_id);
    const previousBlockName = cleanText(routine.block);
    const targetBlockName = cleanText(targetBlock.name);
    const targetBlockTitle = cleanText(targetBlock.title);

    if (previousBlockID === targetBlockID) {
      return jsonResponse({
        event_id: eventID,
        routine_id: routineID,
        routine_name: cleanText(routine.name),
        previous_block_id: previousBlockID,
        previous_block_name: previousBlockName,
        target_block_id: targetBlockID,
        target_block_name: targetBlockName,
        moved: false,
      });
    }

    await patchRoutineFavoriteVotes(eventID, routineID, targetBlockID);
    await patchRoutineFavorites(eventID, routineID, targetBlockID);
    await patchRoutineSpecialAwards(eventID, routineID, targetBlockID);

    const updatedRoutineRows = await supabaseRequest(
      "PATCH",
      `routines?event_id=eq.${encodeURIComponent(eventID)}&routine_id=eq.${encodeURIComponent(routineID)}`,
      {
        block_id: targetBlockID,
        block: targetBlockName,
        block_title: targetBlockTitle,
      },
      "return=representation",
    ) as AnyRow[];
    const updatedRoutine = updatedRoutineRows[0];
    if (!updatedRoutine) {
      throw new HTTPError(404, "No se encontro la coreografia para mover.");
    }

    await patchBlockID("scores", eventID, routineID, targetBlockID);
    await patchBlockID("feedback", eventID, routineID, targetBlockID);
    await patchBlockID("penalties", eventID, routineID, targetBlockID);
    await patchBlockID("judge_activity", eventID, routineID, targetBlockID);

    return jsonResponse({
      event_id: eventID,
      routine_id: cleanText(updatedRoutine.routine_id) || routineID,
      routine_name: cleanText(updatedRoutine.name),
      previous_block_id: previousBlockID,
      previous_block_name: previousBlockName,
      target_block_id: targetBlockID,
      target_block_name: targetBlockName,
      moved: true,
    });
  } catch (error) {
    const status = error instanceof HTTPError ? error.status : 500;
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, status);
  }
});

async function patchBlockID(table: string, eventID: string, routineID: string, targetBlockID: string): Promise<void> {
  await supabaseRequest(
    "PATCH",
    `${table}?event_id=eq.${encodeURIComponent(eventID)}&routine_id=eq.${encodeURIComponent(routineID)}`,
    { block_id: targetBlockID },
    "return=minimal",
  );
}

async function patchRoutineFavoriteVotes(eventID: string, routineID: string, targetBlockID: string): Promise<void> {
  await ignoreMissingTable(async () => {
    await supabaseRequest(
      "DELETE",
      `routine_favorite_votes?event_id=eq.${encodeURIComponent(eventID)}&block_id=eq.${encodeURIComponent(targetBlockID)}&routine_id=eq.${encodeURIComponent(routineID)}`,
      undefined,
      "return=minimal",
    );
    await patchBlockID("routine_favorite_votes", eventID, routineID, targetBlockID);
  });
}

async function patchRoutineFavorites(eventID: string, routineID: string, targetBlockID: string): Promise<void> {
  await ignoreMissingTable(async () => {
    const rows = await supabaseRequest(
      "GET",
      `routine_favorites?select=judge_id,category&event_id=eq.${encodeURIComponent(eventID)}&routine_id=eq.${encodeURIComponent(routineID)}`,
    ) as AnyRow[];

    for (const row of rows) {
      const judgeID = cleanText(row.judge_id);
      const category = cleanText(row.category);
      if (!judgeID || !category) {
        continue;
      }
      await supabaseRequest(
        "DELETE",
        `routine_favorites?event_id=eq.${encodeURIComponent(eventID)}&block_id=eq.${encodeURIComponent(targetBlockID)}&judge_id=eq.${encodeURIComponent(judgeID)}&category=eq.${encodeURIComponent(category)}`,
        undefined,
        "return=minimal",
      );
    }

    await patchBlockID("routine_favorites", eventID, routineID, targetBlockID);
  });
}

async function patchRoutineSpecialAwards(eventID: string, routineID: string, targetBlockID: string): Promise<void> {
  await ignoreMissingTable(async () => {
    const rows = await supabaseRequest(
      "GET",
      `special_awards?select=award&event_id=eq.${encodeURIComponent(eventID)}&routine_id=eq.${encodeURIComponent(routineID)}`,
    ) as AnyRow[];

    for (const row of rows) {
      const award = cleanText(row.award);
      if (!award) {
        continue;
      }
      await supabaseRequest(
        "DELETE",
        `special_awards?event_id=eq.${encodeURIComponent(eventID)}&block_id=eq.${encodeURIComponent(targetBlockID)}&award=eq.${encodeURIComponent(award)}`,
        undefined,
        "return=minimal",
      );
    }

    await patchBlockID("special_awards", eventID, routineID, targetBlockID);
  });
}

async function ignoreMissingTable(operation: () => Promise<void>): Promise<void> {
  try {
    await operation();
  } catch (error) {
    if (error instanceof HTTPError && (error.status === 404 || error.status === 400)) {
      return;
    }
    throw error;
  }
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

function cleanText(value: unknown): string {
  return String(value ?? "").trim();
}
