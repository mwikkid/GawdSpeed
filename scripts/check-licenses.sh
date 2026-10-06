#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Earl Scioneaux, III
#
# License and secrets check (spec §7.6). Run from anywhere; exits non-zero on
# any problem. Runs in CI on every push and before every release.

set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

# 1. Every vendored library has its license, a VERSION file, a
#    MODIFICATIONS.md and an entry in THIRD_PARTY_NOTICES.md.
for dir in ThirdParty/*/; do
    dir=${dir%/}
    name=${dir#ThirdParty/}
    compgen -G "$dir/LICENSE*" > /dev/null || compgen -G "$dir/COPYING*" > /dev/null \
        || fail "$dir has no LICENSE or COPYING file"
    [[ -f "$dir/VERSION" ]] || fail "$dir has no VERSION file"
    [[ -f "$dir/MODIFICATIONS.md" ]] || fail "$dir has no MODIFICATIONS.md"
    grep -q "\`ThirdParty/$name\`" THIRD_PARTY_NOTICES.md \
        || fail "THIRD_PARTY_NOTICES.md has no entry for ThirdParty/$name"
done

# 2. Every license file the notices link to exists.
while read -r path; do
    [[ -f "$path" ]] || fail "THIRD_PARTY_NOTICES.md links to missing $path"
done < <(grep -o 'LICENSES/[A-Za-z0-9._-]*\.txt' THIRD_PARTY_NOTICES.md | sort -u)

# 3. Every Swift/C/C++/ObjC/shell file we own carries the SPDX header in its
#    first five lines.
while IFS= read -r file; do
    head -n 5 "$file" | grep -q "SPDX-License-Identifier: GPL-3.0-or-later" \
        || fail "$file has no SPDX header"
    head -n 5 "$file" | grep -q "Copyright (C) 2026 Earl Scioneaux, III" \
        || fail "$file has no copyright line"
done < <(git ls-files --cached --others --exclude-standard \
            -- '*.swift' '*.c' '*.cpp' '*.h' '*.hpp' '*.m' '*.mm' '*.sh' \
         | grep -v '^ThirdParty/')

# 4. No signing or notarization secrets are tracked.
secrets=$(git ls-files | grep -Ei '\.(p12|p8|cer|mobileprovision|provisionprofile|certSigningRequest)$|(^|/)\.env(\.|$)|AuthKey_|notarize-credentials' || true)
[[ -z "$secrets" ]] || fail "secret-looking files are tracked: $secrets"

# 5. No ThirdParty/<name> folder is on a header search path: its VERSION file
#    would shadow the C++ standard header <version> on a case-insensitive disk.
grep -nE 'ThirdParty/[A-Za-z0-9_-]+' project.yml | grep -E 'SEARCH_PATHS|-I' \
    && fail "project.yml puts a ThirdParty/<name> folder on a search path"

if (( failures > 0 )); then
    echo "check-licenses: $failures problem(s)"
    exit 1
fi
echo "check-licenses: OK"
