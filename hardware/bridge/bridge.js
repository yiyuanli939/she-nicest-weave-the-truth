// 串口 ↔ WebSocket 桥接:游戏(Godot Robot autoload)连 ws://127.0.0.1:9800,
// 本进程把 JSON 行双向透传给 /dev/cu.usbmodem*(ESP32-S3 小机)。
// 用法: npm run bridge   (可选环境变量 SERIAL_PORT / BRIDGE_PORT)
import { SerialPort } from "serialport";
import { ReadlineParser } from "@serialport/parser-readline";
import { WebSocketServer } from "ws";

const WS_PORT = Number(process.env.BRIDGE_PORT ?? 9800);
const BAUD = 115200;
const RETRY_MS = 2000;

let serial = null;
const wss = new WebSocketServer({ host: "127.0.0.1", port: WS_PORT });
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

wss.on("listening", () => log(`WebSocket 就绪 ws://127.0.0.1:${WS_PORT}`));
wss.on("connection", (ws) => {
  log("客户端连入");
  ws.on("message", (data) => {
    const line = data.toString().trim();
    if (!line) return;
    // 路由:含 cmd → 串口(机器人);其余(teleop 手部数据等)→ 广播给其他客户端(游戏)
    let obj = null;
    try { obj = JSON.parse(line); } catch { /* 非 JSON 一律当 cmd 透传 */ }
    if (obj !== null && obj.cmd === undefined) {
      broadcast(line, ws);
      return;
    }
    if (serial?.isOpen) {
      serial.write(line + "\n");
      if (obj?.cmd !== "gimbal") log("» ", line);   // 跟手流太密,不刷日志
    } else log("丢弃(串口未连):", line);
  });
  ws.on("close", () => log("客户端断开"));
});

function broadcast(line, except = null) {
  for (const c of wss.clients)
    if (c !== except && c.readyState === 1) c.send(line);
}

async function pickPort() {
  if (process.env.SERIAL_PORT) return process.env.SERIAL_PORT;
  const ports = await SerialPort.list();
  const hit = ports.find(
    (p) => p.path.includes("usbmodem") || /Espressif/i.test(p.manufacturer ?? "")
  );
  return hit?.path ?? null;
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
    serial.write('{"cmd":"ping"}\n');
  });
  const parser = serial.pipe(new ReadlineParser({ delimiter: "\n" }));
  parser.on("data", (line) => {
    const t = line.trim();
    if (!t) return;
    if (t.startsWith("{")) broadcast(t);   // 只透传 JSON 行,过滤固件日志
    log("« ", t);
  });
  serial.on("close", () => {
    log("串口断开,重试中…");
    serial = null;
    setTimeout(connectSerial, RETRY_MS);
  });
  serial.on("error", (e) => log("串口错误:", e.message));
}

connectSerial();
