#!/usr/bin/env python3
"""Publish GOLD ALERT OTA files into a shared D:\\ota-site root without clobbering other apps."""

from __future__ import annotations

import argparse
import plistlib
import re
import shutil
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

APP_SLUG = "goldalert"
BEGIN = "<!-- GOLDALERT-OTA-BEGIN -->"
END = "<!-- GOLDALERT-OTA-END -->"


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


def upsert_hub_index(out: Path, base: str, title: str, page_name: str, short: str, ver: str) -> None:
    """Add/replace only the GOLDALERT marker block inside shared index.html."""
    hub = out / "index.html"
    link = f"{base.rstrip('/')}/{page_name}"
    block = f"""{BEGIN}
  <a class="app" href="{escape(page_name)}">
    <strong>{escape(title)}</strong>
    <span>v{escape(short)} (build {escape(ver)})</span>
  </a>
{END}
"""
    if hub.is_file():
        text = hub.read_text(encoding="utf-8")
        if BEGIN in text and END in text:
            text = re.sub(
                re.escape(BEGIN) + r".*?" + re.escape(END),
                block.strip(),
                text,
                count=1,
                flags=re.S,
            )
        else:
            # Keep existing page; append our block before </body> when possible.
            if "</body>" in text.lower():
                # Case-sensitive replace of last </body>
                idx = text.lower().rfind("</body>")
                text = text[:idx] + "\n" + block + "\n" + text[idx:]
            else:
                text = text.rstrip() + "\n" + block + "\n"
        hub.write_text(text, encoding="utf-8")
        return

    # No hub yet: create a minimal multi-app landing page.
    hub.write_text(
        f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>OTA 安装</title>
<style>
body {{ font-family: -apple-system, sans-serif; margin: 2rem; background:#0a0a0a; color:#f2f2f2; }}
a.app {{ display:block; padding:14px 16px; margin:10px 0; border-radius:12px;
  background:rgba(255,255,255,.06); color:#f2f2f2; text-decoration:none; }}
a.app span {{ display:block; color:rgba(255,255,255,.45); font-size:13px; margin-top:4px; }}
</style>
</head>
<body>
<h1>安装应用</h1>
<p>用 iPhone Safari 打开对应页面安装。</p>
{block}
</body>
</html>
""",
        encoding="utf-8",
    )
    _ = link  # reserved for future absolute links


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument(
        "--base-url",
        required=True,
        help="Shared HTTPS root, e.g. https://w77.tail708c1b.ts.net",
    )
    parser.add_argument("--title", default="GOLD ALERT")
    parser.add_argument("--out-dir", required=True, type=Path, help="Usually D:\\ota-site")
    parser.add_argument("--ipa-name", default="GOLDALERT-adhoc.ipa")
    parser.add_argument("--manifest-name", default=f"{APP_SLUG}-manifest.plist")
    parser.add_argument("--page-name", default=f"{APP_SLUG}.html")
    parser.add_argument("--icon-name", default=f"{APP_SLUG}-icon.png")
    parser.add_argument("--icon", type=Path, default=None)
    parser.add_argument(
        "--update-hub",
        action="store_true",
        default=True,
        help="Upsert GOLD ALERT link into shared index.html (default on)",
    )
    parser.add_argument("--no-update-hub", action="store_false", dest="update_hub")
    args = parser.parse_args()

    ipa = args.ipa.resolve()
    if not ipa.is_file():
        raise SystemExit(f"找不到 IPA: {ipa}")

    bid, ver, short = read_bundle_info(ipa)
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)

    # Unique names only — never write generic manifest.plist / icon.png / install.html.
    dest_ipa = out / args.ipa_name
    if ipa != dest_ipa:
        shutil.copy2(ipa, dest_ipa)

    icon_path = out / args.icon_name
    if args.icon and args.icon.is_file():
        shutil.copy2(args.icon, icon_path)

    base = args.base_url.rstrip("/")
    ipa_url = f"{base}/{args.ipa_name}"
    manifest_url = f"{base}/{args.manifest_name}"
    icon_url = f"{base}/{args.icon_name}"
    page_url = f"{base}/{args.page_name}"

    assets = [{"kind": "software-package", "url": ipa_url}]
    if icon_path.is_file():
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
    with (out / args.manifest_name).open("wb") as fh:
        plistlib.dump(manifest, fh)

    itms = f"itms-services://?action=download-manifest&url={manifest_url}"
    has_icon = icon_path.is_file()
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
h1 {{ margin: 0 0 8px; font-size: 26px; letter-spacing: .04em; color: #d4a017; }}
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
    {"<img class='icon' src='" + escape(args.icon_name) + "' alt=''/>" if has_icon else ""}
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
    (out / args.page_name).write_text(html, encoding="utf-8")

    if args.update_hub:
        upsert_hub_index(out, base, args.title, args.page_name, short, ver)

    print(f"ota-site:  {out}")
    print(f"page:      {out / args.page_name}")
    print(f"manifest:  {out / args.manifest_name}")
    print(f"ipa:       {dest_ipa}")
    print(f"install:   {page_url}")
    print(f"itms:      {itms}")


if __name__ == "__main__":
    main()
