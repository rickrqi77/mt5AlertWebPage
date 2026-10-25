#!/usr/bin/env python3
"""Publish GOLD ALERT into shared D:\\ota-site and merge install into index.html.

Same directory as other apps. Only touches uniquely named goldalert files, plus a
marked block inside index.html (does not wipe other apps' install entries).
"""

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


def install_block(
    *,
    title: str,
    short: str,
    ver: str,
    bid: str,
    itms: str,
    ipa_url: str,
    icon_name: str | None,
) -> str:
    icon_html = (
        f'<img class="ga-icon" src="{escape(icon_name)}" alt="" width="56" height="56"/>'
        if icon_name
        else ""
    )
    return f"""{BEGIN}
<section class="ga-card" id="goldalert">
  {icon_html}
  <div class="ga-body">
    <h2>{escape(title)}</h2>
    <p class="ga-meta">版本 {escape(short)}（build {escape(ver)}） · <code>{escape(bid)}</code></p>
    <p>
      <a class="ga-btn" href="{escape(itms)}">安装 {escape(title)}</a>
    </p>
    <p class="ga-note">Safari 打开本页后点安装。IPA：<a href="{escape(ipa_url)}">{escape(Path(ipa_url).name)}</a></p>
  </div>
</section>
{END}
"""


def upsert_into_index(out: Path, block: str) -> Path:
    """Merge GOLD ALERT install card into shared index.html; preserve other content."""
    hub = out / "index.html"
    style = """
<style id="goldalert-ota-style">
.ga-card{display:flex;gap:14px;align-items:flex-start;margin:16px 0;padding:16px;
  border-radius:14px;background:rgba(212,160,23,.08);border:1px solid rgba(212,160,23,.25)}
.ga-icon{border-radius:12px;flex-shrink:0}
.ga-body{flex:1;min-width:0}
.ga-card h2{margin:0 0 6px;font-size:20px;color:#d4a017}
.ga-meta{margin:0 0 12px;color:rgba(255,255,255,.55);font-size:13px;line-height:1.4}
.ga-btn{display:inline-block;padding:10px 16px;border-radius:10px;background:#d4a017;
  color:#111;text-decoration:none;font-weight:700}
.ga-note{margin:10px 0 0;font-size:12px;color:rgba(255,255,255,.4)}
.ga-note a{color:#d4a017}
</style>
"""

    if hub.is_file():
        text = hub.read_text(encoding="utf-8")
        if 'id="goldalert-ota-style"' not in text:
            if "</head>" in text.lower():
                idx = text.lower().rfind("</head>")
                # find actual </head> with original casing
                m = re.search(r"</head>", text, flags=re.I)
                if m:
                    text = text[: m.start()] + style + "\n" + text[m.start() :]
            else:
                text = style + "\n" + text

        if BEGIN in text and END in text:
            text = re.sub(
                re.escape(BEGIN) + r".*?" + re.escape(END),
                block.strip(),
                text,
                count=1,
                flags=re.S,
            )
        else:
            m = re.search(r"</body>", text, flags=re.I)
            if m:
                text = text[: m.start()] + "\n" + block + "\n" + text[m.start() :]
            else:
                text = text.rstrip() + "\n" + block + "\n"
        hub.write_text(text, encoding="utf-8")
        return hub

    hub.write_text(
        f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>OTA 安装</title>
{style}
<style>
body{{font-family:-apple-system,sans-serif;margin:1.5rem;background:#0a0a0a;color:#f2f2f2}}
</style>
</head>
<body>
<h1>安装应用</h1>
<p>用 iPhone <b>Safari</b> 打开本页，点对应按钮安装。</p>
{block}
</body>
</html>
""",
        encoding="utf-8",
    )
    return hub


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
    parser.add_argument("--icon-name", default=f"{APP_SLUG}-icon.png")
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

    icon_path = out / args.icon_name
    has_icon = False
    if args.icon and args.icon.is_file():
        shutil.copy2(args.icon, icon_path)
        has_icon = True

    base = args.base_url.rstrip("/")
    ipa_url = f"{base}/{args.ipa_name}"
    manifest_url = f"{base}/{args.manifest_name}"
    icon_url = f"{base}/{args.icon_name}"

    assets = [{"kind": "software-package", "url": ipa_url}]
    if has_icon:
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
    block = install_block(
        title=args.title,
        short=short,
        ver=ver,
        bid=bid,
        itms=itms,
        ipa_url=ipa_url,
        icon_name=args.icon_name if has_icon else None,
    )
    hub = upsert_into_index(out, block)

    print(f"ota-site:  {out}")
    print(f"index:     {hub}")
    print(f"manifest:  {out / args.manifest_name}")
    print(f"ipa:       {dest_ipa}")
    print(f"install:   {base}/")
    print(f"itms:      {itms}")


if __name__ == "__main__":
    main()
