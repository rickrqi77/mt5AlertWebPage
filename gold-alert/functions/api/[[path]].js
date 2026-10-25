/**
 * Proxy /api/* from alertdata.pages.dev to the gold-alert Worker.
 * Must be redeployed with `npm run pages:deploy` from gold-alert/
 * (Wrangler picks up ../functions relative to CWD).
 */
const WORKER_ORIGIN = "https://gold-alert.rick-rqi-apple.workers.dev";

export async function onRequest(context) {
  const incoming = context.request;
  const src = new URL(incoming.url);
  const dest = WORKER_ORIGIN + src.pathname + src.search;

  const headers = new Headers(incoming.headers);
  headers.delete("host");
  headers.set("x-forwarded-host", src.host);

  const init = {
    method: incoming.method,
    headers,
    redirect: "follow",
  };

  if (incoming.method !== "GET" && incoming.method !== "HEAD") {
    init.body = incoming.body;
  }

  try {
    const res = await fetch(dest, init);
    // Surface Worker outages as JSON instead of an opaque HTML 404.
    if (res.status === 404) {
      const ctype = res.headers.get("content-type") || "";
      if (!ctype.includes("application/json")) {
        return new Response(
          JSON.stringify({
            error: "API worker unavailable",
            detail: "gold-alert Worker returned non-JSON 404",
            upstream: WORKER_ORIGIN,
          }),
          {
            status: 502,
            headers: {
              "content-type": "application/json; charset=utf-8",
              "access-control-allow-origin": "*",
            },
          }
        );
      }
    }
    return res;
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: "API proxy failed",
        detail: String((err && err.message) || err),
        upstream: WORKER_ORIGIN,
      }),
      {
        status: 502,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "access-control-allow-origin": "*",
        },
      }
    );
  }
}
