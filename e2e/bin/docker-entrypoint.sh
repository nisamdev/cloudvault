#!/bin/sh
# Wait until the Vite dev server answers, then run the suite. `depends_on`
# only waits for the container to start, and Vite is not listening yet.
set -eu

url="${PLAYWRIGHT_BASE_URL:-http://127.0.0.1:5173}"
echo "Waiting for ${url}"

i=0
while [ "$i" -lt 90 ]; do
  if node -e "fetch(process.argv[1]).then(() => process.exit(0)).catch(() => process.exit(1))" "$url"; then
    exec npx playwright test "$@"
  fi
  i=$((i + 1))
  sleep 1
done

echo "Timed out waiting for ${url}" >&2
exit 1
