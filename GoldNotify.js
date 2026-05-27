// Scriptable 脚本：获取 AU9999 金价并推送通知（同步到 Apple Watch）
// 用法：粘贴到 Scriptable App → 新建脚本 → 命名 "GoldNotify" → 运行或通过快捷指令定时触发

const URL_STR = "https://hq.sinajs.cn/list=gds_AU9999";
const REFERER = "https://finance.sina.com.cn";

let req = new Request(URL_STR);
req.headers = {
  "Referer": REFERER,
  "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
};

let body = "";
try {
  body = await req.loadString();
} catch (e) {
  let n = new Notification();
  n.title = "金价 AU9999";
  n.body = "获取失败：" + e.message;
  await n.schedule();
  Script.complete();
}

// 解析：var hq_str_gds_AU9999="价格,开,高,低,昨收,...,时间,日期";
const match = body.match(/"([^"]+)"/);
if (!match) {
  let n = new Notification();
  n.title = "金价 AU9999";
  n.body = "解析失败，原始：" + body.slice(0, 80);
  await n.schedule();
  Script.complete();
}

const fields = match[1].split(",");
// gds_AU9999 字段顺序：[0]现价 [4]最高 [5]最低 [6]时间 [7]昨收 [8]今开 [12]日期
const price    = parseFloat(fields[0]);
const high     = parseFloat(fields[4]);
const low      = parseFloat(fields[5]);
const time     = fields[6];
const prevClose= parseFloat(fields[7]);
const open     = parseFloat(fields[8]);
const date     = fields[12];

const change   = price - prevClose;
const changePct= (change / prevClose * 100);
const arrow    = change >= 0 ? "▲" : "▼";
const sign     = change >= 0 ? "+" : "";

// 判断是否交易时段
function isTradingTime() {
  const now = new Date();
  const dow  = now.getDay(); // 0=Sun 6=Sat
  const hhmm = now.getHours() * 100 + now.getMinutes();
  if (dow === 0) return false; // 周日全天休市
  // 日盘 09:00-15:30
  if (hhmm >= 900 && hhmm < 1530) return true;
  // 夜盘 20:00-23:59（周一~周五）
  if (dow >= 1 && dow <= 5 && hhmm >= 2000) return true;
  // 夜盘跨午夜 00:00-02:30（周二~周六凌晨，即周一夜盘延续）
  if (dow >= 2 && dow <= 6 && hhmm < 230) return true;
  return false;
}

const trading  = isTradingTime();
const statusStr= trading ? `${arrow} ${sign}${change.toFixed(2)} (${sign}${changePct.toFixed(2)}%)` : "休市";

// 构建通知
let n = new Notification();
n.title = `AU9999  ¥${price.toFixed(2)}  ${statusStr}`;
n.body  = `今开 ${open.toFixed(2)}  昨收 ${prevClose.toFixed(2)}  高 ${high.toFixed(2)}  低 ${low.toFixed(2)}\n${date} ${time}`;
n.sound = "default";
await n.schedule();

// 如果从 Shortcuts 调用，输出文本供后续使用
if (config.runsInApp || config.runsFromHomeScreen) {
  Script.setShortcutOutput(`AU9999 ¥${price.toFixed(2)} ${statusStr}`);
}

Script.complete();
