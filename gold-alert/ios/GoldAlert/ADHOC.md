# GOLD ALERT · Ad Hoc + 网页安装（D:\ota-site）

和「交通查询 / transit」一样：在 WSL 里用 **xtool 编译 + zsign Ad Hoc 签名**，产物放到 **`D:\ota-site\goldalert`**，iPhone 用 Safari 打开：

**https://w77.tail708c1b.ts.net/goldalert/**

只写入 `goldalert` 子目录，**不会覆盖** `D:\ota-site` 里其它应用的安装文件。

不要对签好的包再跑 `xtool dev` / `xtool install`（会改回开发签名）。

## 1. 证书与描述文件

放在 `D:\goldalert\adhoc`（WSL：`/mnt/d/goldalert/adhoc`）：

| 文件 | 说明 |
|------|------|
| `distribution.p12` | 与文件管理器 / 交通查询同一张 Apple Distribution |
| `p12.pass` | 密码单独一行，勿提交仓库 |
| `goldalert-adhoc.mobileprovision` | 本包名的 Ad Hoc 描述文件 |

Apple Developer：

1. App ID：`com.rickrqi77.goldalert`（Explicit）
2. Profiles → **Ad Hoc** → 选该 App ID → 同一张 Distribution 证书 → 勾选你的 iPhone → 下载另存为上面的 `.mobileprovision`

本 App **不需要 iCloud**。

`zsign` 若已装好可跳过；否则按交通查询的 ADHOC.md 编译安装。

## 2. 一条龙打包到 ota-site（推荐）

手机可以不插线。证书放好后，在 WSL：

```bash
cd /path/to/mt5AlertWebPage/gold-alert/ios/GoldAlert
./scripts/pack-onsite.sh
```

或在 Windows 双击 / 运行：

```bat
gold-alert\ios\GoldAlert\scripts\pack-onsite.bat
```

脚本会：

1. （可选）`git pull`
2. `CFBundleVersion` +1
3. `xtool dev build --configuration release --ipa`
4. `zsign` Ad Hoc 签名
5. 写入 `D:\ota-site\goldalert\`：
   - `index.html`（Safari 安装页）
   - `manifest.plist`
   - `GOLDALERT-adhoc.ipa`
   - `icon.png`

## 3. Safari 安装

1. 确认 `https://w77.tail708c1b.ts.net` 已指向 **`D:\ota-site`**（站点根目录）
2. iPhone **Safari** 打开：https://w77.tail708c1b.ts.net/goldalert/
3. 点 **用 Safari 安装**
4. 首次：设置 → 通用 → VPN 与设备管理 → 信任

## 4. 环境变量（可选）

| 变量 | 默认 |
|------|------|
| `OTA_SITE_DIR` | `/mnt/d/ota-site/goldalert` |
| `ONSITE_DIR` | （兼容旧名；未设 `OTA_SITE_DIR` 时可用） |
| `ADHOC_DIR` | `/mnt/d/goldalert/adhoc` |
| `OTA_BASE_URL` | `https://w77.tail708c1b.ts.net/goldalert` |
| `DO_PULL` | `1` |
| `BUMP_BUILD` | `1` |
| `GOLDALERT_P12_PASSWORD` | 若设置则不用 `p12.pass` |

## 5. 以后只改了代码

```bash
./scripts/pack-onsite.sh
```

然后手机 Safari 再打开安装页覆盖安装即可。
