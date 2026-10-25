#!/usr/bin/env bash
# 拉代码 → xtool 编译 → zsign Ad Hoc 签名 → 写入 D:\onsite\goldalert
# Safari 打开 https://w77.tail708c1b.ts.net/goldalert/ 即可安装（与交通查询同样的网页安装方式）。
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ios_dir="$(cd "$script_dir/.." && pwd)"
repo_dir="$(cd "$ios_dir/../.." && pwd)"

# Windows D:\onsite\goldalert  （WSL: /mnt/d/onsite/goldalert）
onsite_dir="${ONSITE_DIR:-/mnt/d/onsite/goldalert}"
adhoc_dir="${ADHOC_DIR:-/mnt/d/goldalert/adhoc}"
base_url="${OTA_BASE_URL:-https://w77.tail708c1b.ts.net/goldalert}"

p12="$adhoc_dir/distribution.p12"
profile="$adhoc_dir/goldalert-adhoc.mobileprovision"
pass_file="$adhoc_dir/p12.pass"
signed_ipa="$adhoc_dir/GOLDALERT-adhoc.ipa"
bundle_id="com.rickrqi77.goldalert"
app_title="GOLD ALERT"
ipa_name="GOLDALERT-adhoc.ipa"

die() { echo "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "缺少 $1。$2"; }

need git "先安装 git。"
need xtool "先按 ios/GoldAlert/README.md 装好 xtool。"
need zsign "先按 ios/GoldAlert/ADHOC.md 装好 zsign。"
need python3 "sudo apt-get install -y python3"
need openssl "sudo apt-get install -y openssl"
need zip "sudo apt-get install -y zip"

[[ -f "$p12" ]] || die "找不到 $p12（把发布证书放到 D:\\goldalert\\adhoc\\distribution.p12）"
[[ -f "$profile" ]] || die "找不到 $profile（按 ADHOC.md 生成 Ad Hoc 描述文件）"

if [[ -n "${GOLDALERT_P12_PASSWORD:-}" ]]; then
  password="$GOLDALERT_P12_PASSWORD"
elif [[ -f "$pass_file" ]]; then
  password="$(sed '1s/^\xEF\xBB\xBF//' "$pass_file" | tr -d '\r\n')"
else
  die "把 p12 密码存成 $pass_file（不要写进仓库）"
fi
[[ -n "$password" ]] || die "密码为空：$pass_file"

entitlements="$ios_dir/GoldAlert.entitlements"
[[ -f "$entitlements" ]] || die "找不到 $entitlements"

profile_text="$(openssl cms -inform DER -in "$profile" -verify -noverify 2>/dev/null || true)"
[[ -n "$profile_text" ]] || die "读不了描述文件：$profile"
grep -q "$bundle_id" <<<"$profile_text" || die "描述文件 Bundle ID 不是 $bundle_id"

if [[ "${DO_PULL:-1}" == "1" ]]; then
  echo "拉取代码..."
  (
    cd "$repo_dir"
    git fetch origin || true
    if git show-ref --verify --quiet refs/remotes/origin/main; then
      git pull --ff-only origin main || git pull origin main || true
    fi
  )
else
  echo "跳过 git pull（DO_PULL=0）"
fi

if [[ "${BUMP_BUILD:-1}" == "1" ]]; then
  PLIST="$ios_dir/Info.plist"
  python3 - "$PLIST" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
m = re.search(r"<key>CFBundleVersion</key>\s*<string>([^<]*)</string>", text)
cur = m.group(1) if m else ""
nxt = str(int(cur) + 1) if cur.isdigit() else "2"
new, n = re.subn(
    r"(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)",
    rf"\g<1>{nxt}\g<2>",
    text,
    count=1,
)
assert n == 1, "未能更新 CFBundleVersion"
open(path, "w", encoding="utf-8").write(new)
print(f"CFBundleVersion {cur or '?'}->{nxt}")
PY
fi

echo "编译（xtool release IPA）..."
build_log="$(mktemp)"
built_after="$(date +%s)"
(cd "$ios_dir" && xtool dev build --configuration release --ipa) 2>&1 | tee "$build_log"
strip_ansi() { sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g'; }
unsigned="$(strip_ansi < "$build_log" | sed -nE 's/.*Wrote (IPA )?to //p' | tail -1 | tr -d '\r')"
[[ -n "$unsigned" && "$unsigned" != /* ]] && unsigned="$ios_dir/$unsigned"
if [[ -z "$unsigned" || ! -f "$unsigned" ]]; then
  unsigned="$(find "$ios_dir" -name '*.ipa' -newermt "@$((built_after - 5))" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || true)"
fi
[[ -n "$unsigned" && -f "$unsigned" ]] || die "没有找到编译出的 ipa。看上面的 xtool 输出。"
echo "未签名的包：$unsigned"

echo "Ad Hoc 签名..."
mkdir -p "$adhoc_dir" "$onsite_dir"
merged_ents="$(mktemp --suffix=.entitlements)"
profile_plist="$(mktemp --suffix=.plist)"
trap 'rm -f "$build_log" "$merged_ents" "$profile_plist"' EXIT
openssl cms -inform DER -in "$profile" -verify -noverify 2>/dev/null >"$profile_plist" \
  || die "解析描述文件失败"
python3 - "$profile_plist" "$entitlements" "$merged_ents" <<'PY'
import plistlib, sys
profile_path, app_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(profile_path, "rb") as fh:
    profile = plistlib.load(fh)
ents = dict(profile.get("Entitlements") or {})
with open(app_path, "rb") as fh:
    app = plistlib.load(fh)
for key, value in app.items():
    # Skip Xcode build-setting placeholders in template entitlements.
    if isinstance(value, str) and "$(AppIdentifierPrefix)" in value:
        continue
    if isinstance(value, list):
        cleaned = []
        for item in value:
            if isinstance(item, str) and "$(AppIdentifierPrefix)" in item:
                continue
            cleaned.append(item)
        value = cleaned
    ents[key] = value
with open(out_path, "wb") as fh:
    plistlib.dump(ents, fh)
print(ents.get("application-identifier"))
PY

zsign -f -k "$p12" -p "$password" -m "$profile" -e "$merged_ents" -o "$signed_ipa" "$unsigned"
[[ -f "$signed_ipa" ]] || die "签名失败"

icon="$ios_dir/Icon.png"
python3 "$script_dir/gen-ota-manifest.py" \
  --ipa "$signed_ipa" \
  --base-url "$base_url" \
  --title "$app_title" \
  --out-dir "$onsite_dir" \
  --ipa-name "$ipa_name" \
  --icon "$icon"

# Also keep a copy next to certs for backup.
cp -f "$onsite_dir/$ipa_name" "$signed_ipa" 2>/dev/null || true

cat <<EOF

完成。Safari 安装页：
  $base_url/

文件已写入：
  $onsite_dir\\index.html
  $onsite_dir\\manifest.plist
  $onsite_dir\\$ipa_name

确认 Tailscale / 本机已把 https://w77.tail708c1b.ts.net 指到 D:\\onsite（或把 goldalert 目录挂在该站点下）。
iPhone 用 Safari 打开上面的地址，点「用 Safari 安装」。
EOF
