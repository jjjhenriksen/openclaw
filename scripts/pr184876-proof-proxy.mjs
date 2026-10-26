// Fork-only loopback relay. Records RPC method/id only; never credentials or payloads.
import http from "node:http";
import { WebSocket, WebSocketServer } from "ws";
const receipts = [];
const connections = { A: { opened: 0, closed: 0, live: 0 }, B: { opened: 0, closed: 0, live: 0 } };
for (const [gateway, listenPort, backendPort] of [
  ["A", 19878, 19876],
  ["B", 19879, 19877],
]) {
  const server = http.createServer((request, response) => {
    const upstream = http.request(
      {
        hostname: "127.0.0.1",
        port: backendPort,
        path: request.url,
        method: request.method,
        headers: request.headers,
      },
      (remote) => {
        response.writeHead(remote.statusCode, remote.headers);
        remote.pipe(response);
      },
    );
    upstream.on("error", () => {
      response.writeHead(502);
      response.end();
    });
    request.pipe(upstream);
  });
  const sockets = new WebSocketServer({ noServer: true });
  server.on("upgrade", (request, socket, head) =>
    sockets.handleUpgrade(request, socket, head, (client) => {
      connections[gateway].opened++;
      connections[gateway].live++;
      const backend = new WebSocket(`ws://127.0.0.1:${backendPort}${request.url}`, {
        headers: request.headers.origin ? { origin: request.headers.origin } : {},
      });
      const pending = [];
      const forward = (data, binary) => {
        let frame;
        try {
          frame = JSON.parse(data.toString());
        } catch {}
        if (frame?.type === "req") {
          receipts.push({ gateway, method: frame.method, id: String(frame.id) });
          // No model generation is permitted in this navigation proof, even on failure.
          if (frame.method === "chat.send" || frame.method === "agent") {
            client.send(
              JSON.stringify({
                type: "res",
                id: frame.id,
                ok: false,
                error: {
                  code: "INVALID_REQUEST",
                  message: "Model generation disabled in navigation proof",
                },
              }),
            );
            return;
          }
        }
        backend.send(data, { binary });
      };
      client.on("message", (data, binary) =>
        backend.readyState === WebSocket.OPEN
          ? forward(data, binary)
          : pending.push([data, binary]),
      );
      backend.on("open", () => {
        for (const args of pending) forward(...args);
        pending.length = 0;
      });
      backend.on("message", (data, binary) => {
        if (client.readyState === WebSocket.OPEN) client.send(data, { binary });
      });
      backend.on("error", () => client.close());
      client.on("error", () => backend.close());
      backend.on("close", () => client.close());
      client.on("close", () => {
        connections[gateway].closed++;
        connections[gateway].live--;
        backend.close();
      });
    }),
  );
  server.listen(listenPort, "127.0.0.1");
}
http
  .createServer((request, response) => {
    response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
    response.end(JSON.stringify({ requests: receipts, connections }));
  })
  .listen(19880, "127.0.0.1");
