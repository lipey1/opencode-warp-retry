# Changelog

## 1.0.0

- Initial release.
- Rotates Cloudflare WARP when OpenCode reports `provider.free-limit`.
- Retries after each rotation, within OpenCode's per-request attempt cap.
- Repeats the rotation when WARP reconnects with the same egress IP.
- Only activates when the OpenCode server has a matching proxy environment.
- Includes a Windows launcher and shortcut installer.
