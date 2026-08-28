# Agent Usage

Menu bar app cho macOS, hiển thị quota còn lại của các AI coding agent đang đăng nhập trên máy — giống popup usage của Claude Desktop, nhưng gộp mọi agent vào một chỗ.

<!-- Mỗi agent một section: 5-hour limit và weekly limit, kèm % và thời điểm reset. -->

## Agent hỗ trợ

| Agent | Credential đọc từ | Nguồn số liệu |
|---|---|---|
| Claude Code | Keychain `Claude Code-credentials` (OAuth do CLI ghi) | `GET api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` (`auth_mode: chatgpt`) | `GET chatgpt.com/backend-api/wham/usage` |
| Z.AI / GLM | `$GLM_API_KEY`, `$ANTHROPIC_AUTH_TOKEN`, `$ZAI_API_KEY`, hoặc `~/.zshrc` | `GET api.z.ai/api/monitor/usage/quota/limit` |
| Grok / xAI | OAuth do [`omp`](https://omp.sh) quản lý | `omp usage --json --provider xai-oauth` |

Agent nào không đăng nhập thì section tự ẩn — app không hiện số giả.

## Cài

```sh
./scripts/build-app.sh --install
```

Build release, dựng `dist/Agent Usage.app`, copy vào `/Applications` rồi mở. Bỏ `--install` nếu chỉ muốn build.

Mở popup → **Open at Login** để app tự chạy khi đăng nhập macOS (đăng ký qua `SMAppService`, xem/tắt được ở System Settings → General → Login Items).

Chạy kiểu dev: `swift run`. Lúc đó không có bundle identifier nên dòng Open at Login và notification đều tắt.

## Hành vi

- **Refresh 60 giây/lần** ở nền. Không hạ thấp hơn được: endpoint usage của Anthropic trả **HTTP 429** khi poll dày hơn.
- **Mở popup không gọi API** — bar chạy animation trên dữ liệu đã có sẵn. Nút **Refresh** mới ép gọi lại.
- Fetch lỗi (429, mất mạng, token hết hạn) thì **giữ nguyên số cũ** trên màn hình thay vì để section biến mất.
- **Cảnh báo ở 80% và 95%**: bar chuyển cam rồi đỏ, icon menu bar đổi màu theo, và gửi notification **một lần** mỗi mốc cho tới khi cửa sổ quota đó reset.

## Yêu cầu

- macOS 14+
- Agent nào muốn theo dõi thì đăng nhập agent đó (`claude`, `codex`, `omp`)
- Grok cần `bun` trong PATH vì `omp` là script shebang

## Ghi chú

**Keychain hỏi lại sau mỗi lần build.** App ký ad-hoc, chữ ký đổi theo từng bản build nên macOS coi đó là app khác và hỏi lại quyền đọc credential của Claude Code. Bấm **Always Allow** một lần cho mỗi bản build.

**Nhiều tài khoản Codex.** Copy `~/.codex/auth.json` thành `~/.codex/auth.<tên>.json`; app quét mọi file `auth*.json` và tạo section riêng cho từng cái, nhãn lấy từ email trong `id_token`. Lưu ý token ở bản copy không tự refresh nên vài ngày phải copy lại.

**Không hỗ trợ Gemini.** `GEMINI_API_KEY` là API key tính tiền theo token, không có cửa sổ quota 5h/tuần để hiển thị. Quota của nó nằm ở Google Cloud Console, không cùng dạng dữ liệu.

App chỉ đọc credential để gọi API, không ghi log và không gửi đi đâu khác.

## Cấu trúc

```
Sources/UsageCore/          # 4 reader + model + ngưỡng severity (có test)
Sources/AIProviderMenuBar/  # SwiftUI menu bar, icon, notification, login item
Tests/UsageCoreTests/       # test parser trên JSON mẫu thật
scripts/build-app.sh        # dựng .app
```

```sh
swift test
```

`claude-desktop-cli/` là tool riêng biệt trong repo này, không liên quan tới app trên.
