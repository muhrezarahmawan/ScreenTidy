/**
 * Lightweight image dimension probe (JPEG / PNG / WebP / GIF).
 * In-memory only — never writes to disk.
 */

export type ImageProbe = {
  width: number;
  height: number;
  mimeType: string;
  longEdge: number;
  byteLength: number;
};

export class ImageValidationError extends Error {
  code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

export function decodeBase64Image(imageBase64: string): Buffer {
  const cleaned = imageBase64.includes(",")
    ? imageBase64.slice(imageBase64.indexOf(",") + 1)
    : imageBase64;
  try {
    return Buffer.from(cleaned, "base64");
  } catch {
    throw new ImageValidationError("IMAGE_DECODE_FAILED", "imageBase64 is not valid base64");
  }
}

export function probeImage(buffer: Buffer, declaredMime?: string): ImageProbe {
  const dims =
    readPng(buffer) ??
    readJpeg(buffer) ??
    readGif(buffer) ??
    readWebp(buffer);

  if (!dims) {
    throw new ImageValidationError(
      "IMAGE_UNSUPPORTED",
      "Unsupported or corrupt image (expected JPEG, PNG, WebP, or GIF)"
    );
  }

  const mimeType =
    declaredMime && declaredMime.startsWith("image/")
      ? declaredMime
      : dims.mimeType;

  return {
    width: dims.width,
    height: dims.height,
    mimeType,
    longEdge: Math.max(dims.width, dims.height),
    byteLength: buffer.length,
  };
}

export function assertImageWithinBounds(
  probe: ImageProbe,
  longEdgeMax: number,
  maxBytes = 5 * 1024 * 1024
): void {
  if (probe.byteLength > maxBytes) {
    throw new ImageValidationError(
      "IMAGE_BYTE_LIMIT",
      `Image exceeds ${maxBytes} byte limit`
    );
  }
  if (probe.longEdge > longEdgeMax) {
    throw new ImageValidationError(
      "IMAGE_LONG_EDGE",
      `Image long edge ${probe.longEdge} exceeds IMAGE_LONG_EDGE_MAX (${longEdgeMax})`
    );
  }
  if (probe.width < 1 || probe.height < 1) {
    throw new ImageValidationError("IMAGE_INVALID_DIMENSIONS", "Invalid image dimensions");
  }
}

export function toDataUrl(mimeType: string, buffer: Buffer): string {
  return `data:${mimeType};base64,${buffer.toString("base64")}`;
}

function readPng(buf: Buffer): { width: number; height: number; mimeType: string } | null {
  if (buf.length < 24) return null;
  if (buf.toString("ascii", 1, 4) !== "PNG") return null;
  if (buf[0] !== 0x89) return null;
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
    mimeType: "image/png",
  };
}

function readJpeg(buf: Buffer): { width: number; height: number; mimeType: string } | null {
  if (buf.length < 4 || buf[0] !== 0xff || buf[1] !== 0xd8) return null;
  let i = 2;
  while (i + 9 < buf.length) {
    if (buf[i] !== 0xff) {
      i += 1;
      continue;
    }
    const marker = buf[i + 1];
    if (marker === 0xd9 || marker === 0xda) break;
    const len = buf.readUInt16BE(i + 2);
    if (len < 2) break;
    // SOF0 / SOF2 baseline/progressive
    if (
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf)
    ) {
      const height = buf.readUInt16BE(i + 5);
      const width = buf.readUInt16BE(i + 7);
      return { width, height, mimeType: "image/jpeg" };
    }
    i += 2 + len;
  }
  return null;
}

function readGif(buf: Buffer): { width: number; height: number; mimeType: string } | null {
  if (buf.length < 10) return null;
  const sig = buf.toString("ascii", 0, 6);
  if (sig !== "GIF87a" && sig !== "GIF89a") return null;
  return {
    width: buf.readUInt16LE(6),
    height: buf.readUInt16LE(8),
    mimeType: "image/gif",
  };
}

function readWebp(buf: Buffer): { width: number; height: number; mimeType: string } | null {
  if (buf.length < 30) return null;
  if (buf.toString("ascii", 0, 4) !== "RIFF") return null;
  if (buf.toString("ascii", 8, 12) !== "WEBP") return null;
  const chunk = buf.toString("ascii", 12, 16);
  if (chunk === "VP8X" && buf.length >= 30) {
    const width = 1 + buf.readUIntLE(24, 3);
    const height = 1 + buf.readUIntLE(27, 3);
    return { width, height, mimeType: "image/webp" };
  }
  if (chunk === "VP8 " && buf.length >= 30) {
    // Lossy bitstream
    const width = buf.readUInt16LE(26) & 0x3fff;
    const height = buf.readUInt16LE(28) & 0x3fff;
    return { width, height, mimeType: "image/webp" };
  }
  if (chunk === "VP8L" && buf.length >= 25) {
    const bits = buf.readUInt32LE(21);
    const width = (bits & 0x3fff) + 1;
    const height = ((bits >> 14) & 0x3fff) + 1;
    return { width, height, mimeType: "image/webp" };
  }
  return null;
}
