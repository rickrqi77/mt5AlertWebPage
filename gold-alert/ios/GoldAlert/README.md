# GOLD ALERT iOS（xtool / Ad Hoc，无需 Mac）

原生 SwiftUI App。在 Linux / Windows（WSL）上用 [xtool](https://xtool.sh) 编译、**Ad Hoc 签名**并装到 iPhone。不依赖网页；价格直接查 Swissquote，提醒写入 Cloudflare，EA 仍从 Cloudflare 拉取。

## 功能

- 本机保存 API Token（Keychain）
- **Swissquote** 直连取 XAU/USD（`forex-data-feed.swissquote.com`），不走网页
- 取到报价后由 App 调用 `POST /api/app/price` 上传 Cloudflare（不标记 EA 在线）
- 设定 / 保存 / 清除 / 暂停：与网页同一套 Cloudflare API，EA 下次 `/api/ea/sync` 读到
- **爆仓价（日元模式）**：读取相册最新截图 → OCR 只解析 GOLD 持仓 → 显示平均价 / 手数 / 爆仓价，并可删除截图

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

## 网页安装（推荐，与交通查询相同）

打包到共享 **`D:\ota-site`**（`goldalert.html` / `goldalert-manifest.plist` 等专用名，不覆盖其它包），Safari 打开：

**https://w77.tail708c1b.ts.net/goldalert.html**

```bash
cd gold-alert/ios/GoldAlert
./scripts/pack-onsite.sh
```

Windows：`scripts\pack-onsite.bat`

证书放 `D:\goldalert\adhoc`。见 [ADHOC.md](ADHOC.md)。

## 开发装机（USB + xtool 开发签名）

```bash
cd gold-alert/ios/GoldAlert
xtool setup   # 首次
xtool dev
```

## 工程说明

| 文件 | 作用 |
|------|------|
| `Package.swift` | SwiftPM（xtool 要求单一 library product） |
| `xtool.yml` | Bundle ID / 图标；`com.rickrqi77.goldalert` |
| `Sources/GoldAlert/` | 原生 SwiftUI 源码 |

默认 API：`https://alertdata.pages.dev`（解锁页可改）。Worker 需已部署含 `POST /api/app/price` 的版本。

## 爆仓价

1. 点「读取图片」→ 取相册 **截图** 最新一张（没有则取最近图片）
2. Vision OCR，**只处理名称含 GOLD / XAU 的持仓**
3. 均价 = Σ(入场价 × 手数) / Σ手数  
4. 可用资金 = 结余 − 预付款 × 0.2  
   - **日元模式**：再 ÷ Swissquote USD/JPY → 美元可用  
   - **美元模式**：跳过换汇，上一步结果就是美元可用  
5. 可承受点数 = 美元可用 ÷ (总手数 × 100)  
6. sell：爆仓价 = 均价 + 点数；buy：爆仓价 = 均价 − 点数  
7. 算出后可删除该截图  

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
