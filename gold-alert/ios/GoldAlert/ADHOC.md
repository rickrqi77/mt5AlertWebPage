# 提醒事项 · Ad Hoc + 网页安装（D:\ota-site）

与「黄金报价 / 交通查询」共用 **`D:\ota-site`** 和同一套 **`index.html`** 安装页样式。

Safari：

**https://w77.tail708c1b.ts.net/**

## 1. 证书

`D:\goldalert\adhoc`：

| 文件 | 说明 |
|------|------|
| `distribution.p12` | Apple Distribution |
| `p12.pass` | 密码一行 |
| `goldalert-adhoc.mobileprovision` | `com.rickrqi77.goldalert` |

## 2. 打包

```bash
cd gold-alert/ios/GoldAlert
./scripts/pack-onsite.sh
```

会把 IPA 放进 `D:\ota-site`，更新 `manifest-goldalert.plist`，并 **扫描目录内全部 .ipa** 刷新 `index.html`（其它 App 仍会列出）。

只刷新安装页（不重新编译）：

```bash
./scripts/scan-ota-site.sh
```

## 3. 安装

Safari 打开 https://w77.tail708c1b.ts.net/ ，在列表里点 **Safari 安装**（提醒事项）。

## 3.5 手表端（可选）

Apple Watch 端（`gold-alert/watchos/`）经 GitHub Actions 的 macOS runner
编译，产物放回 `gold-alert/watchos/build/GoldAlertWatch.app` 后，本脚本会
自动嵌入并签名。需要 `D:\goldalert\adhoc` 里另备两个描述文件：
`goldalert-watch-adhoc.mobileprovision`（`com.rickrqi77.goldalert.watchkitapp`）、
`goldalert-complication-adhoc.mobileprovision`（`com.rickrqi77.goldalert.watchkitapp.complication`）。
完整步骤见 `gold-alert/watchos/README.md`。缺手表产物或描述文件时自动跳过，
手机端打包不受影响。

## 4. 环境变量

| 变量 | 默认 |
|------|------|
| `OTA_SITE_DIR` | `/mnt/d/ota-site` |
| `OTA_BASE_URL` | `https://w77.tail708c1b.ts.net` |
| `OTA_SLUG` | `goldalert` |
| `OTA_TITLE` | `提醒事项` |
| `ADHOC_DIR` | `/mnt/d/goldalert/adhoc` |
