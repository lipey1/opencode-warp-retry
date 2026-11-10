# Publishing

This repository is ready to publish as an npm package and install through GitHub.

## 1. Create the GitHub repository

Create a new empty repository named **`opencode-warp-retry`** under your account
(`lipey1` is already referenced in `package.json`; change it if your username is
different).

Do **not** initialize it with a README, `.gitignore`, or license — this folder
already has them.

## 2. Push the files

With Git installed (`winget install Git.Git`), from this repository folder:

```sh
git init
git add .
git commit -m "Initial release"
git branch -M main
git remote add origin https://github.com/lipey1/opencode-warp-retry.git
git push -u origin main
```

Without Git, create the repository on GitHub and use **Add file > Upload files**
to upload the folder contents (keep the directory structure).

## 3. Test the GitHub install

```sh
opencode plugin add github:lipey1/opencode-warp-retry
```

Then launch OpenCode with the WARP proxy and check the log:

- Windows: `%LOCALAPPDATA%\opencode-warp-retry\warp-retry.log`
- macOS/Linux: `~/.local/share/opencode-warp-retry/warp-retry.log`

You should see:

```text
plugin loaded; automatic free-limit retry enabled (proxy: http://127.0.0.1:40000)
```

## 4. Publish to npm

The name `opencode-warp-retry` is available on npm (checked on 2026-11-09).

```sh
npm login
npm publish --access public
```

After publishing:

```sh
opencode plugin add opencode-warp-retry
```

## 5. Update the version

For every change:

```sh
npm version patch   # or minor / major
git push --follow-tags
npm publish --access public
```

## 6. Prepare a release (optional)

On GitHub, create a release from the pushed tag and paste the relevant
`CHANGELOG.md` section.

## Notes

- `src/index.ts` is shipped as-is; there is no build step.
- `@opencode/plugin` is listed as a dependency and is provided by the OpenCode
  runtime.
- Keep `README.md`, `README.pt-BR.md`, `package.json`, and `CHANGELOG.md` in sync
  when you change behavior or options.
