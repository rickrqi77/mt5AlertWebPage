# GoldAlert 手表端（Apple Watch）

xtool 不支持 watchOS，这里走绕路：**手表部分在 GitHub 的 macOS runner 上
用 xcodebuild 编译成未签名 .app，回 WSL 后在手机打包时嵌入 IPA，
由 zsign 用各自的 Ad Hoc 描述文件统一签名**。手机端仍是原来的 xtool 流程。

适配目标：Apple Watch Series 12 · 42mm（界面按 187×223pt 排版，
46mm 自动放宽）。

## 功能与口径（ren 2026-11-15 确认）

- **表盘入口**：WidgetKit 复杂功能（圆形/矩形/行内/边角四种），显示
  Swissquote 金价，点按直接打开手表端 App。刷新受系统时间线预算限制
  （WidgetKit 每天约 40–75 次量级；手机推送快照的通道同样有每天 50 次
  的系统上限），所以表盘上是**分钟级快照价**，2 秒/5 秒级刷新做不到。
- **手表端 App**：价格**固定 Swiss**（Swissquote 直连 XAU/USD 中间价，
  不跟随手机的来源开关），打开时每 **1 秒**刷新一次；同时显示手机
  连接状态（推送要靠它）。
- **间隔设定**：两项选择——间隔 [1, 2, 3, 4, 5, 10] 默认 5；
  每边档数 [3, 5, 7] 默认 7（上下各 7、共 15 个，与手机端一致）。
- **执行留在手机上**：点「设定并推送」只把 {间隔, 每边档数} 经
  WatchConnectivity 的 sendMessage 发给手机；手机用现有建网格逻辑
  （起点 = 现价整数部分、中心档关闭其余打开）生成网格并
  POST /api/alerts，结果回传到表上显示。**token 不进手表。**
  限制：推送时手机要在手表附近、保持连接；手机达不到时表上明确
  报失败，不会假装成功。手机端 app 未解锁时也会回失败原因。

Bundle ID：

| 部分 | Bundle ID |
|------|-----------|
| 手表 App | `com.rickrqi77.goldalert.watchkitapp` |
| 复杂功能扩展 | `com.rickrqi77.goldalert.watchkitapp.complication` |

## 一次性准备（Apple Developer 后台）

1. Identifiers 里建好上面两个 App ID。
2. Devices 里登记 Apple Watch 的 UDID（Windows 上可用 iMazing/爱思助手
   连 iPhone 查看已配对 Watch 的 UDID）。
3. 用同一个发布证书新建两个 Ad Hoc 描述文件（设备勾选 iPhone + Watch），
   放到 `D:\goldalert\adhoc\`：

| 文件 | App ID |
|------|--------|
| `goldalert-watch-adhoc.mobileprovision` | `com.rickrqi77.goldalert.watchkitapp` |
| `goldalert-complication-adhoc.mobileprovision` | `com.rickrqi77.goldalert.watchkitapp.complication` |

## 每次出包

1. GitHub 仓库 Actions 页运行 **Build Watch App**（改了 `gold-alert/watchos/`
   下的文件 push 后也会自动跑），下载 artifact `GoldAlertWatch-app`。
2. 解压，把 `GoldAlertWatch.app` 放到仓库的
   `gold-alert/watchos/build/GoldAlertWatch.app`（WSL 里操作即可，不用提交）。
3. 照常跑 Build Menu 打包手机端。`pack-onsite.sh` 检测到手表 .app 和
   手表描述文件都在时，会自动嵌入并多描述文件签名；缺任一样则按原流程
   只打手机端，不受影响。
4. 照常从 OTA 页安装到 iPhone。装好后在 iPhone 的 Watch App 里把
   「提醒事项」手表端装到手表上（手表上若装不上，先开手表的
   「设置 → 隐私与安全性 → 开发者模式」），表盘编辑里加「金价」复杂功能。
5. 手机和手表放一起，打开表端 app 选间隔和档数推送一次，回手机端
   核对列表已换成新网格。

## 注意

- 手表 .app 是未签名产物，只能经第 3 步的 zsign 签名后安装，
  不要单独往手表上装。
- GitHub Actions 的 macOS 分钟按 10 倍计费（私有仓库），一次构建约
  3–6 分钟（折算 30–60 分钟额度），按需手动触发即可。
- 签名链（多 -m 描述文件按 App ID 配对）是 zsign 的既有功能，但本仓库
  是第一次实际使用：首次安装后若手表端不出现，先看 pack 日志里 zsign
  是否报错，再核对两个描述文件的 App ID 与设备列表。
