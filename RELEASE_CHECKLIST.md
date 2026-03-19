# Release Checklist

Use this before publishing `handoff.yazi` to GitHub.

## Repo Readiness

- Confirm the repository name is final
- Confirm the public plugin name should remain `handoff.yazi`
- Make sure the README matches the current behavior exactly
- Decide whether any compatibility shims should remain public

## Local Verification

- Test `\c` with files and folders
- Test `\z` with files, folders, and mixed selections
- Test `\s` with both AirDrop and non-AirDrop targets
- Test `\r` against a real SSH host
- Test `\oo` with `fzf`
- Test that successful remote sync copies the expected remote path

## Docs

- Add at least one screenshot or GIF
- Mention macOS scope clearly
- Mention `fzf`, `swift`, and `rsync` as real dependencies
- Keep the exact `keymap.toml` snippet in the README

## Publish Hygiene

- Check for hard-coded personal paths
- Check for leftover debug files or local editor files
- Check that `LICENSE` is present
- Check that README links still work after publishing

## Nice-to-Have Before First Release

- Add a short demo GIF for `Remote Sync`
- Add a short demo GIF for `Share`
- Add a short roadmap section
