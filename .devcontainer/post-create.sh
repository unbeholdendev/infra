#!/usr/bin/env bash
set -euo pipefail

cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{
  "permissions": { "defaultMode": "bypassPermissions" },
  "skipDangerousModePermissionPrompt": true,
  "theme": "dark"
}
JSON

echo "post-create done"
