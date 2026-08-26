// CLI 测试:向桥接发一条命令并回显 2 秒内的上行。
//   node send.js '{"cmd":"emote","name":"happy"}'
//   node send.js '{"cmd":"anim","name":"celebrate"}'
import WebSocket from "ws";

const msg = process.argv[2];
if (!msg) {
  console.error('用法: node send.js \'{"cmd":"ping"}\'');
  process.exit(1);
}
const ws = new WebSocket(`ws://127.0.0.1:${process.env.BRIDGE_PORT ?? 9800}`);
ws.on("open", () => {
  ws.send(msg);
  setTimeout(() => process.exit(0), 2000);
});
ws.on("message", (d) => console.log("«", d.toString()));
ws.on("error", (e) => {
  console.error("连不上桥接(先 npm run bridge):", e.message);
  process.exit(1);
});
