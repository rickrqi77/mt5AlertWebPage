#!/usr/bin/env python3
"""Generate Safari OTA manifest.plist + index.html for an Ad Hoc IPA (ota-site)."""

from __future__ import annotations

import argparse
import plistlib
import re
import shutil
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape


def read_bundle_info(ipa: Path) -> tuple[str, str, str]:
    with zipfile.ZipFile(ipa) as zf:
        info_name = next(
            (n for n in zf.namelist() if re.match(r"Payload/[^/]+\.app/Info\.plist$", n)),
            None,
        )
        if not info_name:
            raise SystemExit(f"IPA 内未找到 Info.plist: {ipa}")
        raw = zf.read(info_name)
    info = plistlib.loads(raw)
    bid = str(info.get("CFBundleIdentifier") or "")
    ver = str(info.get("CFBundleVersion") or "1")
    short = str(info.get("CFBundleShortVersionString") or ver)
    if not bid:
        raise SystemExit("Info.plist 缺少 CFBundleIdentifier")
    return bid, ver, short


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument(
        "--base-url",
        required=True,
        help="HTTPS base for this app folder, e.g. https://w77.tail708c1b.ts.net/goldalert",
    )
    parser.add_argument("--title", default="GOLD ALERT")
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--ipa-name", default="GOLDALERT-adhoc.ipa")
    parser.add_argument("--icon", type=Path, default=None)
    args = parser.parse_args()

    ipa = args.ipa.resolve()
    if not ipa.is_file():
        raise SystemExit(f"找不到 IPA: {ipa}")

    bid, ver, short = read_bundle_info(ipa)
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)

    dest_ipa = out / args.ipa_name
    if ipa != dest_ipa:
        shutil.copy2(ipa, dest_ipa)

    if args.icon and args.icon.is_file():
        shutil.copy2(args.icon, out / "icon.png")

    base = args.base_url.rstrip("/")
    ipa_url = f"{base}/{args.ipa_name}"
    manifest_url = f"{base}/manifest.plist"
    icon_url = f"{base}/icon.png"

    assets = [
        {"kind": "software-package", "url": ipa_url},
    ]
    if (out / "icon.png").is_file():
        assets.append({"kind": "display-image", "url": icon_url})
        assets.append({"kind": "full-size-image", "url": icon_url})

    manifest = {
        "items": [
            {
                "assets": assets,
                "metadata": {
                    "bundle-identifier": bid,
                    "bundle-version": ver,
                    "kind": "software",
                    "title": args.title,
                },
            }
        ]
    }
    with (out / "manifest.plist").open("wb") as fh:
        plistlib.dump(manifest, fh)

    itms = f"itms-services://?action=download-manifest&url={manifest_url}"
    html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
<meta name="apple-mobile-web-app-capable" content="yes"/>
<title>安装 {escape(args.title)}</title>
<style>
:root {{ color-scheme: dark; }}
body {{
  margin: 0; min-height: 100dvh; font-family: -apple-system, "SF Pro Text", sans-serif;
  background: radial-gradient(ellipse 120% 60% at 50% -10%, rgba(212,160,23,.18), transparent 55%),
              linear-gradient(180deg, #111 0%, #0a0a0a 45%);
  color: #f2f2f2; display: flex; align-items: center; justify-content: center;
}}
.card {{
  width: min(420px, 92vw); padding: 28px 22px 24px; border-radius: 18px;
  background: rgba(255,255,255,.05); border: 1px solid rgba(255,255,255,.08);
  text-align: center;
}}
.icon {{ width: 88px; height: 88px; border-radius: 20px; margin-bottom: 14px;
  box-shadow: 0 8px 24px rgba(0,0,0,.35); }}
h1 {{ margin: 0 0 8px; font-size: 26px; letter-spacing: .04em;
  color: #d4a017; }}
.meta {{ color: rgba(255,255,255,.55); font-size: 14px; line-height: 1.5; margin: 0 0 22px; }}
a.btn {{
  display: inline-block; width: 100%; box-sizing: border-box; padding: 14px 16px;
  background: #d4a017; color: #111; border-radius: 12px; text-decoration: none;
  font-weight: 700; font-size: 17px;
}}
.note {{ margin-top: 18px; font-size: 12px; color: rgba(255,255,255,.4); line-height: 1.45; text-align: left; }}
code {{ word-break: break-all; font-size: 11px; }}
</style>
</head>
<body>
  <div class="card">
    {"<img class='icon' src='icon.png' alt=''/>" if (out / "icon.png").is_file() else ""}
    <h1>{escape(args.title)}</h1>
    <p class="meta">版本 {escape(short)}（build {escape(ver)}）<br/>
    Bundle ID：<code>{escape(bid)}</code></p>
    <a class="btn" href="{escape(itms)}">用 Safari 安装</a>
    <p class="note">
      请用 iPhone 的 <b>Safari</b> 打开本页（不要用微信内置浏览器）。<br/>
      设备 UDID 须在 Ad Hoc 描述文件中；首次安装后到
      「设置 → 通用 → VPN 与设备管理」信任证书。<br/>
      IPA：<a href="{escape(ipa_url)}"><code>{escape(ipa_url)}</code></a>
    </p>
  </div>
</body>
</html>
"""
    (out / "index.html").write_text(html, encoding="utf-8")
    print(f"ota-site: {out}")
    print(f"manifest: {out / 'manifest.plist'}")
    print(f"index:    {out / 'index.html'}")
    print(f"ipa:      {dest_ipa}")
    print(f"install:  {base}/")
    print(f"itms:     {itms}")


if __name__ == "__main__":
    main()
