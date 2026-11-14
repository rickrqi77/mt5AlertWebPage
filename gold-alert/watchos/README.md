# GoldAlert 手表端（Apple Watch）

xtool 不支持 watchOS，这里走绕路：**手表部分在 GitHub 的 macOS runner 上
用 xcodebuild 编译成未签名 .app，回 WSL 后在手机打包时嵌入 IPA，
由 zsign 用各自的 Ad Hoc 描述文件统一签名**。手机端仍是原来的 xtool 流程。

适配目标：Apple Watch Series 12 · 42mm（界面按 187×223pt 排版，
46mm 自动放宽）。

## 功能

- **表盘入口**：WidgetKit 复杂功能（圆形/矩形/行内/边角四种），显示
  Swissquote 最新金价（每 15 分钟刷新），点按直接打开手表端 App。
- **手表端 App**：打开显示最新价格（优先 EA 价，无凭据时显示 Swiss 价）、
  EA 在线状态、当前间隔与已设定个数；每 20 秒自动刷新。
- **间隔设定**：与手机端同一组选项 1/2/3/4/5/10，选好点「设定并推送」，
  手表直接 POST `/api/alerts/auto`，服务器按现价生成网格（起点 = 价格
  整数部分、上下各 7 个共 15 个、起点关闭其余打开，与手机端完全一致）
  并保存，EA 在下一个 3 秒同步周期自动采用——不需要手机在场。
- **凭据同步**：iPhone 端解锁后经 WatchConnectivity 把 {baseURL, token}
  同步给手表，手表存自己的钥匙串；手机端退出登录会同步清空手表凭据。
  手表上不输 token。

Bundle ID：

| 部分 | Bundle ID |
|------|-----------|
| 手表 App | `com.rickrqi77.goldalert.watchkitapp` |
| 复杂功能扩展 | `com.rickrqi77.goldalert.watchkitapp.complication` |

## 一次性准备（Apple Developer 后台）

用同一个发布证书新建两个 Ad Hoc 描述文件，放到 `D:\goldalert\adhoc\`：

| 文件 | App ID |
|------|--------|
| `goldalert-watch-adhoc.mobileprovision` | `com.rickrqi77.goldalert.watchkitapp` |
| `goldalert-complication-adhoc.mobileprovision` | `com.rickrqi77.goldalert.watchkitapp.complication` |

设备列表要包含 iPhone（描述文件按设备走，Watch 不单独列）。

## 每次出包

1. GitHub 仓库 Actions 页运行 **Build Watch App**（改了 `gold-alert/watchos/`
   下的文件 push 后也会自动跑），下载 artifact `GoldAlertWatch-app`。
2. 解压，把 `GoldAlertWatch.app` 放到仓库的
   `gold-alert/watchos/build/GoldAlertWatch.app`（WSL 里操作即可）。
3. 照常跑 Build Menu 打包手机端。`pack-onsite.sh` 检测到手表 .app 和
   手表描述文件都在时，会自动嵌入并多描述文件签名；缺任一样则按原流程
   只打手机端，不受影响。
4. 照常从 OTA 页安装到 iPhone。装好后在 iPhone 的 Watch App 里把
   「提醒事项」手表端装到手表上，表盘编辑里加「金价」复杂功能。
5. 打开手机端提醒事项解锁一次（若已解锁，打开一次即会同步凭据），
   再打开手表端，价格与推送即可用。

## 注意

- 手表 .app 是未签名产物，只能经第 3 步的 zsign 签名后安装，
  不要单独往手表上装。
- GitHub Actions 的 macOS 分钟按 10 倍计费（私有仓库），一次构建约
  3–6 分钟（折算 30–60 分钟额度），按需手动触发即可，不必每次 push 都跑：
  本工作流只在 watchos 目录变更或手动触发时运行。
- 签名链（多 -m 描述文件按 App ID 配对）是 zsign 的既有功能，但本仓库
  是第一次实际使用：首次安装后若手表端不出现，先看 pack 日志里 zsign
  是否报错，再核对两个描述文件的 App ID 与设备列表。
