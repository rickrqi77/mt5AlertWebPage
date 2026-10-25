#!/usr/bin/env python3
"""Generate / update multi-app Ad Hoc OTA manifests + Safari install index.

Keeps apps.json under the OTA site. Can upsert one IPA, or --scan-all to
list every *.ipa in the out-dir (so file manager / transit / xauusd all show).

Usage:
  python3 gen-ota-manifest.py --ipa PATH --base-url URL --title 黄金报价 --slug xauusd --out-dir DIR
  python3 gen-ota-manifest.py --base-url URL --out-dir DIR --scan-all
  python3 gen-ota-manifest.py --base-url URL --out-dir DIR --init
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape


APPS_JSON = "apps.json"


def read_bundle_info(ipa: Path) -> tuple[str, str, str, str]:
    """Return (bundle_id, version, short_version, display_title)."""
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
    title = (
        str(info.get("CFBundleDisplayName") or "").strip()
        or str(info.get("CFBundleName") or "").strip()
        or ipa.stem
    )
    if not bid:
        raise SystemExit(f"Info.plist 缺少 CFBundleIdentifier: {ipa}")
    return bid, ver, short, title


def slugify(text: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower()).strip("-")
    return s or "app"


def load_apps(out: Path) -> list[dict]:
    path = out / APPS_JSON
    if not path.is_file():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict) and isinstance(data.get("apps"), list):
        return list(data["apps"])
    if isinstance(data, list):
        return list(data)
    return []


def save_apps(out: Path, apps: list[dict]) -> None:
    payload = {"apps": apps}
    (out / APPS_JSON).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def write_manifest(
    out: Path,
    *,
    slug: str,
    ipa_name: str,
    base_url: str,
    title: str,
    bid: str,
    ver: str,
) -> Path:
    base = base_url.rstrip("/")
    ipa_url = f"{base}/{ipa_name}"
    manifest = {
        "items": [
            {
                "assets": [{"kind": "software-package", "url": ipa_url}],
                "metadata": {
                    "bundle-identifier": bid,
                    "bundle-version": ver,
                    "kind": "software",
                    "title": title,
                },
            }
        ]
    }
    path = out / f"manifest-{slug}.plist"
    with path.open("wb") as fh:
        plistlib.dump(manifest, fh)
    return path


def write_index(out: Path, apps: list[dict], base_url: str) -> None:
    base = base_url.rstrip("/")
    rows: list[str] = []
    for app in apps:
        title = escape(str(app.get("title") or app.get("slug") or "App"))
        slug = escape(str(app.get("slug") or ""))
        short = escape(str(app.get("short_version") or ""))
        ver = escape(str(app.get("version") or ""))
        bid = escape(str(app.get("bundle_id") or ""))
        ipa_name = escape(str(app.get("ipa") or ""))
        manifest_url = f"{base}/manifest-{slug}.plist"
        itms = f"itms-services://?action=download-manifest&url={manifest_url}"
        ipa_url = f"{base}/{ipa_name}"
        rows.append(
            f"""
<section class="app">
  <h2>{title}</h2>
  <p class="meta">版本 {short}（build {ver}）<br/>
  Bundle ID：<code>{bid}</code><br/>
  文件：<code>{ipa_name}</code></p>
  <p><a class="btn" href="{escape(itms)}">Safari 安装</a></p>
  <p class="links">IPA：<a href="{escape(ipa_url)}"><code>{escape(ipa_url)}</code></a></p>
</section>
"""
        )

    body = (
        "\n".join(rows)
        if rows
        else "<p>目录里还没有 .ipa。把签好的包放进 D:\\ota-site 后执行 scan-ota-site / publish-ota。</p>"
    )
    html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>OTA 安装</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  margin: 0; padding: 1.5rem; line-height: 1.55; background: #0b0b0c; color: #f2f2f2; }}
h1 {{ font-size: 1.4rem; margin: 0 0 0.5rem; }}
.lead {{ color: #a0a0a8; margin-bottom: 1.5rem; }}
.app {{ border-top: 1px solid #2a2a30; padding: 1.25rem 0; }}
.app h2 {{ margin: 0 0 0.4rem; font-size: 1.15rem; }}
.meta {{ color: #a0a0a8; font-size: 0.92rem; }}
a.btn {{ display: inline-block; padding: 12px 18px; background: #0a84ff; color: #fff;
  border-radius: 10px; text-decoration: none; font-weight: 600; }}
a {{ color: #6cb6ff; }}
code {{ word-break: break-all; font-size: 0.85rem; }}
.note {{ margin-top: 2rem; color: #888; font-size: 0.85rem; }}
</style>
</head>
<body>
<h1>OTA 安装</h1>
<p class="lead">用 <strong>Safari</strong> 打开本页，点「Safari 安装」。设备须在对应 Ad Hoc 描述文件的 UDID 列表中。</p>
{body}
<p class="note">本页会列出 D:\\ota-site 下全部 .ipa（scan-all / publish-ota 刷新）。Tailscale → http://127.0.0.1:8080，8080 需常驻服务该目录。</p>
</body>
</html>
"""
    (out / "index.html").write_text(html, encoding="utf-8")
    (out / "install.html").write_text(html, encoding="utf-8")


def upsert_app(apps: list[dict], entry: dict) -> list[dict]:
    slug = entry["slug"]
    ipa = entry.get("ipa")
    bid = entry.get("bundle_id")
    out = []
    for a in apps:
        if a.get("slug") == slug:
            continue
        if ipa and a.get("ipa") == ipa:
            continue
        if bid and a.get("bundle_id") == bid:
            continue
        out.append(a)
    out.append(entry)
    out.sort(key=lambda a: str(a.get("title") or a.get("slug") or "").lower())
    return out


def sync_all_ipas(out: Path, base_url: str, existing: list[dict]) -> list[dict]:
    """Rebuild catalog from every *.ipa in out; keep prior title/slug when possible."""
    by_ipa = {str(a.get("ipa") or ""): a for a in existing}
    by_bid = {str(a.get("bundle_id") or ""): a for a in existing}
    used_slugs: set[str] = set()
    apps: list[dict] = []

    for ipa in sorted(out.glob("*.ipa"), key=lambda p: p.name.lower()):
        try:
            bid, ver, short, display = read_bundle_info(ipa)
        except SystemExit as exc:
            print(f"skip {ipa.name}: {exc}")
            continue

        prev = by_ipa.get(ipa.name) or by_bid.get(bid)
        if prev and prev.get("slug"):
            slug = str(prev["slug"])
        else:
            slug = slugify(bid.split(".")[-1] if bid else ipa.stem)
        base_slug = slug
        n = 2
        while slug in used_slugs:
            slug = f"{base_slug}-{n}"
            n += 1
        used_slugs.add(slug)

        title = str((prev or {}).get("title") or display or ipa.stem)
        write_manifest(
            out,
            slug=slug,
            ipa_name=ipa.name,
            base_url=base_url,
            title=title,
            bid=bid,
            ver=ver,
        )
        apps.append(
            {
                "slug": slug,
                "title": title,
                "ipa": ipa.name,
                "bundle_id": bid,
                "version": ver,
                "short_version": short,
            }
        )
        print(f"  + {title} ({ipa.name})")

    apps.sort(key=lambda a: str(a.get("title") or a.get("slug") or "").lower())
    return apps


def main() -> None:
    parser = argparse.ArgumentParser(description="Multi-app Ad Hoc OTA index + manifests")
    parser.add_argument("--ipa", type=Path, help="Signed IPA to publish")
    parser.add_argument("--base-url", required=True, help="https://HOST 无尾斜杠")
    parser.add_argument("--title", default="App")
    parser.add_argument("--slug", help="Stable id for manifest filename, e.g. xauusd")
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument(
        "--rebuild-index",
        action="store_true",
        help="Regenerate index from apps.json (also rescans *.ipa)",
    )
    parser.add_argument(
        "--scan-all",
        action="store_true",
        help="List every *.ipa in out-dir on the install page",
    )
    parser.add_argument(
        "--init",
        action="store_true",
        help="Create empty apps.json + index/install.html (no IPA required)",
    )
    args = parser.parse_args()

    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    apps = load_apps(out)

    if args.init and not args.scan_all and not args.ipa:
        if not apps:
            save_apps(out, [])
            apps = []
        write_index(out, apps, args.base_url)
        print(f"apps.json: {out / APPS_JSON}")
        print(f"index:     {out / 'index.html'}")
        print(f"install:   {out / 'install.html'}")
        return

    if args.scan_all or args.rebuild_index:
        print(f"==> Scanning {out} for *.ipa")
        apps = sync_all_ipas(out, args.base_url, apps)
        save_apps(out, apps)
        write_index(out, apps, args.base_url)
        print(f"index: {out / 'index.html'}  apps: {len(apps)}")
        return

    if not args.ipa:
        raise SystemExit("需要 --ipa，或使用 --scan-all / --rebuild-index / --init")
    ipa = args.ipa.resolve()
    if not ipa.is_file():
        raise SystemExit(f"找不到 IPA: {ipa}")

    bid, ver, short, display = read_bundle_info(ipa)
    title = args.title if args.title and args.title != "App" else display
    slug = args.slug or slugify(bid.split(".")[-1] if bid else title)

    if ipa.parent != out:
        dest = out / ipa.name
        if not dest.exists() or dest.stat().st_mtime < ipa.stat().st_mtime:
            dest.write_bytes(ipa.read_bytes())
        ipa_name = dest.name
    else:
        ipa_name = ipa.name

    entry = {
        "slug": slug,
        "title": title,
        "ipa": ipa_name,
        "bundle_id": bid,
        "version": ver,
        "short_version": short,
    }
    apps = upsert_app(apps, entry)
    # After adding one app, rescan so sibling IPAs stay listed
    apps = sync_all_ipas(out, args.base_url, apps)
    # Prefer explicit title/slug for the IPA we just published
    for a in apps:
        if a.get("ipa") == ipa_name:
            a["title"] = title
            a["slug"] = slug
            write_manifest(
                out,
                slug=slug,
                ipa_name=ipa_name,
                base_url=args.base_url,
                title=title,
                bid=bid,
                ver=ver,
            )
            break
    apps.sort(key=lambda a: str(a.get("title") or a.get("slug") or "").lower())
    save_apps(out, apps)
    write_index(out, apps, args.base_url)

    base = args.base_url.rstrip("/")
    manifest_url = f"{base}/manifest-{slug}.plist"
    itms = f"itms-services://?action=download-manifest&url={manifest_url}"
    print(f"manifest: {out / f'manifest-{slug}.plist'}")
    print(f"index:    {out / 'index.html'}")
    print(f"install:  {out / 'install.html'}")
    print(f"apps:     {len(apps)}")
    print(f"itms:     {itms}")


if __name__ == "__main__":
    main()
