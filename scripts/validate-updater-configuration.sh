#!/bin/sh
# Xcode passes resolved build settings. Require a direct release feed and signing public key.
set -eu
[ "${CONFIGURATION}" = Release ] || exit 0
if ! printf '%s' "${SPARKLE_FEED_URL:-}" | /usr/bin/grep -Eq '^https://[[:alnum:]][[:alnum:].-]*(:[0-9]+)?/[^[:space:]]+$'; then
    echo 'error: Direct releases require an HTTPS SPARKLE_FEED_URL with a host and feed path.' >&2
    exit 1
fi
if ! printf '%s' "${SPARKLE_PUBLIC_ED_KEY:-}" | /usr/bin/grep -Eq '^[A-Za-z0-9+/]{43}=$'; then
    echo 'error: Direct releases require a base64-encoded 32-byte SPARKLE_PUBLIC_ED_KEY.' >&2
    exit 1
fi
key_bytes=$(printf '%s' "${SPARKLE_PUBLIC_ED_KEY:-}" | /usr/bin/base64 -D 2>/dev/null | /usr/bin/wc -c | /usr/bin/tr -d ' ')
if [ "$key_bytes" != 32 ]; then
    echo 'error: Direct releases require a base64-encoded 32-byte SPARKLE_PUBLIC_ED_KEY.' >&2
    exit 1
fi
