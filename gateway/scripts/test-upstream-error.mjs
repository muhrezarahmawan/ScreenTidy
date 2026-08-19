import assert from "node:assert/strict";
import { BadRequestError, AuthenticationError } from "openai";
import { mapOpenAIFailure } from "../src/openaiClient.js";
import {
  extractSanitizedUpstreamError,
  sanitizeUpstreamMessage,
} from "../src/upstreamError.js";

function testSanitize() {
  assert.equal(
    sanitizeUpstreamMessage("bad key sk-abc1234567890xyz in message"),
    "bad key [redacted] in message"
  );
  const long = "x".repeat(400);
  assert.ok((sanitizeUpstreamMessage(long) || "").endsWith("…"));
}

function testMapAuth() {
  const err = new AuthenticationError(401, { message: "Incorrect API key", type: "invalid_request_error", code: "invalid_api_key" }, "Incorrect API key", undefined);
  const mapped = mapOpenAIFailure(err);
  assert.equal(mapped.code, "UPSTREAM_AUTH");
  assert.equal(mapped.upstream?.httpStatus, 401);
  assert.equal(mapped.upstream?.code, "invalid_api_key");
}

function testMapBadRequest() {
  const err = new BadRequestError(
    400,
    {
      message: "Invalid schema for response_format",
      type: "invalid_request_error",
      code: "invalid_json_schema",
      param: "text.format.schema",
    },
    "Invalid schema",
    undefined
  );
  const mapped = mapOpenAIFailure(err);
  assert.equal(mapped.code, "UPSTREAM_CLIENT_ERROR");
  assert.equal(mapped.upstream?.httpStatus, 400);
  assert.equal(mapped.upstream?.code, "invalid_json_schema");
  assert.match(mapped.message, /Invalid schema/i);
}

function testExtract() {
  const err = new BadRequestError(
    400,
    { message: "model not found", type: "invalid_request_error", code: "model_not_found" },
    "model not found",
    undefined
  );
  const up = extractSanitizedUpstreamError(err);
  assert.equal(up?.httpStatus, 400);
  assert.equal(up?.code, "model_not_found");
}

testSanitize();
testMapAuth();
testMapBadRequest();
testExtract();
console.log("upstream-error tests ok");
