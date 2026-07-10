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

Paste this in Terminal — it installs the latest release into /Applications and opens it,
skipping the Gatekeeper dance entirely:

```sh
curl -fsSL https://raw.githubusercontent.com/BraisonCrece/susurro/main/install.sh | bash
```

On first launch Susurro opens a setup window that walks you through the two permissions
(Microphone, Accessibility — with live checkmarks and buttons that jump straight to the
right System Settings pane) and your Groq API key (free at https://console.groq.com/keys).

<details>
<summary>Manual install (no Terminal)</summary>

1. Download the latest `Susurro-x.y.z.zip` from
   [Releases](https://github.com/BraisonCrece/susurro/releases/latest), unzip it and drag
   `Susurro.app` into **Applications**.
2. On first open, macOS will warn that it could not verify the app and only offer
   **Done** / **Move to Trash**. Don't trash it! Click **Done**, then go to
   **System Settings › Privacy & Security**, scroll down to the Susurro message and click
   **Open Anyway**. This only happens once — the app is not notarized, since that requires
   Apple's $99/year developer program.

</details>

Updates arrive on their own: the app notifies you when a new version is out and updates
itself without losing permissions. You can also force a check with **Buscar
actualizaciones…** in the menu.

## Usage

1. Hold **right ⌥**.
2. Speak. Correct yourself naturally ("...tomorrow, no wait, Thursday").
3. Release. In ~1 s the clean text appears wherever your cursor is.

Regretted it mid-sentence? Tap **left ⌥** while recording and the dictation is discarded —
the audio never leaves your machine.

## Smart dictation

- **Continues your text.** Susurro reads the ~200 characters before the caret (through
  Accessibility — never password fields) so burst dictations get the leading space and
  capitalization right. Toggleable in settings (`useCursorContext`); when off, nothing but
  the audio leaves your machine.
- **Spoken lists.** "para la compra: uno manzanas, dos plátanos…" comes out as a numbered
  list, keeping your intro line.
- **Dictated punctuation.** "coma", "punto", "question mark"… become the marks themselves.
- **Identifier casing.** "user id en camel case" → `userId`, "max retries en snake case en
  mayúsculas" → `MAX_RETRIES`.
- **Your languages, only yours.** Configure the languages you dictate in, ordered by
  preference (e.g. Spanish, Galician, English). Output only ever comes out in those:
  close-language misdetections — Galician rendered with Portuguese spellings is the
  classic — are normalized automatically, while mixing your languages in one dictation
  is preserved.
- **Personal dictionary.** Your jargon ("Whitebox, Sorbet, Temporal…") biases the
  transcription model itself and the refiner enforces the exact spelling. Edit it in
  settings.
- **Technical mode.** When the frontmost app is a terminal or code editor (`technicalApps`
  in the config, sensible defaults included), dictated commands come out verbatim: "git
  commit guión guión amend" → `git commit --amend`.
- **Silence never types.** Too-short, too-quiet or speech-free recordings are discarded
  before reaching the API, so silence hallucinations ("You're welcome") are gone.

## Configuration

Open **Configuración…** from the menu bar icon (or ⌘,) to set your API key, the language
and the models. Everything lives in `~/.config/susurro/config.json` (created on first
launch), which you can also edit by hand — restart the app to pick up changes:

```json
{
  "groqApiKey": "gsk_...",
  "transcriptionModel": "whisper-large-v3-turbo",
  "cleanupModel": "llama-3.3-70b-versatile",
  "languages": ["es", "gl", "en"]
}
```

Optional keys: `systemPrompt` to customize the cleanup rules (JSON only), `languages` (ISO
codes in order of preference; empty = pure auto-detection; the legacy `language` key is
still read), `dictionary` (array of terms for the personal dictionary), `useCursorContext`
(default `true`), and `technicalApps` (array of bundle IDs that trigger technical mode).
The `GROQ_API_KEY` environment variable is also honored.

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
