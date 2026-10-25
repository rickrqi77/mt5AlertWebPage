# GOLD ALERT — XAUUSD 黄金价格提醒系统

基于 **MetaTrader 5 (MQL5)** + **Cloudflare Workers / D1** + **手机网页** + **Telegram Bot** 的黄金价格提醒系统。

价格来源：**仅使用你电脑上 MT5（XMTrading）中的 XAUUSD 报价**，不使用任何第三方行情 API。

```
iPhone Safari  ──HTTPS──►  Cloudflare Worker  ◄──HTTPS──  MT5 EA (Windows)
                              │        │
                              ▼        ▼
                           Cloudflare D1    Telegram Bot ──► iPhone
```

---

## 目录结构

```
gold-alert/
├── worker/src/index.js      # Cloudflare Worker API
├── wrangler.jsonc           # Wrangler 配置
├── schema.sql               # D1 数据库结构
├── package.json
├── web/                     # 手机网页（可选；App 可独立完成设定）
├── ios/GoldAlert/           # 原生 iOS App（xtool Ad Hoc，无需 Mac）
├── mt5/
│   └── GoldPriceAlert.mq5   # MetaTrader 5 EA（必须是 .mq5）
└── README.md
```

### iOS App（推荐，可不打开网页）

原生 SwiftUI，用 [xtool](https://xtool.sh) 在 Linux/Windows 上 **Ad Hoc** 装到 iPhone：

- 价格：App 直连 **Swissquote**，再 `POST /api/app/price` 上传 Cloudflare
- 提醒：与网页相同，写入 Cloudflare；EA 仍读 Cloudflare
- 说明与部署：见 `ios/GoldAlert/README.md`（`xtool setup` → `xtool dev`）

---

## 一、你需要准备什么

1. 一台能运行的 Windows 电脑，已安装 **MetaTrader 5**（XMTrading）
2. 一个 **Cloudflare** 账号（免费即可）
3. 一个 **Telegram** 账号
4. 一台 **iPhone**（Safari）
5. 本机安装 **Node.js**（用于部署 Worker）

> 本项目 **不使用 MT4**，EA 文件必须是 `.mq5`。

---

## 二、安装 Node.js

### Windows

1. 打开：https://nodejs.org/
2. 下载 LTS 版本并安装
3. 打开 **命令提示符 (CMD)** 或 **PowerShell**，输入：

```bash
node -v
npm -v
```

能显示版本号即可。

### macOS / Linux

```bash
node -v
npm -v
```

若没有，请从 https://nodejs.org/ 安装。

---

## 三、下载本项目并安装依赖

把 `gold-alert` 文件夹放到电脑上，进入该目录：

```bash
cd gold-alert
npm install
```

这会安装 Cloudflare 官方工具 **Wrangler**。

检查：

```bash
npx wrangler --version
```

---

## 四、登录 Cloudflare

```bash
npx wrangler login
```

浏览器会打开 Cloudflare 登录页，登录并授权。

确认登录成功：

```bash
npx wrangler whoami
```

---

## 五、创建 D1 数据库

```bash
npx wrangler d1 create gold-alert-db
```

命令成功后会输出类似：

```
[[d1_databases]]
binding = "DB"
database_name = "gold-alert-db"
database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**把 `database_id` 复制下来。**

打开 `wrangler.jsonc`，把：

```jsonc
"database_id": "REPLACE_WITH_YOUR_D1_DATABASE_ID"
```

改成你的真实 ID，例如：

```jsonc
"database_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

保存文件。

---

## 六、执行数据库结构（schema.sql）

本地（可选，用于本地调试）：

```bash
npm run db:migrate:local
```

远程（正式环境，**必须执行**）：

```bash
npm run db:migrate:remote
```

或：

```bash
npx wrangler d1 execute gold-alert-db --remote --file=./schema.sql
```

---

## 七、生成并设置 API Token

API Token 用于保护接口，手机网页和 MT5 EA 都要用它。

### 生成一个随机 Token（示例）

可以自己想一串足够长的随机字符，例如：

```
gold_alert_7f3a9c2e1b8d4e6f0a5c9b2d
```

### 写入 Cloudflare Secret（正式环境）

```bash
npx wrangler secret put API_TOKEN
```

按提示粘贴你的 Token，回车。

> Token **不要**写进 HTML / JS 源码里。手机网页第一次打开时会让你手动输入，并保存在浏览器 `sessionStorage`。

---

## 八、创建 Telegram Bot 并获取 Chat ID

### 8.1 创建 Bot

1. 打开 Telegram，搜索 `@BotFather`
2. 发送 `/newbot`
3. 按提示设置名称
4. BotFather 会给你一个 **Bot Token**，形如：`123456789:AAH...`
5. **妥善保存**，不要发给别人，不要写进网页或 EA

### 8.2 获取 Chat ID

1. 用你的 iPhone 打开刚创建的 Bot，点 **Start**
2. 随便发一条消息给 Bot（例如：`hi`）
3. 在浏览器打开（把 `BOT_TOKEN` 换成你的）：

```
https://api.telegram.org/botBOT_TOKEN/getUpdates
```

4. 在返回的 JSON 里找到 `"chat":{"id": 数字`，那个数字就是 **Chat ID**  
   （个人号一般是正数，例如 `123456789`）

### 8.3 把 Telegram 信息写入 Cloudflare Secret

```bash
npx wrangler secret put TELEGRAM_BOT_TOKEN
```

粘贴 Bot Token。

```bash
npx wrangler secret put TELEGRAM_CHAT_ID
```

粘贴 Chat ID。

> Telegram Bot Token **只会**存在 Cloudflare Worker Secret 中。  
> 不会出现在 HTML、JavaScript、MT5 EA、API 响应里。

---

## 九、部署 Worker + Pages

API 在 Worker；网页在 Pages。`alertdata.pages.dev/api/*` 由 `functions/api/[[path]].js` 代理到 Worker。

```bash
# 1) API Worker（必须）
npm run deploy

# 2) 网页 + /api 代理（必须带 functions/，在 gold-alert/ 目录执行）
npm run pages:deploy

# 或一次都部署：
npm run deploy:all
```

成功后：

- 手机网页：`https://alertdata.pages.dev/`
- API：`https://alertdata.pages.dev/api/...`（经 Pages Functions 代理）
- Worker 直连：`https://gold-alert.rick-rqi-apple.workers.dev`

若 Worker 被删过、Secret 丢失：第一次用正确 Token 解锁时会把 Token 写入 D1（也可再执行 `npx wrangler secret put API_TOKEN`）。

---

## 九-B、网页和 EA 都走 Cloudflare，触发后 EA 直接发 Telegram

EA 按间隔向 Cloudflare 发 **一次** 请求：带上最新价格、哪些提醒还在触发，并在同一次响应里取回已保存的提醒。网页没有「刷新」按钮。页面打开时，按这个间隔读取 EA 刚写入的价格和使用情况。设定和保存写入 Cloudflare。价格穿越后，EA 直接把消息发给 Telegram。

- 手机网页：`https://alertdata.pages.dev/`
- 下载 EA：`https://alertdata.pages.dev/GoldPriceAlert.mq5`（v1.17）

---

## 十、手机网页使用方法（iPhone Safari）

1. Safari 打开：`https://alertdata.pages.dev/`
2. **第一次**输入 **API Token**，点「解锁」
3. 页面按 EA 的间隔显示最新价格。已触发过的提醒显示「已用」。没有「刷新」按钮
4. 设置间隔（例如 `5`），点「设定」按当前 EA 价格生成提醒
5. 点「保存设置」，提醒写入 Cloudflare，EA 下次同步时取回

### 功能说明

| 功能 | 说明 |
|------|------|
| 当前价格 | EA 每次同步写入的最新价。页面打开时按同样间隔更新。还没有价格时显示 `--` |
| 已用 | EA 在同一次同步里报上哪些提醒已经触发。页面上按钮变成「已用」 |
| 自动生成 | 以当前 EA 价格的整数为中心，上下各 7 档 + 中间一档（最多 15 个），写入 Cloudflare |
| 保存设置 | 写入 Cloudflare，EA 下次同步时取回 |
| 全部清除 | 删除 Cloudflare 上的全部提醒 |
| 触发通知 | EA 发现穿越后直接发 Telegram，不经过 Cloudflare |

> 网页关掉或切到后台后，页面不再读取。EA **继续**按间隔做那一次同步。重新打开网页会读到 EA 刚写入的价格和提醒。

---

## 十一、安装 MT5 EA（重要）

### 11.1 复制文件

1. 打开 MetaTrader 5
2. 菜单：**文件 → 打开数据文件夹**
3. 进入：`MQL5 / Experts`
4. 把本项目的 `mt5/GoldPriceAlert.mq5` 复制进去

### 11.2 编译

网站上的 `.mq5` 不能直接被 MT5 运行。编译器在你这台 Windows 的 MT5 里。双击下面的脚本会下载最新源码，调用本机 MetaEditor 编译，并覆盖 `GoldPriceAlert.ex5`。不用打开 MetaEditor 按 F7。

1. 把这两个文件下载到同一个文件夹
   - `https://alertdata.pages.dev/compile-gold-alert.bat`
   - `https://alertdata.pages.dev/compile-gold-alert.ps1`
2. 先打开过一次 MetaTrader 5
3. 双击 `compile-gold-alert.bat`
4. 看到「已覆盖」后，图表上的 EA 通常会自动重新加载。Experts 里应出现新的 `EA initialized` 版本

仍想手工编译时：在 MT5 按 **F4** 打开 MetaEditor，打开 `Experts / GoldPriceAlert.mq5`，按 **F7**。下方应显示 `0 error(s)`。

### 11.3 允许 WebRequest（必须做，否则 EA 无法联网）

1. MT5 菜单：**工具 → 选项**
2. 打开 **Expert Advisors**（智能交易）
3. 勾选：**允许算法交易**（Allow Algo Trading）
4. 勾选：**允许 WebRequest 访问下列 URL**（Allow WebRequest for listed URL）
5. 在列表中 **添加这两个地址**：

```
https://alertdata.pages.dev
https://api.telegram.org
```

6. 点「确定」

> 不要假设 WebRequest 默认可用。不加 URL 会出现错误 **4060**。

### 11.4 挂载 EA 到黄金图表

1. 打开 XMTrading 的黄金图表（可能是 `XAUUSD` / `GOLD` / `XAUUSD#` 等）
2. 把 **GoldPriceAlert** 拖到图表上
3. 在参数里设置：

| 参数 | 示例 | 说明 |
|------|------|------|
| `InpApiBaseUrl` | `https://alertdata.pages.dev` | **不要**末尾斜杠 |
| `InpApiToken` | （你的 API Token） | 与 Cloudflare Secret 相同 |
| `InpSymbol` | （留空） | 留空 = 使用当前图表品种 |
| `InpSyncSeconds` | `3` | 没有间隔文件时使用。小于 3 会按 3 秒。有 `gold-alert-interval.txt` 时以文件为准 |
| `InpEnableTelegram` | `true` | 穿越后由 EA 直接发 Telegram |
| `InpTelegramBotToken` | BotFather 给的 Token | |
| `InpTelegramChatId` | 你的 Chat ID | |

4. 勾选「允许算法交易」
5. 确认 MT5 顶部「Algo Trading」按钮为 **绿色开启**

### 11.4b 在电脑上改取提醒间隔

EA 为 v1.17 并正在运行时，不用打开 MT5 参数。间隔大于 1 分钟时，每分钟看一次新秒数，改小后大约 1 分钟生效，不用等上一段大间隔走完。间隔小于 1 分钟时，按那个秒数查看和发送。Cloudflare 请求仍按设定的秒数发送。

1. 下载并双击：`https://alertdata.pages.dev/set-alert-interval.bat`
2. 输入秒数（3 到 3600），回车
3. Experts 大约 1 分钟内出现 `Pull interval updated: Ns`。间隔小于 1 分钟时，会更快

文件写在 `%APPDATA%\MetaQuotes\Terminal\Common\Files\gold-alert-interval.txt`。删掉这个文件后，EA 回到图表参数 `InpSyncSeconds`。

### 11.5 查看日志

打开 MT5 下方 **「专家」(Experts)** 标签，应看到类似：

```
[GoldAlert] EA initialized v1.17
[GoldAlert] Sync every 3s: price, usage, and alerts in one request.
[GoldAlert] Symbol: XAUUSD
[GoldAlert] API connected
[GoldAlert] Config version: 1
[GoldAlert] Loaded 0 alerts
```

若出现：

```
[GoldAlert] ERROR: WebRequest failed. Error=4060
```

说明 URL 未加入白名单，请回到 **11.3** 重新配置。

---

## 十二、本地开发（可选）

```bash
cp .dev.vars.example .dev.vars
# 编辑 .dev.vars 填入 API_TOKEN / TELEGRAM_* 

npm run db:migrate:local
npm run dev
```

浏览器打开 Wrangler 提示的本地地址（通常是 `http://127.0.0.1:8787`）。

---

## 十三、API 一览

所有接口都需要 Header：

```
Authorization: Bearer <API_TOKEN>
```

| 方法 | 路径 | 用途 |
|------|------|------|
| POST | `/api/ea/sync` | EA 的唯一周期请求：上报价格和使用情况，响应里带回已保存的提醒 |
| POST | `/api/app/price` | iOS App 上传 Swissquote 报价（不标记 EA 在线） |
| GET | `/api/spot` | Worker 代拉 Swissquote（网页可选；App 直连 Swissquote） |
| GET | `/api/status` | 网页打开时读取 EA 刚写入的价格、提醒和使用情况 |
| GET | `/api/alerts` | 提醒列表 |
| POST | `/api/alerts` | 保存提醒（最多 15） |
| DELETE | `/api/alerts/:id` | 删除单个提醒 |
| POST | `/api/alerts/auto` | 按当前 EA 价格自动生成 ±7 档 |
| POST | `/api/ea/heartbeat` | 旧接口。当前 EA 不调用 |
| GET | `/api/config` | 旧接口。内容和同步响应相同，当前 EA 不单独请求 |
| POST | `/api/alert-trigger` | 保留接口。当前 EA 不调用，Telegram 由 EA 直发 |
| GET/POST | `/api/settings` | 间隔等设置 |

### 自动生成示例

当前价 `4181.2`，先取整数 `4181` 作为基数，间隔 `5`，生成 15 档：

```
4146  4151  4156  4161  4166  4171  4176
4181   ← 当前整数价，默认不触发
4186  4191  4196  4201  4206  4211  4216
```

---

## 十四、突破逻辑说明

对每个提醒价 `P`：

- **上涨穿越**：上一价 `< P` 且 当前价 `>= P` → 发送 ↑ 上涨
- **下跌穿越**：上一价 `> P` 且 当前价 `<= P` → 发送 ↓ 下跌

触发后，这一档在 EA 里关闭，价格继续停在同一侧 **不会重复提醒**。  
在网页上重新保存并启用后，EA 下次拉取配置才会再次提醒。

Telegram 消息示例：

```
3983.25 _ 3983.31
```

---

## 十五、验收测试清单

按顺序做：

| # | 测试 | 期望结果 |
|---|------|----------|
| 1 | EA 挂载并联网 | Experts 出现 `Sync every 3s: price, usage, and alerts in one request.` 和 `API connected` |
| 2 | 手机添加 `4000` 并保存 | EA 下次同步日志出现 Loaded，含 4000 |
| 3 | 点「设定」 | 按 EA 价格生成 15 个价格 |
| 4 | 间隔改为 `10` 再生成 | 间隔为 10 |
| 5 | 删除一个价格并保存 | EA 下次同步取回 |
| 6 | 价格向上穿越 | Telegram 收到 `提醒价 _ 现价`，Experts 出现 ALERT UP |
| 7 | 价格向下穿越 | Telegram 收到 `提醒价 _ 现价`，Experts 出现 ALERT DOWN |
| 8 | 同侧持续波动 | **不**重复发送 |
| 9 | 重新穿越 | 可再次提醒 |
| 10 | 关闭手机网页 | 页面停止读取。EA 仍继续那一次同步 |
| 11 | 打开网页 | 没有「刷新」按钮。价格是 EA 上报的价，已触发的提醒显示「已用」 |
| 12 | 关掉网页再打开 | 仍显示 EA 最新价格，已保存的提醒还在 |

---

## 十六、常见问题

### Q: WebRequest Error=4060

在 MT5：**工具 → 选项 → Expert Advisors**，把 `https://alertdata.pages.dev` 和 `https://api.telegram.org` 加入白名单。

### Q: 如何远程暂停 EA 提醒？

电脑上的 MT5 无法从网页直接关闭。网页有 **暂停提醒 / 恢复提醒**：暂停后 EA 约 3 秒内不再触发 Telegram。恢复后继续按已选中的价格提醒。

### Q: 怎么确认 EA 在取提醒？

网页不再显示在线或离线。看 MT5 Experts：应有 `EA initialized v1.17`、`Sync every 3s: price, usage, and alerts in one request.`、`API connected`。保存提醒后下次同步出现新的 `Loaded`。

### Q: 收不到 Telegram

1. EA 参数里勾选 `InpEnableTelegram`，并填 `InpTelegramBotToken`、`InpTelegramChatId`  
2. 确认已给 Bot 发过 `/start`  
3. WebRequest 白名单包含 `https://api.telegram.org`  
4. 触发后 Experts 应出现 `Telegram sent`。若是 Error=4060，回到 11.3 

### Q: XM 黄金不是叫 XAUUSD？

把 EA 拖到实际黄金图表上，`InpSymbol` **留空**即可自动使用图表品种。

### Q: EA 日志会不会把硬盘写满？

默认不会。心跳和报价不再写日志，只在启动、配置变化、触发提醒或出错时记录。  
MT5 日志在数据文件夹的 `Logs` / `MQL5\Logs`，通常按天分文件。旧日志可手动删除。需要详细报价日志时，把 EA 参数 `InpVerboseLog` 设为 `true`。

### Q: 手机 Token 忘了？

Token 存在 Cloudflare Secret 中。你可以用原来的字符串重新输入；若忘记，重新 `secret put API_TOKEN` 并同步更新 EA 参数。

---

## 十七、安全说明

- API 全部需要 Token，不是公开接口
- 手机网页 **不硬编码** Token（手动输入后存 sessionStorage）
- Telegram Bot Token **仅**存于 Cloudflare Worker Secret
- EA **不包含** Telegram Token；触发后由 Cloudflare 代发

---

## 十八、部署检查清单（快速版）

1. ✅ `npm install`
2. ✅ `npx wrangler login`
3. ✅ `npx wrangler d1 create gold-alert-db` → 写入 `wrangler.jsonc`
4. ✅ `npm run db:migrate:remote`
5. ✅ `npx wrangler secret put API_TOKEN`
6. ✅ `npx wrangler secret put TELEGRAM_BOT_TOKEN`
7. ✅ `npx wrangler secret put TELEGRAM_CHAT_ID`
8. ✅ `npm run deploy`
9. ✅ Safari 打开 Worker 网址，输入 Token
10. ✅ MT5 编译 `GoldPriceAlert.mq5`
11. ✅ MT5 允许 WebRequest URL
12. ✅ 挂载 EA，开启 Algo Trading
13. ✅ 按第十五节做验收测试

---

祝挂单愉快。有问题先看 MT5 **Experts** 日志和 `npx wrangler tail`。
