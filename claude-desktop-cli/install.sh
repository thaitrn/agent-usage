#!/bin/zsh
set -eu

[[ "$(uname -s)" == "Darwin" ]] || { echo 'Chỉ hỗ trợ macOS.' >&2; exit 1; }
command -v claude >/dev/null || { echo 'Chưa cài Claude Code CLI (`claude`).' >&2; exit 1; }

install_dir="$HOME/.local/bin"
wrapper="$install_dir/claude-desktop"
mkdir -p "$install_dir"

cat > "$wrapper" <<'WRAPPER'
#!/bin/zsh
set -u

claude_bin=$(command -v claude) || { echo 'Không tìm thấy lệnh `claude`.' >&2; exit 1; }

for desktop_pid in $(pgrep -f '/Library/Application Support/Claude/claude-code/.*/claude\.app/Contents/MacOS/claude'); do
  desktop_oauth=$(ps eww -p "$desktop_pid" | perl -ne 'if (/(?:^| )CLAUDE_CODE_OAUTH_TOKEN=([^ ]+)/) { print $1; exit }')
  [[ -n "$desktop_oauth" ]] && exec env \
    -u ANTHROPIC_AUTH_TOKEN \
    -u ANTHROPIC_API_KEY \
    -u ANTHROPIC_BASE_URL \
    -u ANTHROPIC_MODEL \
    -u ANTHROPIC_DEFAULT_HAIKU_MODEL \
    -u ANTHROPIC_DEFAULT_OPUS_MODEL \
    -u ANTHROPIC_DEFAULT_SONNET_MODEL \
    -u CLAUDE_CODE_USE_BEDROCK \
    -u CLAUDE_CODE_USE_FOUNDRY \
    -u CLAUDE_CODE_USE_VERTEX \
    CLAUDE_CODE_OAUTH_TOKEN="$desktop_oauth" "$claude_bin" "$@"
done

echo 'Không tìm thấy phiên Claude Desktop Code đang chạy. Mở Claude Desktop → Code → Local trước.' >&2
exit 1
WRAPPER
chmod 700 "$wrapper"

config="$HOME/.claude.json"
if [[ -f "$config" ]]; then
  /usr/bin/plutil -replace hasCompletedOnboarding -bool true "$config" 2>/dev/null ||
    /usr/bin/plutil -insert hasCompletedOnboarding -bool true "$config"
else
  printf '{"hasCompletedOnboarding":true}\n' > "$config"
  chmod 600 "$config"
fi

if [[ ":$PATH:" != *":$install_dir:"* ]]; then
  profile="$HOME/.zprofile"
  grep -Fq '# claude-desktop-cli' "$profile" 2>/dev/null ||
    printf '\nexport PATH="$HOME/.local/bin:$PATH" # claude-desktop-cli\n' >> "$profile"
fi

echo "Đã cài: $wrapper"
echo 'Mở Claude Desktop → Code → Local, rồi chạy: claude-desktop'
