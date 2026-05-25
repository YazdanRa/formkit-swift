#!/bin/bash -e

opts=()
opts+=("--allow-writing-to-directory" "$1")
opts+=("generate-documentation")
opts+=("--target" "FormKitSwift")
opts+=("--output-path" "$1")
opts+=("--disable-indexing")
opts+=("--transform-for-static-hosting")
opts+=("--enable-experimental-combined-documentation")
opts+=("--warnings-as-errors")

if [ -n "$2" ]; then
    opts+=("--hosting-base-path" "$2")
fi

/usr/bin/swift package "${opts[@]}"

echo '{}' > "$1/theme-settings.json"
touch "$1/.nojekyll"

cat > "$1/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="utf-8">
    <title>Redirecting...</title>
    <meta http-equiv="refresh" content="0; url=./documentation/">
  </head>
  <body>
    <p>If you are not redirected automatically, <a href="./documentation/">click here</a>.</p>
  </body>
</html>
EOF
