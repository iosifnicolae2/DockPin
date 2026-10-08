#!/bin/sh
# Looks for sensitive data in every commit of this repo before it is published.
# Usage: scripts/audit.sh   (prints matches; exit 1 if any)
set -u
cd "$(dirname "$0")/.." || exit 2
# git grep -E has no \b, so word ends are spelled out as ([^a-z0-9]|$).
pattern='/Users/|/home/|@gmail|serial number|password *[:=]|secret *[:=]|token *[:=]|BEGIN (RSA |EC |OPENSSH )?PRIVATE|BEGIN CERTIFICATE|AuthKey_|\.(p8|p12|pem)([^a-z0-9]|$)|192\.168\.|10\.[0-9]+\.[0-9]+\.[0-9]+|tmp/claude|scratchpad'
# Lines that only name a secret or a key file type, never hold one.
allowed='^scripts/audit.sh:|^\.github/workflows/release.yml:.*(secrets\.|github\.token|openssl rand|p12|P12|p8|P8)|^scripts/release.sh:[0-9]+:#'

found=0
for rev in $(git rev-list --all); do
    git grep -n -I -i -E "$pattern" "$rev" -- . 2>/dev/null
done | sed -E 's/^[0-9a-f]{40}://' | sort -u | grep -v -E "$allowed" && found=1

echo "--- key or certificate files ever committed:"
git log --all --name-only --format= | sort -u | grep -i -E '\.(p8|p12|pem|cer|key|mobileprovision|provisionprofile)$' && found=1

echo "--- commit authors / committers (public once pushed):"
git log --all --format='%an <%ae> | %cn <%ce>' | sort -u
echo "--- files in the tree:"
git ls-files | sed 's/^/  /'
echo "--- large or binary files:"
git ls-files | while read -r f; do
    size=$(wc -c < "$f")
    [ "$size" -gt 200000 ] && echo "  $f: $size bytes"
done

if [ "$found" = 1 ]; then echo "AUDIT: matches above need a look"; exit 1; fi
echo "AUDIT: no sensitive matches"
