# CodexQuota

A small macOS floating panel that shows remaining Codex 5-hour and weekly usage in the bottom-right corner.

## Run

1. Build with Xcode Command Line Tools: `./build.sh`
2. Open `dist/CodexQuota.app`.

The app reads the existing OAuth access token from `~/.codex/auth.json` locally and makes a read-only request to `https://chatgpt.com/backend-api/wham/usage` at launch or when you press refresh. It does not poll in the background. This request reads quota metadata and does not generate model output or consume Codex model usage. Credentials are never copied into this repository or logged. The endpoint is undocumented and can change. If an account only reports a weekly window, the app shows only that available window.

## Notes

- macOS 13 or newer; SwiftUI and AppKit.
- The panel stays above other windows and appears on all Spaces.
- Drag the grip beside the title to reposition the panel. Use the palette button to set the background and accent colors, opacity, corner radius, and an imported image skin; “Save and overwrite current skin” persists the selection across launches. Imported images stay in local Application Support storage.
- The panel shows this app's resident memory use, sampled locally every two seconds. This does not poll the Codex quota endpoint.
- No analytics, telemetry, or third-party dependencies.
- The panel is local to the active display and currently has no settings screen.

## License

MIT. See [LICENSE](LICENSE).
