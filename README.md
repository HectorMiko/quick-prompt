# quick-prompt

A macOS menu bar app that runs Claude prompts on the text you select.

- **Double ⌘C**: runs your quick action (by default, a spelling and grammar fix) and pastes the result over the selection.
- **⌃⌥⌘E**: opens a palette with all your prompts. The result is copied to the clipboard.
- **Settings**: add and edit prompts, pick the model and effort per prompt, and use either an Anthropic API key or your Claude Pro/Max subscription (through Claude Code).

## Install

Requirements: macOS 14 or later, Xcode 16 or later, [Homebrew](https://brew.sh).

```sh
brew install xcodegen
git clone https://github.com/HectorMiko/quick-prompt.git
cd quick-prompt
make install
```

The app is built and copied to `~/Applications/quick-prompt.app`, then launched.

## First launch

1. Allow quick-prompt in **System Settings > Privacy & Security**:
   - **Accessibility** (read the selection and paste),
   - **Input Monitoring** (double ⌘C).
2. Open **Settings… > Backend** from the menu bar icon and either paste an Anthropic API key or check that Claude Code is found.

## Optional: keep permissions across rebuilds

Without a signing identity, macOS asks for the permissions again after each `make install`. To avoid it, sign with your Apple Development certificate:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
# then set DEVELOPMENT_TEAM to your Team ID in Config/Local.xcconfig
```
