// 串口 ↔ WebSocket 桥接:游戏(Godot Robot autoload)连 ws://127.0.0.1:9800,
// 本进程把 JSON 行双向透传给 /dev/cu.usbmodem*(ESP32-S3 小机)。
// 客户端发来的消息若本身带 "evt" 键(如语音助手的 {"evt":"speech"}),视为上行事件,
// 只转发给其它客户端、不下串口;串口打开/断开也广播 {"evt":"serial","open":bool}。
// 自愈:固件掉回 MicroPython REPL 时(崩溃、Ctrl-C、mpremote 拷完没复位),我们的 JSON 行会被 REPL 当表达式吃掉并回显
// ">>> {...}";看到 REPL 提示符就发 Ctrl-B + Ctrl-D 软复位重跑 main.py;空闲 5 s 没收到板子任何输出就 ping 一次,
// 让 REPL 状态一定能被回显暴露出来。
// 用法: npm run bridge   (可选环境变量 SERIAL_PORT / BRIDGE_PORT)
import { SerialPort } from "serialport";
import { ReadlineParser } from "@serialport/parser-readline";
import { WebSocketServer } from "ws";

const WS_PORT = Number(process.env.BRIDGE_PORT ?? 9800);
const BAUD = 115200;
const RETRY_MS = 2000;
const IDLE_PING_MS = 5000;     // 板子多久没吭声就 ping(看门狗)
const REPL_KICK_MIN_MS = 3000; // 两次软复位之间的最小间隔(复位自己也会打印几行 >>>)

let serial = null;
let lastRx = 0;
let lastKick = 0;
const wss = new WebSocketServer({ host: "127.0.0.1", port: WS_PORT });
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

wss.on("listening", () => log(`WebSocket 就绪 ws://127.0.0.1:${WS_PORT}`));
function isEvt(line) {
  try {
    const o = JSON.parse(line);
    return !!o && typeof o === "object" && "evt" in o;
  } catch {
    return false;
  }
}

wss.on("connection", (ws) => {
  log("客户端连入");
  ws.send(JSON.stringify({ evt: "serial", open: !!serial?.isOpen }));
  ws.on("message", (data) => {
    const line = data.toString().trim();
    if (!line) return;
    if (isEvt(line)) {   // 客户端注入的上行事件(语音助手)→ 只给其它客户端
      for (const c of wss.clients) if (c !== ws && c.readyState === 1) c.send(line);
      log("↔ ", line);
      return;
    }
    if (serial?.isOpen) {
      serial.write(line + "\n");
      log("» ", line);
    } else log("丢弃(串口未连):", line);
  });
  ws.on("close", () => log("客户端断开"));
});

function broadcast(line) {
  for (const c of wss.clients) if (c.readyState === 1) c.send(line);
}

async function pickPort() {
  if (process.env.SERIAL_PORT) return process.env.SERIAL_PORT;
  const ports = await SerialPort.list();
  // 优先原生 USB(usbmodem / Espressif);没有就用板子 UART 口的 USB 转串口(usbserial,FTDI/CP210x),
  // MicroPython 的控制台在两个口上都有
  const native = ports.find(
    (p) => p.path.includes("usbmodem") || /Espressif/i.test(p.manufacturer ?? "")
  );
  const uart = ports.find((p) => p.path.includes("usbserial"));   // serialport 列出的是 /dev/tty.*
  return native?.path ?? uart?.path ?? null;
}

async function connectSerial() {
  const path = await pickPort();
  if (!path) {
    setTimeout(connectSerial, RETRY_MS);
    return;
  }
  serial = new SerialPort({ path, baudRate: BAUD }, (err) => {
    if (err) {
      log("串口打开失败:", err.message);
      setTimeout(connectSerial, RETRY_MS);
      return;
    }
    log("串口已连:", path);
    broadcast(JSON.stringify({ evt: "serial", open: true }));
    serial.write('{"cmd":"ping"}\n');
  });
  const parser = serial.pipe(new ReadlineParser({ delimiter: "\n" }));
  parser.on("data", (line) => {
    const t = line.trim();
    if (!t) return;
    lastRx = Date.now();
    if (t.startsWith("{")) broadcast(t);   // 只透传 JSON 行,过滤固件日志
    log("« ", t);
    if (t.startsWith(">>>")) kickRepl();   // REPL 在回显我们的命令 = main.py 没在跑
  });
  serial.on("close", () => {
    log("串口断开,重试中…");
    serial = null;
    broadcast(JSON.stringify({ evt: "serial", open: false }));
    setTimeout(connectSerial, RETRY_MS);
  });
  serial.on("error", (e) => log("串口错误:", e.message));
}

// 掉 REPL 自愈:Ctrl-B(若在 raw REPL 先退到普通 REPL)+ Ctrl-D(软复位 → boot.py → main.py)
function kickRepl() {
  const now = Date.now();
  if (!serial?.isOpen || now - lastKick < REPL_KICK_MIN_MS) return;
  lastKick = now;
  log("小机停在 REPL(main.py 没跑),发 Ctrl-B + Ctrl-D 软复位");
  broadcast(JSON.stringify({ evt: "repl_kick" }));
  serial.write("\r\x02\r\x04");
}

// 看门狗:板子空闲太久就 ping;跑着的固件回 pong,停在 REPL 的会回显 ">>> {...}" 触发上面的自愈
setInterval(() => {
  if (serial?.isOpen && Date.now() - lastRx > IDLE_PING_MS) {
    lastRx = Date.now();   // 别每个 tick 都发;等这条的回音
    serial.write('{"cmd":"ping"}\n');
  }
}, IDLE_PING_MS);

connectSerial();
