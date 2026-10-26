#!/usr/bin/env bash
# Create the self-signed code-signing certificate used for free (non-notarized) releases.
# Run ONCE, keep the output forever. See docs/RELEASING.md → "Self-signed releases".
#
#   scripts/create-signing-cert.sh [output-dir]     # default: ~/LocalFlow-signing
#
# Why it matters: macOS ties Accessibility / Input Monitoring grants to the signing
# certificate. Every release signed with this same certificate keeps users' grants; a new
# certificate makes every user re-grant. So never regenerate it — back it up instead.
#
# Writes (outside the repository, never commit these):
#   LocalFlow-Self-Signed.p12   certificate + private key, for the SELF_SIGNED_P12_BASE64 secret
#   p12-password.txt            its random password, for the SELF_SIGNED_P12_PASSWORD secret
# Does not touch your keychain or any system setting.
set -euo pipefail

CN="LocalFlow Self-Signed"
OUT="${1:-$HOME/LocalFlow-signing}"
OPENSSL=/usr/bin/openssl # LibreSSL: writes .p12 files that macOS `security import` accepts

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)/" in
    "$ROOT"/*) die "write the certificate outside the repository (got $OUT)" ;;
esac
[[ -e "$OUT/LocalFlow-Self-Signed.p12" ]] && die "$OUT already has a certificate. Reuse it — a new one resets every user's permissions."

mkdir -p "$OUT"
chmod 700 "$OUT"
umask 077
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $CN
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$work/cert.cnf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
password="$("$OPENSSL" rand -base64 24)"
"$OPENSSL" pkcs12 -export -name "$CN" -inkey "$work/key.pem" -in "$work/cert.pem" \
    -out "$OUT/LocalFlow-Self-Signed.p12" -passout "pass:$password"
printf '%s\n' "$password" > "$OUT/p12-password.txt"

fingerprint="$("$OPENSSL" x509 -in "$work/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"
expires="$("$OPENSSL" x509 -in "$work/cert.pem" -noout -enddate | cut -d= -f2)"

cat <<EOF
Created "$CN" (SHA-1 $fingerprint, expires $expires)
  $OUT/LocalFlow-Self-Signed.p12
  $OUT/p12-password.txt

Next:
  1. Back up both files somewhere safe (e.g. a password manager). Losing them means the
     next release resets every user's permissions.
  2. Add them as GitHub secrets (from the repository directory):
       gh secret set SELF_SIGNED_P12_BASE64 < <(base64 -i "$OUT/LocalFlow-Self-Signed.p12")
       tr -d '\n' < "$OUT/p12-password.txt" | gh secret set SELF_SIGNED_P12_PASSWORD
  3. Tag a release: see docs/RELEASING.md.
EOF
