# GOLD ALERT iOS（xtool / Ad Hoc，无需 Mac）

原生 SwiftUI App。在 Linux / Windows（WSL）上用 [xtool](https://xtool.sh) 编译、**Ad Hoc 签名**并装到 iPhone。不依赖网页；价格直接查 Swissquote，提醒写入 Cloudflare，EA 仍从 Cloudflare 拉取。

## 功能

- 本机保存 API Token（Keychain）
- **Swissquote** 直连取 XAU/USD（`forex-data-feed.swissquote.com`），不走网页
- 取到报价后由 App 调用 `POST /api/app/price` 上传 Cloudflare（不标记 EA 在线）
- 设定 / 保存 / 清除 / 暂停：与网页同一套 Cloudflare API，EA 下次 `/api/ea/sync` 读到

## 一次性：安装 xtool（Linux / Windows）

官方文档：https://xtool.sh/documentation/xtool/installation-linux/

1. 安装 xtool AppImage，放进 `PATH`
2. 从 Apple 下载 **Xcode.xip**（需 Apple ID）
3. 运行：

```bash
xtool setup
```

登录方式：

- **API Key**：付费 Apple Developer Program（推荐，走 App Store Connect）
- **Password**：任意 Apple ID（免费也可；xtool 会注册设备并签发开发/Ad Hoc 配置）

按提示提供 `Xcode.xip` 路径，生成 iOS Swift SDK。

## 部署到 iPhone（Ad Hoc）

在本目录执行：

```bash
cd gold-alert/ios/GoldAlert
xtool dev
```

流程：

1. USB 连接 iPhone（可先 `ideviceinfo` 确认）
2. 手机上点 **信任** 此电脑
3. 开启 **开发者模式**（设置 → 隐私与安全性）
4. xtool 注册设备 → 生成证书 + Provisioning Profile → **签名** → 安装
5. 首次打开若提示未信任：设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID

改完代码再执行一次 `xtool dev` 即可覆盖安装。

### 只打 IPA（可选）

```bash
xtool dev build --ipa
```

再按需用本机签名工具处理；日常装机直接 `xtool dev` 即可。

## 工程说明

| 文件 | 作用 |
|------|------|
| `Package.swift` | SwiftPM（xtool 要求单一 library product） |
| `xtool.yml` | Bundle ID / 图标；`com.rickrqi77.goldalert` |
| `Sources/GoldAlert/` | 原生 SwiftUI 源码 |

默认 API：`https://alertdata.pages.dev`（解锁页可改）。Worker 需已部署含 `POST /api/app/price` 的版本。

## 与网页 / EA 的关系

```
iPhone App ──Swissquote──► 显示现价
     │
     └──POST /api/app/price──► Cloudflare D1（价格快照）
     └──POST /api/alerts*  ──► Cloudflare D1（提醒）
                                      ▲
MT5 EA ──POST /api/ea/sync────────────┘
```

网页可继续用，也可不再打开；App 可独立完成设定与保存。
