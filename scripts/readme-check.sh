#!/usr/bin/env bash
# 把 README 的「最小用法」代码块逐字抽出来，灌进一个指向本仓源码的独立工程，真编译真跑。
#
# 判的是"文档写的形状就是用户抄了能跑的东西"。发布之后这份门禁不改口径：workspace 的 member
# 仍指本仓源码，pin 从 moon.mod 现读，不写死版本号。
#
# 通过 = 零警告 + failed: 0。警告不许豁免：抽出来的代码是真代码，报警告就是真问题。
set -euo pipefail
: "${MOON_HOME:?需要先 export MOON_HOME}"
cd "$(dirname "$0")/.."
REPO=$(pwd -W 2>/dev/null || pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/moonoss-readme-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

CHECK="$WORK/readme_check"
mkdir -p "$CHECK"

{
  echo 'members = ['
  echo "  \"$REPO\","
  echo '  "./readme_check",'
  echo ']'
} > "$WORK/moon.work"

VERSION=$(sed -nE 's/^version = "([^"]+)".*/\1/p' moon.mod | head -1)
ASYNC=$(sed -nE 's/.*"moonbitlang\/async@([^"]+)".*/\1/p' moon.mod | head -1)
HUTOOL=$(sed -nE 's/.*"mldong\/moon-hutool@([^"]+)".*/\1/p' moon.mod | head -1)
{
  echo 'name = "mldong/readme_check"'
  echo 'version = "0.0.0"'
  echo 'preferred_target = "wasm"'
  echo 'import {'
  echo "  \"mldong/moon-oss@$VERSION\","
  echo "  \"moonbitlang/async@$ASYNC\","
  echo "  \"mldong/moon-hutool@$HUTOOL\","
  echo '}'
} > "$CHECK/moon.mod"

python - "$REPO" "$CHECK" <<'PY'
import io, os, re, sys

repo, check = sys.argv[1], sys.argv[2]
# alias -> 包路径；抽出来的代码里出现过 @alias. 才引，多引一个包对包本身就是 unused_package。
ALIASES = [
    ("sdk", "mldong/moon-oss/oss"),
    ("ossauth", "mldong/moon-oss/auth"),
    ("ossconfig", "mldong/moon-oss/config"),
    ("osserror", "mldong/moon-oss/error"),
    ("transport", "mldong/moon-hutool/http"),
    ("xml", "mldong/moon-oss/oss"),
]
RUNTIME = [
    ("utf8", "moonbitlang/core/encoding/utf8"),
    ("env", "moonbitlang/core/env"),
]

src = io.open(os.path.join(repo, "README.md"), encoding="utf-8").read()
found = re.search(r"## 最小用法\s+```moonbit\n(.*?)\n```", src, re.S)
if not found:
    raise SystemExit("README 里没有「最小用法」的 moonbit 代码块，这条门禁等于没跑")
code = found.group(1)
if "async test" not in code and "test \"" not in code:
    raise SystemExit("README 的代码块里没有 test：它不会被执行，门禁就只剩编译")
io.open(os.path.join(check, "readme_oss_test.mbt"), "w",
        encoding="utf-8", newline="\n").write(code + "\n")

entries = []
for alias, pkg in ALIASES + RUNTIME:
    if ("@" + alias + ".") in code:
        entries.append('  "%s" @%s,' % (pkg, alias))
# async 运行时只在抽出来的代码真用得上时才引：文档块可能是纯同步的（例如只算签名与 URL），
# 无条件引就是 unused_package 警告，零警告口径下会把门禁永久钉红。
if any(tok in code for tok in ("async test", "await ", "@async.")):
    entries.append('  "moonbitlang/async",')
Q = chr(34)
text = (
    "import {" + "\n" + "\n".join(entries) + "\n"
    + "} for " + Q + "test" + Q + "\n\n"
    + "supported_targets = " + Q + "wasm+native" + Q + "\n"
)
io.open(os.path.join(check, "moon.pkg"), "w", encoding="utf-8", newline="\n").write(text)
print("extracted 1 block, imports %d" % len(entries))
PY

cd "$WORK"
log=$(moon test --target wasm -j 1 ./readme_check 2>&1) || true
printf '%s\n' "$log" | tail -5
if printf '%s' "$log" | grep -q "Warning"; then
  printf '%s\n' "$log" | grep -B2 -A 8 "Warning" | head -40
  echo "README CHECK FAIL: 抽出来的代码有警告（零警告口径下这是错误）" >&2
  exit 1
fi
if printf '%s' "$log" | grep -q "failed: 0"; then
  echo "README CHECK PASS（零警告，真编译真跑）"
else
  echo "README CHECK FAIL" >&2
  exit 1
fi
