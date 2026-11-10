# Changelog

## Unreleased

- Docs: dedicated Linux section (WARP client install, proxy mode, service/desktop entry, log check).
- Docs: npm package and release ZIP links.
- Docs: note that the Windows launcher does not apply on Linux.

## 1.0.0

- Initial release.
- Rotates Cloudflare WARP when OpenCode reports `provider.free-limit`.
- Retries after each rotation, within OpenCode's per-request attempt cap.
- Repeats the rotation when WARP reconnects with the same egress IP.
- Only activates when the OpenCode server has a matching proxy environment.
- Includes a Windows launcher and shortcut installer.
