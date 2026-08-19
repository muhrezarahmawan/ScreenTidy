/** Safe request log — never include OCR, images, or full payloads. */
export function logRequest(fields: {
  correlationId: string;
  status: number;
  latencyMs: number;
  model: string;
  route: string;
  errorCode?: string;
  upstreamHttpStatus?: number;
  upstreamType?: string;
  upstreamCode?: string;
  upstreamMessage?: string;
  upstreamRequestId?: string;
}): void {
  const line = {
    ts: new Date().toISOString(),
    route: fields.route,
    correlationId: fields.correlationId,
    status: fields.status,
    latencyMs: fields.latencyMs,
    model: fields.model,
    ...(fields.errorCode ? { errorCode: fields.errorCode } : {}),
    ...(fields.upstreamHttpStatus != null
      ? { upstreamHttpStatus: fields.upstreamHttpStatus }
      : {}),
    ...(fields.upstreamType ? { upstreamType: fields.upstreamType } : {}),
    ...(fields.upstreamCode ? { upstreamCode: fields.upstreamCode } : {}),
    ...(fields.upstreamMessage ? { upstreamMessage: fields.upstreamMessage } : {}),
    ...(fields.upstreamRequestId ? { upstreamRequestId: fields.upstreamRequestId } : {}),
  };
  console.log(JSON.stringify(line));
}

export function logInfo(message: string, extra?: Record<string, string | number | boolean>): void {
  console.log(JSON.stringify({ ts: new Date().toISOString(), level: "info", message, ...extra }));
}

export function logError(message: string, extra?: Record<string, string | number | boolean>): void {
  console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", message, ...extra }));
}
