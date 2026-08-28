# Dùng phiên Claude Desktop cho Claude Code CLI trên macOS

> Cách không chính thức, có thể hỏng sau khi Claude Desktop hoặc Claude Code cập nhật. Không dùng trên máy không tin cậy.

## Cơ chế

Claude Desktop truyền biến `CLAUDE_CODE_OAUTH_TOKEN` cho tiến trình Claude Code mà tab **Code → Local** khởi chạy. Script cài lệnh `claude-desktop`; mỗi lần chạy, lệnh này:

1. Tìm tiến trình Claude Code con của Claude Desktop.
2. Đọc OAuth token từ environment của tiến trình đó.
3. Xóa các biến API key, gateway, cloud provider và model override có thể thắng OAuth theo auth precedence.
4. Truyền token trực tiếp trong RAM cho Claude Code CLI.
5. Không in hoặc ghi token xuống file/Keychain.

Installer cũng đặt `hasCompletedOnboarding=true` trong `~/.claude.json`. Nếu cờ này là `false`, CLI sẽ mở OAuth browser dù đã nhận token từ Desktop.

## Yêu cầu

- macOS.
- Claude Desktop đã đăng nhập.
- Claude Code CLI đã cài và có lệnh `claude`.
- Một phiên **Claude Desktop → Code → Local** đang chạy.

## Cài một lần

```bash
chmod +x claude-desktop-cli/install.sh
./claude-desktop-cli/install.sh
source ~/.zprofile
```

Kiểm tra:

```bash
claude-desktop auth status
```

Kết quả mong đợi:

```json
{
  "loggedIn": true,
  "authMethod": "oauth_token",
  "apiProvider": "firstParty"
}
```

Mở Claude Code:

```bash
claude-desktop
```

Trong Claude Code, `/status` phải hiển thị:

```text
Session kind: interactive
Auth token: CLAUDE_CODE_OAUTH_TOKEN
```

## Session có tự giữ không?

Không lưu session đăng nhập cho CLI. `claude auth status` chạy trực tiếp vẫn có thể báo `false`.

`claude-desktop` tự đọc token hiện tại mỗi lần khởi động, nên thường không cần setup lại khi:

- Claude Desktop vẫn đăng nhập;
- có ít nhất một Local Code session đang chạy.

Phải mở lại Local Code session và chạy lại `claude-desktop` khi Desktop bị thoát, tiến trình Code bị đóng, hoặc token hiện tại hết hạn. Một CLI đang chạy không tự nhận token mới sau khi Desktop refresh; nếu gặp `401` hoặc yêu cầu `/login`, thoát CLI rồi chạy lại `claude-desktop`.

Chạy `claude auth logout` có thể đặt lại `hasCompletedOnboarding=false`. Khi đó chạy lại installer.

## Rủi ro và giới hạn

- Token OAuth xuất hiện trong environment của tiến trình CLI, giống cách Desktop truyền nó cho tiến trình con. Tiến trình khác chạy cùng macOS user có thể đọc environment này.
- Wrapper lấy token từ Local Code process đầu tiên tìm thấy. Không nên dùng nếu cùng macOS user chạy nhiều tài khoản Claude đồng thời.
- Đây không phải luồng đăng nhập được Anthropic hỗ trợ. Luồng chính thức vẫn là `claude auth login` qua browser.
- Wrapper buộc dùng Anthropic first-party OAuth; không dùng nó nếu bạn muốn Bedrock, Vertex, Foundry hoặc gateway/API model tùy chỉnh.
- Không đặt token vào `.zshrc`, shell history, log hoặc file cấu hình.

Tài liệu chính thức: [Claude Code authentication](https://code.claude.com/docs/en/authentication). Bằng chứng Desktop chạy Claude Code con với credential riêng: [anthropics/claude-code#72862](https://github.com/anthropics/claude-code/issues/72862).

## Gỡ cài đặt

```bash
rm ~/.local/bin/claude-desktop
```

Nếu installer từng thêm PATH, xóa dòng có `# claude-desktop-cli` khỏi `~/.zprofile`.
