import ws from 'k6/ws';
import http from 'k6/http';
import papaparse from 'https://jslib.k6.io/papaparse/5.1.1/index.js';
import { SharedArray } from 'k6/data';
import { Counter, Trend } from 'k6/metrics';

// k6 load test: opens WebSockets that subscribe like a real room page, and (after
// 30s) posts messages to exercise broadcast fan-out. Delivery is tracked via
// metrics rather than console.log so high message rates don't flood stdout and
// skew results. Parameterized via env (see README.md):
//   HOST, PORT (HTTP), WS_PORT (defaults to PORT), USERS (cookie pool),
//   RATE (new conns/sec), HOLD (sec/conn), VUS (max concurrency), DURATION, MSG_COUNT
// Steady-state concurrency ~= RATE * HOLD (capped by VUS).

const appendsReceived = new Counter('appends_received');     // real message broadcasts delivered to sockets
const subsConfirmed   = new Counter('subscriptions_confirmed');
const wsErrors        = new Counter('ws_errors');
const postDuration    = new Trend('message_post_duration', true);

// Signed Turbo stream names for room 1's `messages` stream and user 1's `rooms`
// stream (gid://sabha/..., SECRET_KEY_BASE=dummy). See test/performance/README.md.
const turboSignedStreamNames = [
  "InJvb21zIg==--54acd827f0a7db144c75316a9fc488c0a949f9635b1e47956ce1bd9d1cf2c41d",
  "IloybGtPaTh2YzJGaWFHRXZVbTl2YlhNNk9rTnNiM05sWkM4eDptZXNzYWdlcyI=--cb2cb75566e57c00ffee6a6c50e78ce5216e151422e03c11917e8fe4a1706fbd",
  "IloybGtPaTh2YzJGaWFHRXZWWE5sY2k4eDpyb29tcyI=--42a94033d5823d82bcafce1d88911270a1ca74f1eb015206bb4156166613dc12"
];

const dummyCookies = new SharedArray('cookies', function () {
  return papaparse.parse(open('cookies.txt'), { header: false }).data;
});

const host = __ENV.HOST == "localhost" ? "host.docker.internal" : __ENV.HOST;
const port = __ENV.PORT ? `:${__ENV.PORT}` : "";              // HTTP (Rails): /rooms, /messages
const wsPort = __ENV.WS_PORT ? `:${__ENV.WS_PORT}` : port;    // WS: :3000 (ActionCable) or :8080 (anycable-go)
const users = parseInt(__ENV.USERS || '500');           // cookie pool size to draw from
const duration = __ENV.DURATION || '60s';
const msgCount = parseInt(__ENV.MSG_COUNT || '100');
const holdSeconds = parseInt(__ENV.HOLD || '50');       // how long each socket stays open
// Establishment rate (new conns/sec) decoupled from target concurrency.
// Steady-state concurrency ~= RATE * HOLD. VUS caps the plateau.
const rate = parseInt(__ENV.RATE || String(Math.ceil(users / 3.0)));
const vus = parseInt(__ENV.VUS || String(users));

export const options = {
  discardResponseBodies: true,
  scenarios: {
    sockets: {
      executor: 'constant-arrival-rate',
      duration: duration,
      rate: rate,
      timeUnit: '1s',
      preAllocatedVUs: vus,
      maxVUs: vus,
      env: { SCENARIO: 'sockets' },
      gracefulStop: "2s"
    },
    messages: {
      executor: 'shared-iterations',
      iterations: 1,
      vus: 1,
      startTime: '30s',
      env: { SCENARIO: 'messages' },
      gracefulStop: "10s"
    },
  },
};

export default function() {
  if (__ENV.SCENARIO == 'sockets') {
    sockets();
  } else if (__ENV.SCENARIO == 'messages') {
    messages();
  }
}

export function sockets() {
  const cookie = dummyCookies[Math.floor(Math.random() * users)][0];
  const url = `ws://${host}${wsPort}/cable`;
  const params = {
    headers: { 'Origin': `http://localhost`, 'Cookie': `session_token=${cookie}` }
  };

  ws.connect(url, params, function(socket) {
    socket.on('open', function open() {
      socket.send(JSON.stringify({ command: 'subscribe', identifier: '{"channel":"PresenceChannel", "room_id":1}' }));
      socket.send(JSON.stringify({ command: 'subscribe', identifier: '{"channel":"UserUnreadRoomsChannel"}' }));
      socket.send(JSON.stringify({ command: 'subscribe', identifier: '{"channel":"HeartbeatChannel"}' }));
      turboSignedStreamNames.forEach((signedStreamName) => {
        socket.send(JSON.stringify({ command: 'subscribe', identifier: `{"channel":"Turbo::StreamsChannel", "signed_stream_name":"${signedStreamName}"}` }));
      });

      socket.on('message', function(message) {
        if (message.includes("confirm_subscription")) {
          subsConfirmed.add(1);
        } else if (message.includes("append")) {
          appendsReceived.add(1);
        }
      });

      // Hold the connection open for the steady-state window, then close cleanly.
      socket.setTimeout(function () { socket.close(); }, holdSeconds * 1000);
    });

    socket.on('error', function(e) {
      if (e.error() != 'websocket: close sent') {
        wsErrors.add(1);
        console.log('ws error: ', e.error());
      }
    });
  });
}

export function messages() {
  const cookie = `session_token=${dummyCookies[0][0]}`;

  const response = http.get(`http://${host}${port}/rooms/1`, { headers: { "Cookie": cookie }, responseType: "text" });
  const m = response.body && response.body.match(/<meta name="csrf-token" content="([^"]*)"/i);
  if (!m) { console.log(`messages: could not read csrf token (status ${response.status})`); return; }
  const csrfToken = m[1];

  const postHeaders = {
    "Cookie": cookie,
    "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
  };

  for (let i = 0; i < msgCount; i++) {
    const payload = {
      "message[body]": `Hello from k6 #${i}`,
      "message[client_message_id]": `${i}-${Math.random().toString(36)}`,
      "authenticity_token": csrfToken
    };
    const res = http.post(`http://${host}${port}/rooms/1/messages`, payload, { headers: postHeaders, responseType: "text" });
    postDuration.add(res.timings.duration);
  }
}
