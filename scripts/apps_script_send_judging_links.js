/**
 * Google Apps Script Web App endpoint for the Jueceo app.
 *
 * Script properties:
 * - JUDGING_MAIL_SHARED_SECRET: optional. If set, it must match the app config.
 *
 * Uses Drive API through UrlFetchApp to grant folder permissions without Google
 * sending one notification email per shared item.
 *
 * Deploy as Web App:
 * - Execute as: Me
 * - Who has access: Anyone with the link
 */

const JUDGING_MAIL_SCRIPT_VERSION = "folder-sharing-v2";

function authorizeJudgingMailScript() {
  PropertiesService.getScriptProperties().getProperty("JUDGING_MAIL_SHARED_SECRET");
  DriveApp.getRootFolder().getName();
  UrlFetchApp.fetch("https://www.googleapis.com/drive/v3/about?fields=user", {
    method: "get",
    headers: {
      Authorization: `Bearer ${ScriptApp.getOAuthToken()}`
    },
    muteHttpExceptions: true
  });
  MailApp.getRemainingDailyQuota();
  return `Autorizado ${JUDGING_MAIL_SCRIPT_VERSION}`;
}

function doPost(event) {
  try {
    const payload = JSON.parse((event.postData && event.postData.contents) || "{}");
    authorizeRequest(payload.sharedSecret);

    const academies = Array.isArray(payload.academies) ? payload.academies : [];
    if (academies.length === 0) {
      throw new Error("No hay academias para enviar.");
    }

    const results = academies.map((academyPayload) => sendAcademyMail(payload, academyPayload));
    const failed = results.filter((result) => !result.ok);
    const skipped = results.filter((result) => result.skipped);
    const sent = results.filter((result) => result.ok && !result.skipped).length;
    const warnings = results.flatMap((result) => result.warnings || []);
    return jsonResponse({
      ok: sent > 0,
      version: JUDGING_MAIL_SCRIPT_VERSION,
      sent,
      skipped: skipped.length,
      results,
      warnings,
      errors: failed.map((result) => result.message)
    });
  } catch (error) {
    return jsonResponse({
      ok: false,
      version: JUDGING_MAIL_SCRIPT_VERSION,
      sent: 0,
      message: error.message || String(error)
    });
  }
}

function authorizeRequest(receivedSecret) {
  const expectedSecret = PropertiesService.getScriptProperties().getProperty("JUDGING_MAIL_SHARED_SECRET");
  if (expectedSecret && receivedSecret !== expectedSecret) {
    throw new Error("Clave de envío inválida.");
  }
}

function sendAcademyMail(payload, academyPayload) {
  try {
    const email = cleanText(academyPayload.email);
    const academy = cleanText(academyPayload.academy);
    const links = Array.isArray(academyPayload.links) ? academyPayload.links : [];
    const availableLinks = links.filter((link) => cleanText(link.url));

    if (!email || email.indexOf("@") === -1) {
      throw new Error(`Email inválido para ${academy || "academia"}.`);
    }
    if (availableLinks.length === 0) {
      return {
        ok: true,
        skipped: true,
        academy,
        email,
        links: 0,
        message: `Sin links disponibles para ${academy || email}.`
      };
    }

    const accessGrant = payload.grantDriveAccess
      ? grantDriveAccess(email, availableLinks)
      : { warnings: [], folders: [] };
    if (payload.grantDriveAccess && accessGrant.folders.length === 0) {
      throw new Error(`No se pudo compartir ninguna carpeta para ${academy || email}. ${accessGrant.warnings[0] || ""}`.trim());
    }
    const mailPayload = Object.assign({}, academyPayload, {
      links: availableLinks,
      folders: accessGrant.folders
    });

    MailApp.sendEmail({
      to: email,
      subject: payload.subject || "Tu devolución de jueceo ya está disponible",
      body: buildTextBody(payload, mailPayload),
      htmlBody: buildHtmlBody(payload, mailPayload)
    });

    return {
      ok: true,
      academy,
      email,
      links: availableLinks.length,
      sharedFolders: accessGrant.folders.length,
      warnings: accessGrant.warnings
    };
  } catch (error) {
    return {
      ok: false,
      academy: cleanText(academyPayload.academy),
      email: cleanText(academyPayload.email),
      message: error.message || String(error)
    };
  }
}

function grantDriveAccess(email, links) {
  const warnings = [];
  const routineFolders = routineFoldersFromLinks(links, warnings);
  const sharedFolders = [];

  routineFolders.forEach((folder) => {
    try {
      shareDriveItemSilently(folder.id, email);
      sharedFolders.push(folder);
    } catch (error) {
      warnings.push(`No se pudo compartir la carpeta ${folder.name || folder.id}: ${error.message || String(error)}`);
    }
  });

  return { warnings, folders: sharedFolders };
}

function routineFoldersFromLinks(links, warnings) {
  const foldersByID = {};
  links.forEach((link) => {
    const fileID = cleanText(link.fileID);
    if (!fileID) {
      warnings.push(`Link sin fileID para ${cleanText(link.routineName) || cleanText(link.fileName) || "hoja de jueceo"}.`);
      return;
    }
    try {
      const file = DriveApp.getFileById(fileID);
      const parents = file.getParents();
      if (!parents.hasNext()) {
        warnings.push(`No se encontró carpeta padre para ${cleanText(link.fileName) || fileID}.`);
        return;
      }
      const folder = parents.next();
      const folderID = folder.getId();
      if (!foldersByID[folderID]) {
        foldersByID[folderID] = {
          id: folderID,
          name: folder.getName(),
          url: folder.getUrl(),
          routineID: cleanText(link.routineID),
          routineName: cleanText(link.routineName)
        };
      }
    } catch (error) {
      warnings.push(`No se pudo ubicar carpeta para ${cleanText(link.fileName) || fileID}: ${error.message || String(error)}`);
    }
  });

  return Object.keys(foldersByID)
    .map((folderID) => foldersByID[folderID])
    .sort((left, right) => folderTitle(left).localeCompare(folderTitle(right)));
}

function shareDriveItemSilently(itemID, email) {
  const permission = {
    role: "reader",
    type: "user",
    emailAddress: email
  };

  if (typeof Drive !== "undefined" && Drive.Permissions && Drive.Permissions.create) {
    try {
      Drive.Permissions.create(permission, itemID, {
        sendNotificationEmail: false,
        supportsAllDrives: true,
        fields: "id"
      });
      return;
    } catch (error) {
      if (isExistingPermissionError(error)) {
        return;
      }
      throw error;
    }
  }

  shareDriveItemSilentlyWithFetch(itemID, permission);
}

function shareDriveItemSilentlyWithFetch(itemID, permission) {
  const endpoint = `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(itemID)}/permissions`
    + "?sendNotificationEmail=false&supportsAllDrives=true&fields=id";

  let response;
  try {
    response = UrlFetchApp.fetch(endpoint, {
      method: "post",
      contentType: "application/json; charset=utf-8",
      headers: {
        Authorization: `Bearer ${ScriptApp.getOAuthToken()}`
      },
      muteHttpExceptions: true,
      payload: JSON.stringify(permission)
    });
  } catch (error) {
    if (isMissingUrlFetchAuthorizationError(error)) {
      throw new Error("Falta autorizar UrlFetchApp en Apps Script. Pegá el manifest de scripts/appsscript.json, guardá, ejecutá authorizeJudgingMailScript una vez y volvé a desplegar.");
    }
    throw error;
  }
  const statusCode = response.getResponseCode();
  if (statusCode >= 200 && statusCode < 300) {
    return;
  }

  const responseText = response.getContentText();
  if (statusCode === 409 || /already|duplicate|exists|ya tiene|ya existe/i.test(responseText)) {
    return;
  }
  throw new Error(driveAPIErrorMessage(responseText) || `Drive API devolvió HTTP ${statusCode}.`);
}

function isExistingPermissionError(error) {
  return /already|duplicate|exists|ya tiene|ya existe/i.test(error.message || String(error));
}

function isMissingUrlFetchAuthorizationError(error) {
  return /UrlFetchApp\.fetch|script\.external_request|No cuentas con el permiso|Authorization is required/i.test(error.message || String(error));
}

function driveAPIErrorMessage(responseText) {
  try {
    const parsed = JSON.parse(responseText);
    return parsed && parsed.error && parsed.error.message ? parsed.error.message : "";
  } catch (error) {
    return cleanText(responseText);
  }
}

function folderTitle(folder) {
  const routine = `#${cleanText(folder.routineID)} ${cleanText(folder.routineName)}`.trim();
  return routine || cleanText(folder.name) || cleanText(folder.id);
}

function buildTextBody(payload, academyPayload) {
  const academy = cleanText(academyPayload.academy);
  const folders = academyPayload.folders || [];
  const links = academyPayload.links || [];
  const accessLines = folders.length > 0 ? folders.map((folder) => {
    return `- ${folderTitle(folder)}: ${cleanText(folder.url)}`;
  }).join("\n") : links.map((link) => {
    const routine = `#${cleanText(link.routineID)} ${cleanText(link.routineName)}`.trim();
    const judge = cleanText(link.judge);
    return `- ${routine}${judge ? ` - ${judge}` : ""}: ${cleanText(link.url)}`;
  }).join("\n");

  return [
    `Hola, equipo de ${academy}.`,
    "",
    cleanText(payload.bodyIntro),
    "",
    "Pueden acceder a sus hojas desde estos links:",
    "",
    accessLines,
    "",
    cleanText(payload.bodyClosing)
  ].join("\n");
}

function buildHtmlBody(payload, academyPayload) {
  const academy = cleanText(academyPayload.academy);
  const folders = academyPayload.folders || [];
  const links = academyPayload.links || [];
  const accessItems = folders.length > 0 ? folders.map((folder) => {
    return `<li><a href="${escapeHtml(cleanText(folder.url))}">${escapeHtml(folderTitle(folder))}</a></li>`;
  }).join("") : links.map((link) => {
    const routine = `#${cleanText(link.routineID)} ${cleanText(link.routineName)}`.trim();
    const judge = cleanText(link.judge);
    const title = `${routine}${judge ? ` - ${judge}` : ""}`;
    return `<li><a href="${escapeHtml(cleanText(link.url))}">${escapeHtml(title)}</a></li>`;
  }).join("");

  return [
    `<p>Hola, equipo de <strong>${escapeHtml(academy)}</strong>.</p>`,
    paragraphs(payload.bodyIntro),
    "<p>Pueden acceder a sus hojas desde estos links:</p>",
    `<ul>${accessItems}</ul>`,
    paragraphs(payload.bodyClosing)
  ].join("\n");
}

function paragraphs(text) {
  return cleanText(text)
    .split(/\n{2,}/)
    .map((paragraph) => `<p>${escapeHtml(paragraph).replace(/\n/g, "<br>")}</p>`)
    .join("\n");
}

function cleanText(value) {
  return value === null || value === undefined ? "" : String(value).trim();
}

function escapeHtml(value) {
  return cleanText(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function jsonResponse(body) {
  return ContentService
    .createTextOutput(JSON.stringify(body))
    .setMimeType(ContentService.MimeType.JSON);
}
