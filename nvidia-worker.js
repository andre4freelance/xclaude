// nvidia-worker.js — Cloudflare Worker that lets Claude Code (Anthropic
// Messages API) talk to NVIDIA NIM's free OpenAI-compatible API.
//
// It translates, in both directions:
//   Anthropic /v1/messages  <->  OpenAI /v1/chat/completions
// including streaming (SSE), tool calls, tool results, images, and system
// prompts — everything Claude Code actually uses.
//
// Deploy (no local install): Cloudflare dashboard -> Workers & Pages ->
// Create Worker -> paste this file -> Deploy. Then add these variables under
// Settings -> Variables and Secrets:
//   NVIDIA_API_KEY  (secret)  your nvapi-... key
//   NVIDIA_MODEL    (text)    e.g. z-ai/glm-5.2   (optional; forces the model)
//   PROXY_KEY       (secret)  any password (optional; blocks strangers)
// In Claude Code / the xclaude wrapper set:
//   base URL = https://<your-worker>.workers.dev
//   API key  = the PROXY_KEY you chose (or anything, if you left it unset)
//   model    = z-ai/glm-5.2  (used only if NVIDIA_MODEL is not set)

const NVIDIA_URL = "https://integrate.api.nvidia.com/v1/chat/completions";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, GET, OPTIONS",
  "access-control-allow-headers": "*",
};

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "GET" && path === "/") {
      return json({ ok: true, service: "nvidia-anthropic-proxy" });
    }

    // Optional access control: require the caller's key to match PROXY_KEY.
    if (env.PROXY_KEY) {
      const auth = request.headers.get("authorization") || "";
      const xkey = request.headers.get("x-api-key") || "";
      const presented = auth.replace(/^Bearer\s+/i, "") || xkey;
      if (presented !== env.PROXY_KEY) {
        return anthropicError(401, "authentication_error", "invalid proxy key");
      }
    }
    if (!env.NVIDIA_API_KEY) {
      return anthropicError(500, "api_error", "NVIDIA_API_KEY is not set on the Worker");
    }

    // Claude Code asks the endpoint to count tokens; give a rough estimate.
    if (path.endsWith("/count_tokens")) {
      const body = await safeJson(request);
      return json({ input_tokens: estimateTokens(body) });
    }

    if (request.method !== "POST" || !path.endsWith("/messages")) {
      return anthropicError(404, "not_found_error", "unknown path: " + path);
    }

    const body = await safeJson(request);
    if (!body) return anthropicError(400, "invalid_request_error", "bad JSON body");

    const model = env.NVIDIA_MODEL || stripSuffix(body.model) || "z-ai/glm-5.2";
    const oaiReq = toOpenAI(body, model);

    let upstream;
    try {
      upstream = await fetch(NVIDIA_URL, {
        method: "POST",
        headers: {
          authorization: "Bearer " + env.NVIDIA_API_KEY,
          "content-type": "application/json",
          accept: oaiReq.stream ? "text/event-stream" : "application/json",
        },
        body: JSON.stringify(oaiReq),
      });
    } catch (e) {
      return anthropicError(502, "api_error", "cannot reach NVIDIA: " + e);
    }

    if (!upstream.ok) {
      const text = await upstream.text();
      return anthropicError(upstream.status, "api_error", "NVIDIA " + upstream.status + ": " + text.slice(0, 500));
    }

    if (oaiReq.stream) {
      return new Response(openaiStreamToAnthropic(upstream.body, model), {
        headers: { "content-type": "text/event-stream; charset=utf-8", "cache-control": "no-cache", ...CORS },
      });
    }
    const oai = await upstream.json();
    return json(openaiToAnthropic(oai, model));
  },
};

// ---- request: Anthropic -> OpenAI ------------------------------------------

function toOpenAI(body, model) {
  const messages = [];
  if (body.system) messages.push({ role: "system", content: textFrom(body.system) });

  for (const msg of body.messages || []) {
    if (typeof msg.content === "string") {
      messages.push({ role: msg.role, content: msg.content });
      continue;
    }
    const blocks = Array.isArray(msg.content) ? msg.content : [];
    if (msg.role === "assistant") {
      let text = "";
      const toolCalls = [];
      for (const b of blocks) {
        if (b.type === "text") text += b.text || "";
        else if (b.type === "tool_use")
          toolCalls.push({
            id: b.id,
            type: "function",
            function: { name: b.name, arguments: JSON.stringify(b.input || {}) },
          });
      }
      const m = { role: "assistant", content: text || null };
      if (toolCalls.length) m.tool_calls = toolCalls;
      messages.push(m);
    } else {
      // user turn: tool_result blocks become `tool` messages; the rest is user content
      const parts = [];
      for (const b of blocks) {
        if (b.type === "tool_result") {
          messages.push({ role: "tool", tool_call_id: b.tool_use_id, content: textFrom(b.content) });
        } else if (b.type === "text") {
          parts.push({ type: "text", text: b.text || "" });
        } else if (b.type === "image" && b.source) {
          parts.push({ type: "image_url", image_url: { url: `data:${b.source.media_type};base64,${b.source.data}` } });
        }
      }
      if (parts.length) {
        const onlyText = parts.length === 1 && parts[0].type === "text";
        messages.push({ role: "user", content: onlyText ? parts[0].text : parts });
      }
    }
  }

  const out = { model, messages, stream: !!body.stream };
  if (body.max_tokens) out.max_tokens = body.max_tokens;
  if (typeof body.temperature === "number") out.temperature = body.temperature;
  if (typeof body.top_p === "number") out.top_p = body.top_p;
  if (body.stop_sequences) out.stop = body.stop_sequences;
  if (out.stream) out.stream_options = { include_usage: true };

  if (Array.isArray(body.tools) && body.tools.length) {
    out.tools = body.tools
      .filter((t) => t && t.name)
      .map((t) => ({ type: "function", function: { name: t.name, description: t.description || "", parameters: t.input_schema || { type: "object", properties: {} } } }));
    const tc = body.tool_choice;
    if (tc) {
      if (tc.type === "auto") out.tool_choice = "auto";
      else if (tc.type === "any") out.tool_choice = "required";
      else if (tc.type === "tool" && tc.name) out.tool_choice = { type: "function", function: { name: tc.name } };
    }
  }
  return out;
}

// ---- response (non-stream): OpenAI -> Anthropic ----------------------------

function openaiToAnthropic(oai, model) {
  const choice = (oai.choices && oai.choices[0]) || {};
  const msg = choice.message || {};
  const content = [];
  if (msg.content) content.push({ type: "text", text: msg.content });
  for (const tc of msg.tool_calls || []) {
    content.push({ type: "tool_use", id: tc.id || genId("toolu"), name: tc.function?.name, input: safeParse(tc.function?.arguments) });
  }
  if (content.length === 0) content.push({ type: "text", text: "" });
  return {
    id: genId("msg"),
    type: "message",
    role: "assistant",
    model,
    content,
    stop_reason: mapFinish(choice.finish_reason),
    stop_sequence: null,
    usage: { input_tokens: oai.usage?.prompt_tokens || 0, output_tokens: oai.usage?.completion_tokens || 0 },
  };
}

// ---- response (stream): OpenAI SSE -> Anthropic SSE ------------------------

function openaiStreamToAnthropic(readable, model) {
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  const msgId = genId("msg");
  let buffer = "";
  let started = false;
  let blockOpen = false;
  let blockType = null; // "text" | "tool"
  let anthIndex = -1;
  const toolIndexMap = new Map(); // openai tool index -> anthropic block index
  let usage = { input_tokens: 0, output_tokens: 0 };
  let stopReason = "end_turn";

  const sse = (event, data) => enc.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);

  return new ReadableStream({
    async start(controller) {
      const send = (event, data) => controller.enqueue(sse(event, data));
      const openBlock = (type, extra) => {
        if (blockOpen) { send("content_block_stop", { type: "content_block_stop", index: anthIndex }); blockOpen = false; }
        anthIndex++;
        blockType = type;
        blockOpen = true;
        const cb = type === "text" ? { type: "text", text: "" } : { type: "tool_use", id: extra.id, name: extra.name, input: {} };
        send("content_block_start", { type: "content_block_start", index: anthIndex, content_block: cb });
      };

      send("message_start", {
        type: "message_start",
        message: { id: msgId, type: "message", role: "assistant", model, content: [], stop_reason: null, stop_sequence: null, usage },
      });
      started = true;

      const reader = readable.getReader();
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += dec.decode(value, { stream: true });
          let nl;
          while ((nl = buffer.indexOf("\n")) !== -1) {
            const line = buffer.slice(0, nl).trim();
            buffer = buffer.slice(nl + 1);
            if (!line.startsWith("data:")) continue;
            const payload = line.slice(5).trim();
            if (payload === "[DONE]") continue;
            let chunk;
            try { chunk = JSON.parse(payload); } catch { continue; }
            if (chunk.usage) {
              usage = { input_tokens: chunk.usage.prompt_tokens || usage.input_tokens, output_tokens: chunk.usage.completion_tokens || usage.output_tokens };
            }
            const choice = (chunk.choices && chunk.choices[0]) || {};
            const delta = choice.delta || {};

            if (typeof delta.content === "string" && delta.content.length) {
              if (!blockOpen || blockType !== "text") openBlock("text");
              send("content_block_delta", { type: "content_block_delta", index: anthIndex, delta: { type: "text_delta", text: delta.content } });
            }
            for (const tc of delta.tool_calls || []) {
              const oaiIdx = tc.index ?? 0;
              if (!toolIndexMap.has(oaiIdx)) {
                openBlock("tool", { id: tc.id || genId("toolu"), name: tc.function?.name || "" });
                toolIndexMap.set(oaiIdx, anthIndex);
              }
              const args = tc.function?.arguments;
              if (args) send("content_block_delta", { type: "content_block_delta", index: toolIndexMap.get(oaiIdx), delta: { type: "input_json_delta", partial_json: args } });
            }
            if (choice.finish_reason) stopReason = mapFinish(choice.finish_reason);
          }
        }
      } catch (e) {
        // fall through to close the stream cleanly
      }

      if (blockOpen) send("content_block_stop", { type: "content_block_stop", index: anthIndex });
      send("message_delta", { type: "message_delta", delta: { stop_reason: stopReason, stop_sequence: null }, usage });
      send("message_stop", { type: "message_stop" });
      controller.close();
    },
  });
}

// ---- helpers ---------------------------------------------------------------

function mapFinish(r) {
  if (r === "tool_calls") return "tool_use";
  if (r === "length") return "max_tokens";
  if (r === "stop") return "end_turn";
  return r ? "end_turn" : "end_turn";
}

function textFrom(x) {
  if (typeof x === "string") return x;
  if (Array.isArray(x)) return x.map((b) => (typeof b === "string" ? b : b.text || (b.type === "text" ? b.text : ""))).join("");
  if (x && typeof x === "object" && x.text) return x.text;
  return x == null ? "" : String(x);
}

function stripSuffix(m) { return typeof m === "string" ? m.replace(/\[1m\]$/, "") : m; }
function safeParse(s) { try { return JSON.parse(s || "{}"); } catch { return {}; } }
function genId(prefix) { return prefix + "_" + crypto.randomUUID().replace(/-/g, "").slice(0, 24); }
function estimateTokens(body) {
  const s = JSON.stringify(body || {});
  return Math.max(1, Math.ceil(s.length / 4));
}
async function safeJson(req) { try { return await req.json(); } catch { return null; } }
function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", ...CORS } });
}
function anthropicError(status, type, message) {
  return json({ type: "error", error: { type, message } }, status);
}
