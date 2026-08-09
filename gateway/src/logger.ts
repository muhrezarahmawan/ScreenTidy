/** Safe request log — never include OCR, images, or full payloads. */
export function logRequest(fields: {
  correlationId: string;
  status: number;
  latencyMs: number;
  model: string;
  route: string;
  errorCode?: string;
}): void {
  const line = {
    ts: new Date().toISOString(),
    route: fields.route,
    correlationId: fields.correlationId,
    status: fields.status,
    latencyMs: fields.latencyMs,
    model: fields.model,
    ...(fields.errorCode ? { errorCode: fields.errorCode } : {}),
  };
  console.log(JSON.stringify(line));
}

export function logInfo(message: string, extra?: Record<string, string | number | boolean>): void {
  console.log(JSON.stringify({ ts: new Date().toISOString(), level: "info", message, ...extra }));
}

export function logError(message: string, extra?: Record<string, string | number | boolean>): void {
  console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", message, ...extra }));
}
