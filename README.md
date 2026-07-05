# Susurro

Smart dictation for macOS, in the spirit of Wispr Flow / SuperWhisper, with all the
processing in the cloud via Groq. Native menu bar app, no local compute.

**Flow:** hold ⌥ (right Option) and speak → on release, the audio goes to Groq Whisper
(`whisper-large-v3-turbo`) → the raw transcript goes through a fast LLM
(`llama-3.3-70b-versatile`) that removes filler words, applies self-corrections and fixes
punctuation → the clean text is pasted wherever your cursor is, and your clipboard is
restored.

The app UI is currently Spanish-only.

## Install

1. Download the latest `Susurro-x.y.z.zip` from
   [Releases](https://github.com/BraisonCrece/susurro/releases/latest) and unzip it.
2. Drag `Susurro.app` into **Applications** and open it.
3. The first time, macOS will warn that it could not verify the app and only offer
   **Done** / **Move to Trash**. Don't trash it! Click **Done**, then go to
   **System Settings › Privacy & Security**, scroll down to the Susurro message and click
   **Open Anyway**. This only happens once — the app is not notarized, since that requires
   Apple's $99/year developer program.

   If no "Open Anyway" button shows up, run this one-liner in Terminal instead:

   ```sh
   xattr -rd com.apple.quarantine /Applications/Susurro.app
   ```

4. Grant the two permissions it asks for: **Microphone** and **Accessibility**.
5. Set your Groq API key (free at https://console.groq.com/keys) in the settings window,
   reachable from the menu bar icon.

Updates arrive on their own: the app notifies you when a new version is out and updates
itself without losing permissions. You can also force a check with **Buscar
actualizaciones…** in the menu.

## Usage

1. Hold **right ⌥**.
2. Speak. Correct yourself naturally ("...tomorrow, no wait, Thursday").
3. Release. In ~1 s the clean text appears wherever your cursor is.

## Configuration

Open **Configuración…** from the menu bar icon (or ⌘,) to set your API key, the language
and the models. Everything lives in `~/.config/susurro/config.json` (created on first
launch), which you can also edit by hand — restart the app to pick up changes:

```json
{
  "groqApiKey": "gsk_...",
  "transcriptionModel": "whisper-large-v3-turbo",
  "cleanupModel": "llama-3.3-70b-versatile",
  "language": "es"
}
```

Optional: `systemPrompt` to customize the cleanup rules (only editable in the JSON), and
`language` (ISO code, e.g. `es` / `en`) to pin the transcription language. The
`GROQ_API_KEY` environment variable is also honored.

## Permissions

- **Microphone** — to record.
- **Accessibility** — to monitor the global key and synthesize ⌘V.

If it still doesn't work after granting them, remove and re-add Susurro in the
Accessibility list (TCC sometimes caches the grant of a previous version).

## Development

Requirements: macOS 13+, a Swift toolchain (Xcode or Command Line Tools).

```sh
./build-app.sh                    # builds, bundles and signs Susurro.app
./build-app.sh --install          # additionally copies it to /Applications
open Susurro.app
```

For quick iteration you can build without bundling using `swift build`, but the
**microphone only works from the `.app`** (macOS requires the bundle's
`NSMicrophoneUsageDescription`) and Sparkle only starts inside the bundle.

The script signs with the self-signed **"Susurro"** keychain identity when present
(stable → TCC grants survive rebuilds); otherwise it falls back to ad-hoc signing.

### Customizing the trigger key

The trigger lives in `Sources/Susurro/HotkeyManager.swift` (`triggerKeyCode = 61`, right
Option). Other useful keycodes: right Command `54`, right Control `62`, right Shift `60`.
Use a **modifier** key so the trigger never types characters into the focused app.

### Publishing a release

```sh
git tag v1.0.1 && git push origin v1.0.1
```

GitHub Actions ([release.yml](.github/workflows/release.yml)) builds a universal binary,
signs it with the "Susurro" certificate, generates Sparkle's `appcast.xml` and publishes
the release with the zip. Required repo secrets: `SIGNING_CERT_P12_BASE64`,
`SIGNING_CERT_PASSWORD`, `KEYCHAIN_PASSWORD` and `SPARKLE_PRIVATE_KEY`.
