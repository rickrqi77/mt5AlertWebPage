# GOLD ALERT · Ad Hoc + 网页安装（D:\ota-site）

与其它 App **同一层目录** `D:\ota-site`。  
安装按钮**合并进共享 `index.html`**（只更新本应用标记区块，不整页覆盖）。

Safari 打开：

**https://w77.tail708c1b.ts.net/**

不要对签好的包再跑 `xtool dev` / `xtool install`。

## 1. 证书与描述文件

`D:\goldalert\adhoc`：

| 文件 | 说明 |
|------|------|
| `distribution.p12` | Apple Distribution |
| `p12.pass` | 密码一行 |
| `goldalert-adhoc.mobileprovision` | Bundle ID `com.rickrqi77.goldalert` |

## 2. 打包

```bash
cd gold-alert/ios/GoldAlert
./scripts/pack-onsite.sh
```

或 `scripts\pack-onsite.bat`

写入 `D:\ota-site\`：

| 文件 | 说明 |
|------|------|
| `index.html` | 合并 GOLD ALERT「安装」按钮（保留其它 App 内容） |
| `goldalert-manifest.plist` | 清单 |
| `GOLDALERT-adhoc.ipa` | 安装包 |
| `goldalert-icon.png` | 图标 |

## 3. 安装

1. 站点根 = `D:\ota-site`
2. Safari 打开 https://w77.tail708c1b.ts.net/
3. 在页面里点 **安装 GOLD ALERT**

## 4. 环境变量

| 变量 | 默认 |
|------|------|
| `OTA_SITE_DIR` | `/mnt/d/ota-site` |
| `OTA_BASE_URL` | `https://w77.tail708c1b.ts.net` |
| `ADHOC_DIR` | `/mnt/d/goldalert/adhoc` |
