import * as XLSX from "npm:xlsx@0.18.5";
import { DEFAULT_TEMPLATES } from "./default_templates.ts";

type AnyRow = Record<string, unknown>;

type Criterion = {
  id: number;
  section: string;
  label: string;
  maxScore: number;
};

type Template = {
  genre: string;
  title: string;
  maxScore: number;
  criteria: Criterion[];
};

type Routine = {
  id: string;
  blockID: string;
  block: string;
  name: string;
  academy: string;
  division: string;
  genre: string;
  level: string;
  category: string;
  choreographer: string;
  participant: string;
  state: string;
  time: string;
  duration: string;
};

type DanceBlock = {
  blockID: string;
  name: string;
  title: string;
  sortOrder: number;
  isActive: boolean;
  routines: Routine[];
};

type AppData = {
  sourceName: string;
  blocks: DanceBlock[];
  routines: Routine[];
  templates: Template[];
  judges: string[];
};

type ImportPayload = {
  event_slug?: string;
  event_name?: string;
  filename?: string;
  payload_base64?: string;
  activate?: boolean;
  replace_event?: boolean;
  force_replace?: boolean;
  dry_run?: boolean;
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-import-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const IMPORT_SECRET_HEADER = "x-import-secret";

const REQUIRED_BLOCK_COLUMNS: Record<string, string> = {
  name: "COREOGRAFIA",
  academy: "ACADEMIA",
  division: "DIVISION",
  genre: "GENERO/SUBGENERO",
  category: "CATEGORIA",
};

const TEMPLATE_ALIASES: Record<string, string> = {
  ARO: "DANZA AEREA",
  TELA: "DANZA AEREA",
  URBANOS: "HIP HOP",
  OPEN: "CONTEMPORANEO",
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
    authorizeImport(request);
    const payload = await request.json() as ImportPayload;
    const sourceName = cleanText(payload.filename) || "import.xlsx";
    const slug = stableID(payload.event_slug || sourceName.replace(/\.[^.]+$/, ""));
    const eventName = cleanText(payload.event_name) || sourceName.replace(/\.[^.]+$/, "");
    const payloadBase64 = cleanText(payload.payload_base64);
    if (!payloadBase64) {
      throw new HTTPError(400, "Falta payload_base64.");
    }

    const appData = parseWorkbook(sourceName, payloadBase64);
    if (payload.dry_run) {
      return jsonResponse({
        event_id: "",
        event_slug: slug,
        event_name: eventName,
        routines: appData.routines.length,
        blocks: appData.blocks.length,
        templates: appData.templates.length,
        dry_run: true,
      });
    }

    const eventID = await uploadToSupabase(appData, {
      slug,
      name: eventName,
      activate: payload.activate ?? true,
      replaceEvent: payload.replace_event ?? false,
      forceReplace: payload.force_replace ?? false,
    });

    return jsonResponse({
      event_id: eventID,
      event_slug: slug,
      event_name: eventName,
      routines: appData.routines.length,
      blocks: appData.blocks.length,
      templates: appData.templates.length,
    });
  } catch (error) {
    const status = error instanceof HTTPError ? error.status : 500;
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, status);
  }
});

function authorizeImport(request: Request): void {
  const expected = cleanText(Deno.env.get("IMPORT_SECRET") || Deno.env.get("JUECEO_IMPORT_SECRET"));
  if (!expected) {
    throw new HTTPError(500, "Falta IMPORT_SECRET en la Edge Function.");
  }

  const provided = cleanText(request.headers.get(IMPORT_SECRET_HEADER));
  if (!safeEqual(provided, expected)) {
    throw new HTTPError(403, "No tenes permiso para importar Excel.");
  }
}

function safeEqual(left: string, right: string): boolean {
  const maxLength = Math.max(left.length, right.length);
  let diff = left.length ^ right.length;
  for (let index = 0; index < maxLength; index += 1) {
    diff |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return diff === 0;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function normalized(value: unknown): string {
  return cleanText(value)
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toUpperCase();
}

function stableID(value: unknown): string {
  const base = normalized(value).toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return base || "sin-dato";
}

function cleanText(value: unknown): string {
  return String(value ?? "").trim();
}

function rowText(row: unknown[], index: number | undefined): string {
  if (index === undefined || index < 0 || index >= row.length) {
    return "";
  }
  return cleanText(row[index]);
}

function parseNumber(value: unknown): number {
  const text = cleanText(value).replace(",", ".");
  if (!text) {
    return Number.NaN;
  }
  return Number(text);
}

function compactNumberText(value: unknown): string {
  const number = parseNumber(value);
  if (!Number.isFinite(number)) {
    return cleanText(value);
  }
  return Number.isInteger(number) ? String(number) : String(Number(number.toPrecision(12)));
}

function routineIDText(value: unknown): string {
  const text = cleanText(value);
  if (!text) {
    return "";
  }
  const number = Number(text.replace(",", "."));
  return Number.isFinite(number) && Number.isInteger(number) ? String(number) : text.replace(/\.0$/, "");
}

function titleCase(value: string): string {
  return value.toLocaleLowerCase("es-MX").replace(/\p{L}+/gu, (word) => {
    const [first = "", ...rest] = Array.from(word);
    return first.toLocaleUpperCase("es-MX") + rest.join("");
  });
}

function parseWorkbook(sourceName: string, payloadBase64: string): AppData {
  const workbook = XLSX.read(payloadBase64, {
    type: "base64",
    cellFormula: true,
    cellNF: true,
    cellText: true,
  });

  const blocks: DanceBlock[] = [];
  const templates: Template[] = [];
  const warnings: string[] = [];
  const errors: string[] = [];

  for (const sheetName of workbook.SheetNames) {
    const sheet = workbook.Sheets[sheetName];
    const block = parseBlock(sheetName, sheet);
    if (block) {
      blocks.push(block);
    }

    const template = parseTemplate(sheetName, sheet);
    if (template) {
      templates.push(template);
    }
  }

  const routines = blocks.flatMap((block) => block.routines);
  if (routines.length && templates.length === 0) {
    templates.push(...cloneTemplates(DEFAULT_TEMPLATES as readonly Template[]));
    warnings.push("Se usan plantillas base embebidas en la funcion import-excel.");
  }

  const judges = withRequiredPeople(parseJudges(workbook, warnings));
  const routineIDs = new Set<string>();
  for (const routine of routines) {
    if (routineIDs.has(routine.id)) {
      errors.push(`Rutina duplicada: #${routine.id}.`);
    }
    routineIDs.add(routine.id);
  }

  const templateWarnings = ensureTemplatesForRoutines(templates, routines);
  warnings.push(...templateWarnings);

  if (errors.length) {
    throw new HTTPError(422, errors.join("; "));
  }

  return {
    sourceName,
    blocks,
    routines,
    templates,
    judges,
  };
}

function cloneTemplates(templates: readonly Template[]): Template[] {
  return templates.map((template) => ({
    ...template,
    criteria: template.criteria.map((criterion) => ({ ...criterion })),
  }));
}

function sheetRows(sheet: XLSX.WorkSheet): unknown[][] {
  const ref = sheet["!ref"];
  if (!ref) {
    return [];
  }
  const range = XLSX.utils.decode_range(ref);
  const rows: unknown[][] = [];
  for (let rowIndex = range.s.r; rowIndex <= range.e.r; rowIndex += 1) {
    const row: unknown[] = [];
    for (let columnIndex = range.s.c; columnIndex <= range.e.c; columnIndex += 1) {
      row.push(cellText(sheet, rowIndex, columnIndex));
    }
    rows.push(row);
  }
  return rows;
}

function cellText(sheet: XLSX.WorkSheet, rowIndex: number, columnIndex: number): string {
  const cell = sheet[XLSX.utils.encode_cell({ r: rowIndex, c: columnIndex })] as XLSX.CellObject | undefined;
  if (!cell) {
    return "";
  }
  if (cell.w !== undefined) {
    return cleanText(cell.w);
  }
  if (cell.v instanceof Date) {
    return formatDateCell(cell.v);
  }
  if (typeof cell.v === "number" && cell.v >= 0 && cell.v < 1 && cleanText(cell.z).toLowerCase().includes("h")) {
    return formatExcelTime(cell.v);
  }
  return cleanText(cell.v);
}

function cellFormula(sheet: XLSX.WorkSheet, rowIndex: number, columnIndex: number): string {
  const cell = sheet[XLSX.utils.encode_cell({ r: rowIndex, c: columnIndex })] as XLSX.CellObject | undefined;
  return cleanText(cell?.f);
}

function formatDateCell(date: Date): string {
  const hours = date.getUTCHours();
  const minutes = date.getUTCMinutes();
  const seconds = date.getUTCSeconds();
  if (date.getUTCFullYear() <= 1900 || (date.getUTCFullYear() === 1899 && date.getUTCMonth() === 11)) {
    return seconds ? padTime(hours, minutes, seconds) : padTime(hours, minutes);
  }
  return date.toISOString();
}

function formatExcelTime(value: number): string {
  const totalSeconds = Math.round(value * 24 * 60 * 60);
  const hours = Math.floor(totalSeconds / 3600) % 24;
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return seconds ? padTime(hours, minutes, seconds) : padTime(hours, minutes);
}

function padTime(hours: number, minutes: number, seconds?: number): string {
  const hh = String(hours).padStart(2, "0");
  const mm = String(minutes).padStart(2, "0");
  if (seconds === undefined) {
    return `${hh}:${mm}`;
  }
  return `${hh}:${mm}:${String(seconds).padStart(2, "0")}`;
}

function parseBlock(sheetName: string, sheet: XLSX.WorkSheet): DanceBlock | null {
  const rows = sheetRows(sheet);
  const headerIndex = rows.findIndex((row) => {
    const headers = row.map(normalized);
    return headers.includes("COREOGRAFIA") && headers.includes("ACADEMIA");
  });
  if (headerIndex < 0) {
    return null;
  }

  const columnMap: Record<string, number> = {};
  rows[headerIndex].forEach((value, index) => {
    const key = normalized(value);
    if (key.includes("COREOGRAFIA")) columnMap.name = index;
    if (key.includes("ACADEMIA")) columnMap.academy = index;
    if (key.includes("DIVISION")) columnMap.division = index;
    if (key.includes("GENERO") || key.includes("MODALIDAD")) columnMap.genre = index;
    if (key.includes("NIVEL")) columnMap.level = index;
    if (key.includes("CATEGORIA")) columnMap.category = index;
    if (key.includes("COREOGRAFO")) columnMap.choreographer = index;
    if (key.includes("PARTICIPANTE")) columnMap.participant = index;
    if (key.includes("ESTADO")) columnMap.state = index;
    if (key.includes("HORARIO")) columnMap.time = index;
    if (key.includes("DURACION")) columnMap.duration = index;
  });

  const missing = Object.entries(REQUIRED_BLOCK_COLUMNS)
    .filter(([key]) => columnMap[key] === undefined)
    .map(([, label]) => label);
  if (missing.length) {
    return null;
  }

  const blockID = stableID(sheetName);
  const routines: Routine[] = [];
  for (let rowIndex = headerIndex + 1; rowIndex < rows.length; rowIndex += 1) {
    const row = rows[rowIndex];
    const routineID = routineIDText(row[0]);
    if (!routineID) {
      continue;
    }

    const name = rowText(row, columnMap.name);
    if (!name) {
      continue;
    }

    const duration = rowText(row, columnMap.duration) || inferredDuration(sheet, rowIndex + 1, columnMap.time);
    routines.push({
      id: routineID,
      blockID,
      block: sheetName,
      name: titleCase(name),
      academy: rowText(row, columnMap.academy),
      division: rowText(row, columnMap.division),
      genre: rowText(row, columnMap.genre),
      level: rowText(row, columnMap.level),
      category: rowText(row, columnMap.category),
      choreographer: rowText(row, columnMap.choreographer),
      participant: rowText(row, columnMap.participant),
      state: rowText(row, columnMap.state),
      time: rowText(row, columnMap.time),
      duration,
    });
  }

  if (!routines.length) {
    return null;
  }

  const sortOrder = Number.parseInt(routines[0].id, 10) || 0;
  const title = rows.slice(0, headerIndex)
    .flatMap((row) => row.map(cleanText).filter(Boolean))
    .join(" · ");
  return {
    blockID,
    name: sheetName,
    title,
    sortOrder,
    isActive: false,
    routines,
  };
}

function inferredDuration(sheet: XLSX.WorkSheet, rowNumber: number, timeIndex: number | undefined): string {
  if (timeIndex === undefined) {
    return "";
  }
  const nextRowFormula = cellFormula(sheet, rowNumber, timeIndex);
  const match = nextRowFormula.match(/^=?\s*\$?[A-Z]+\$?(\d+)\s*\+\s*([0-9]+(?:[.,][0-9]+)?)\s*\/\s*1440\s*$/i);
  if (!match || Number(match[1]) !== rowNumber) {
    return "";
  }
  return compactNumberText(match[2]);
}

function parseTemplate(sheetName: string, sheet: XLSX.WorkSheet): Template | null {
  const sheetKey = normalized(sheetName);
  if (
    sheetKey.startsWith("JUECEO") ||
    sheetKey.startsWith("COPIA DE JUECEO") ||
    sheetKey === "CALIFICACIONES" ||
    sheetKey === "DICTAMEN FINAL"
  ) {
    return null;
  }

  const rows = sheetRows(sheet);
  const title = rows.flatMap((row) => row)
    .map(cleanText)
    .find((value) => normalized(value).includes("HOJA DE JUECEO"));
  const templateMarkers = new Set(["TECNICA", "EJECUCION COREOGRAFICA", "INTERPRETACION", "ARTISTICO"]);
  const hasTemplateMarker = rows.flatMap((row) => row).some((value) => templateMarkers.has(normalized(value)));
  let section = "General";
  const criteria: Criterion[] = [];

  rows.forEach((row) => {
    const numberValue = row[1];
    const label = rowText(row, 2);
    const maximum = parseNumber(row[3]);
    const number = parseNumber(numberValue);
    if (cleanText(numberValue) && !Number.isFinite(number) && !["-", "JUEZ", "FEEDBACK"].includes(normalized(numberValue))) {
      section = cleanText(numberValue);
    }
    if (Number.isFinite(number) && number > 0 && label && Number.isFinite(maximum) && maximum > 0) {
      criteria.push({
        id: Math.trunc(number),
        section,
        label,
        maxScore: maximum,
      });
    }
  });

  if (!criteria.length) {
    return null;
  }
  if (!title && !hasTemplateMarker) {
    return null;
  }

  return {
    genre: sheetName,
    title: title || `HOJA DE JUECEO ${sheetName}`,
    maxScore: criteria.reduce((sum, criterion) => sum + criterion.maxScore, 0),
    criteria,
  };
}

function parseJudges(workbook: XLSX.WorkBook, warnings: string[]): string[] {
  const sheet = workbook.Sheets["CALIFICACIONES"];
  const judges: string[] = [];
  const seen = new Set<string>();
  let duplicateCount = 0;
  if (sheet) {
    const range = sheet["!ref"] ? XLSX.utils.decode_range(sheet["!ref"]) : null;
    if (range) {
      for (let rowIndex = range.s.r; rowIndex <= range.e.r; rowIndex += 1) {
        const value = cellText(sheet, rowIndex, 2);
        if (!value || normalized(value) === "JUEZ" || value.startsWith("=")) {
          continue;
        }
        const judge = value.toLocaleUpperCase("es-MX");
        const key = normalized(judge);
        if (seen.has(key)) {
          duplicateCount += 1;
          continue;
        }
        seen.add(key);
        judges.push(judge);
      }
    }
  }
  if (!judges.length) {
    warnings.push("No se encontraron jueces en CALIFICACIONES; se usan jueces demo.");
    return ["DAVE", "EVA", "DANIEL"];
  }
  if (duplicateCount) {
    warnings.push(`CALIFICACIONES: ${duplicateCount} jueces duplicados omitidos.`);
  }
  return judges;
}

function withRequiredPeople(judges: string[]): string[] {
  const result = [...judges];
  if (!result.some((judge) => stableID(judge) === "ati")) {
    result.push("ATI");
  }
  return result;
}

function roleForPerson(name: string): string {
  return stableID(name) === "ati" ? "admin" : "judge";
}

function aliasBaseForGenre(genre: string): string | undefined {
  const genreKey = normalized(genre);
  if (genreKey.startsWith("OPEN:")) {
    return "DANZA AEREA";
  }
  return TEMPLATE_ALIASES[genreKey];
}

function ensureTemplatesForRoutines(templates: Template[], routines: Routine[]): string[] {
  const warnings: string[] = [];
  const templatesByGenre = new Map(templates.map((template) => [normalized(template.genre), template]));
  const genres = Array.from(new Set(routines.map((routine) => routine.genre).filter(Boolean)))
    .sort((left, right) => normalized(left).localeCompare(normalized(right)));

  for (const genre of genres) {
    const genreKey = normalized(genre);
    if (templatesByGenre.has(genreKey)) {
      continue;
    }
    const baseKey = aliasBaseForGenre(genre);
    const baseTemplate = baseKey ? templatesByGenre.get(baseKey) : undefined;
    if (!baseTemplate) {
      throw new HTTPError(422, `Genero sin hoja de jueceo: ${genre}.`);
    }
    const aliased = {
      ...baseTemplate,
      genre,
      title: `HOJA DE JUECEO ${genre}`,
      criteria: baseTemplate.criteria.map((criterion) => ({ ...criterion })),
    };
    templates.push(aliased);
    templatesByGenre.set(genreKey, aliased);
    warnings.push(`${genre}: se usa la plantilla base ${baseTemplate.genre}.`);
  }
  return warnings;
}

async function uploadToSupabase(
  appData: AppData,
  options: { slug: string; name: string; activate: boolean; replaceEvent: boolean; forceReplace: boolean },
): Promise<string> {
  const eventRows = await supabaseRequest("POST", "events?on_conflict=slug", [{
    slug: options.slug,
    name: options.name,
    source_name: appData.sourceName,
    event_type: "event",
  }], "resolution=merge-duplicates,return=representation") as AnyRow[];

  const eventID = cleanText(eventRows?.[0]?.id);
  if (!eventID) {
    throw new HTTPError(500, "Supabase no devolvio el evento importado.");
  }

  const importedBlockIDs = appData.blocks.map((block) => block.blockID || stableID(block.name));
  if (options.replaceEvent) {
    if (!options.forceReplace && (
      await eventRowsExist("scores", eventID) ||
      await eventRowsExist("feedback", eventID) ||
      await eventRowsExist("penalties", eventID)
    )) {
      throw new HTTPError(409, "El evento ya tiene puntajes, feedback o penalizaciones.");
    }
    await deleteEventRows(eventID);
  } else {
    await deleteBlockRows(eventID, importedBlockIDs, options.forceReplace);
  }

  const blockTitles = new Map(appData.blocks.map((block) => [block.name, block.title || ""]));
  const blockIDs = new Map(appData.blocks.map((block) => [block.name, block.blockID || stableID(block.name)]));
  const blockRows = appData.blocks.map((block, index) => ({
    event_id: eventID,
    block_id: block.blockID || stableID(block.name),
    name: block.name,
    title: block.title || "",
    sort_order: block.sortOrder || index + 1,
    is_active: Boolean(block.isActive),
  }));
  const routineRows = appData.routines.map((routine, index) => ({
    event_id: eventID,
    routine_id: routine.id,
    block_id: routine.blockID || blockIDs.get(routine.block) || stableID(routine.block),
    block: routine.block,
    block_title: blockTitles.get(routine.block) || "",
    sort_order: index + 1,
    name: routine.name,
    academy: routine.academy,
    division: routine.division,
    genre: routine.genre,
    level: routine.level,
    category: routine.category,
    choreographer: routine.choreographer,
    participant: routine.participant,
    state: routine.state,
    scheduled_time: routine.time,
    duration: routine.duration,
  }));
  const judgeRows = appData.judges.map((judge, index) => ({
    event_id: eventID,
    judge_id: stableID(judge),
    name: judge,
    role: roleForPerson(judge),
    sort_order: index + 1,
  }));
  const templateRows: AnyRow[] = [];
  const criterionRows: AnyRow[] = [];
  appData.templates.forEach((template, templateIndex) => {
    const templateID = stableID(template.genre);
    templateRows.push({
      event_id: eventID,
      template_id: templateID,
      genre: template.genre,
      title: template.title,
      max_score: template.maxScore,
      sort_order: templateIndex + 1,
    });
    template.criteria.forEach((criterion, criterionIndex) => {
      criterionRows.push({
        event_id: eventID,
        template_id: templateID,
        criterion_id: criterion.id,
        section: criterion.section,
        label: criterion.label,
        max_score: criterion.maxScore,
        sort_order: criterionIndex + 1,
      });
    });
  });

  await upsertRows("blocks", blockRows, "event_id,block_id");
  await upsertRows("routines", routineRows, "event_id,routine_id");
  await upsertRows("judges", judgeRows, "event_id,judge_id");
  await upsertRows("criteria_templates", templateRows, "event_id,template_id");
  await upsertRows("criteria", criterionRows, "event_id,template_id,criterion_id");
  if (options.activate) {
    await supabaseRequest("PATCH", "events?is_active=eq.true", { is_active: false }, "return=minimal");
    await supabaseRequest("PATCH", `events?id=eq.${encodeURIComponent(eventID)}`, { is_active: true }, "return=minimal");
  }
  return eventID;
}

async function deleteEventRows(eventID: string): Promise<void> {
  for (const table of ["penalties", "feedback", "scores", "criteria", "criteria_templates", "judges", "routines", "blocks"]) {
    await supabaseRequest("DELETE", `${table}?event_id=eq.${encodeURIComponent(eventID)}`, undefined, "return=minimal");
  }
}

async function deleteBlockRows(eventID: string, blockIDs: string[], forceReplace: boolean): Promise<void> {
  if (!blockIDs.length) {
    return;
  }
  if (!forceReplace && (
    await rowsExist("scores", eventID, blockIDs) ||
    await rowsExist("feedback", eventID, blockIDs) ||
    await rowsExist("penalties", eventID, blockIDs)
  )) {
    throw new HTTPError(409, "El bloque ya tiene puntajes, feedback o penalizaciones.");
  }
  const blockFilter = blockIDs.map(encodeURIComponent).join(",");
  await supabaseRequest(
    "DELETE",
    `routines?event_id=eq.${encodeURIComponent(eventID)}&block_id=in.(${blockFilter})`,
    undefined,
    "return=minimal",
  );
}

async function rowsExist(table: string, eventID: string, blockIDs: string[]): Promise<boolean> {
  const blockFilter = blockIDs.map(encodeURIComponent).join(",");
  const rows = await supabaseRequest(
    "GET",
    `${table}?select=event_id&event_id=eq.${encodeURIComponent(eventID)}&block_id=in.(${blockFilter})&limit=1`,
  ) as unknown[];
  return rows.length > 0;
}

async function eventRowsExist(table: string, eventID: string): Promise<boolean> {
  const rows = await supabaseRequest(
    "GET",
    `${table}?select=event_id&event_id=eq.${encodeURIComponent(eventID)}&limit=1`,
  ) as unknown[];
  return rows.length > 0;
}

async function upsertRows(table: string, rows: AnyRow[], conflict: string): Promise<void> {
  if (!rows.length) {
    return;
  }
  const query = new URLSearchParams({ on_conflict: conflict }).toString();
  for (let index = 0; index < rows.length; index += 500) {
    const chunk = rows.slice(index, index + 500);
    try {
      await supabaseRequest("POST", `${table}?${query}`, chunk, "resolution=merge-duplicates,return=minimal");
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      const fallbackColumns = table === "judges"
        ? ["role"]
        : table === "routines"
        ? ["participant"]
        : [];
      const missingColumns = fallbackColumns.filter((column) => detail.includes(column));
      if (!missingColumns.length) {
        throw error;
      }
      const fallbackChunk = chunk.map((row) => {
        const fallbackRow = { ...row };
        for (const column of missingColumns) {
          delete fallbackRow[column];
        }
        return fallbackRow;
      });
      await supabaseRequest("POST", `${table}?${query}`, fallbackChunk, "resolution=merge-duplicates,return=minimal");
    }
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
