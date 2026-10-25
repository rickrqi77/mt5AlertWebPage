# GOLD ALERT · Ad Hoc + 网页安装（D:\ota-site）

产物直接放进共享目录 **`D:\ota-site`**（与其它 App 同一站点根）。  
只用本应用专用文件名，**不会覆盖**其它包的 `install.html` / `manifest.plist` / `icon.png`。

Safari 安装页：

**https://w77.tail708c1b.ts.net/goldalert.html**

不要对签好的包再跑 `xtool dev` / `xtool install`。

## 1. 证书与描述文件

放在 `D:\goldalert\adhoc`（WSL：`/mnt/d/goldalert/adhoc`）：

| 文件 | 说明 |
|------|------|
| `distribution.p12` | 与文件管理器 / 交通查询同一张 Apple Distribution |
| `p12.pass` | 密码单独一行，勿提交仓库 |
| `goldalert-adhoc.mobileprovision` | Bundle ID `com.rickrqi77.goldalert` 的 Ad Hoc 描述文件 |

本 App **不需要 iCloud**。

## 2. 打包

```bash
cd /path/to/mt5AlertWebPage/gold-alert/ios/GoldAlert
./scripts/pack-onsite.sh
```

Windows：`scripts\pack-onsite.bat`

写入 `D:\ota-site\`：

| 文件 | 作用 |
|------|------|
| `goldalert.html` | Safari 安装页 |
| `goldalert-manifest.plist` | itms-services 清单 |
| `GOLDALERT-adhoc.ipa` | 安装包 |
| `goldalert-icon.png` | 图标 |
| `index.html` | 仅追加/更新 GOLD ALERT 链接区块（保留其它内容） |

## 3. 安装

1. 站点根目录 = **`D:\ota-site`** → `https://w77.tail708c1b.ts.net`
2. Safari 打开 https://w77.tail708c1b.ts.net/goldalert.html
3. 点「用 Safari 安装」

## 4. 环境变量（可选）

| 变量 | 默认 |
|------|------|
| `OTA_SITE_DIR` | `/mnt/d/ota-site` |
| `ADHOC_DIR` | `/mnt/d/goldalert/adhoc` |
| `OTA_BASE_URL` | `https://w77.tail708c1b.ts.net` |
| `DO_PULL` / `BUMP_BUILD` | `1` |
