# Susurro

Dictado inteligente para macOS, estilo Wispr Flow / SuperWhisper, con todo el procesamiento
en la nube vía Groq. App de menu bar nativa, sin cómputo local.

**Flujo:** mantienes ⌥ (Option derecho) y hablas → al soltar, el audio va a Groq Whisper
(`whisper-large-v3-turbo`) → el transcript crudo pasa a un LLM rápido
(`llama-3.3-70b-versatile`) que elimina muletillas, resuelve autocorrecciones y puntúa → el
texto limpio se pega solo en la app que tengas enfocada y se restaura tu portapapeles.

## Requisitos

- macOS 13+
- Toolchain de Swift (Xcode o Command Line Tools)
- Una API key de Groq: https://console.groq.com/keys

## Build

```sh
./build-app.sh          # compila y genera Susurro.app
open Susurro.app        # o cópialo a /Applications
```

Para iterar durante el desarrollo puedes compilar sin empaquetar con `swift build`, pero el
**micrófono solo funciona desde el `.app`** (macOS exige el `NSMicrophoneUsageDescription`
del bundle).

## Configuración

Al primer arranque se crea `~/.config/susurro/config.json`. Pon tu clave ahí:

```json
{
  "groqApiKey": "gsk_...",
  "transcriptionModel": "whisper-large-v3-turbo",
  "cleanupModel": "llama-3.3-70b-versatile",
  "language": "es"
}
```

Luego usa **Recargar configuración** en el menú. Opcional: `systemPrompt` para personalizar
las reglas de limpieza, y `language` (código ISO, p. ej. `es` / `en`) para fijar el idioma de
la transcripción. También se acepta la variable de entorno `GROQ_API_KEY`.

## Permisos

macOS pedirá dos permisos la primera vez (Ajustes del Sistema › Privacidad y seguridad):

- **Micrófono** — para grabar.
- **Accesibilidad** — para monitorizar la tecla global y simular ⌘V.

Si tras concederlos sigue sin funcionar, quita y vuelve a añadir Susurro en la lista de
Accesibilidad (TCC a veces cachea el grant del binario anterior).

## Uso

1. Mantén pulsado **⌥ derecho**.
2. Habla. Corrígete con naturalidad ("...mañana, no, el jueves").
3. Suelta. En ~1 s el texto limpio aparece donde tengas el cursor.

## Personalizar la tecla

El trigger está en `Sources/Susurro/HotkeyManager.swift` (`triggerKeyCode = 61`, Option
derecho). Otros keycodes útiles: Command derecho `54`, Control derecho `62`, Shift derecho
`60`. Usa una tecla **modificadora** para que el trigger no escriba caracteres en la app.
