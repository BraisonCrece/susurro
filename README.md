# Susurro

Dictado inteligente para macOS, estilo Wispr Flow / SuperWhisper, con todo el procesamiento
en la nube vía Groq. App de menu bar nativa, sin cómputo local.

**Flujo:** mantienes ⌥ (Option derecho) y hablas → al soltar, el audio va a Groq Whisper
(`whisper-large-v3-turbo`) → el transcript crudo pasa a un LLM rápido
(`llama-3.3-70b-versatile`) que elimina muletillas, resuelve autocorrecciones y puntúa → el
texto limpio se pega solo en la app que tengas enfocada y se restaura tu portapapeles.

## Instalación

1. Baja el último `Susurro-x.y.z.zip` desde
   [Releases](https://github.com/BraisonCrece/susurro/releases/latest) y descomprímelo.
2. Arrastra `Susurro.app` a **Aplicaciones** y ábrela.
3. La primera vez macOS dirá que no puede verificar la app (no está notarizada). Cierra el
   aviso y ve a **Ajustes del Sistema › Privacidad y seguridad**, baja hasta el mensaje
   sobre Susurro y pulsa **Abrir igualmente**. Solo pasa una vez.
4. Concede los dos permisos que pide: **Micrófono** y **Accesibilidad**.
5. Pon tu API key de Groq (gratis en https://console.groq.com/keys) en la ventana de
   configuración que se abre desde el icono de la barra de menús.

Las actualizaciones llegan solas: la app avisa cuando hay una versión nueva y se actualiza
sin perder los permisos. También puedes forzarlo con **Buscar actualizaciones…** en el menú.

## Uso

1. Mantén pulsado **⌥ derecho**.
2. Habla. Corrígete con naturalidad ("...mañana, no, el jueves").
3. Suelta. En ~1 s el texto limpio aparece donde tengas el cursor.

## Configuración

Abre **Configuración…** desde el icono de la barra de menús (o ⌘,) para poner tu API key,
el idioma y los modelos. Todo vive en `~/.config/susurro/config.json` (se crea al primer
arranque), que también puedes editar a mano — reinicia la app para que recoja los cambios:

```json
{
  "groqApiKey": "gsk_...",
  "transcriptionModel": "whisper-large-v3-turbo",
  "cleanupModel": "llama-3.3-70b-versatile",
  "language": "es"
}
```

Opcional: `systemPrompt` para personalizar las reglas de limpieza (solo editable en el
JSON), y `language` (código ISO, p. ej. `es` / `en`) para fijar el idioma de la
transcripción. También se acepta la variable de entorno `GROQ_API_KEY`.

## Permisos

- **Micrófono** — para grabar.
- **Accesibilidad** — para monitorizar la tecla global y simular ⌘V.

Si tras concederlos sigue sin funcionar, quita y vuelve a añadir Susurro en la lista de
Accesibilidad (TCC a veces cachea el grant de una versión anterior).

## Desarrollo

Requisitos: macOS 13+, toolchain de Swift (Xcode o Command Line Tools).

```sh
./build-app.sh                    # compila, empaqueta y firma Susurro.app
./build-app.sh --install          # además lo copia a /Applications
open Susurro.app
```

Para iterar puedes compilar sin empaquetar con `swift build`, pero el **micrófono solo
funciona desde el `.app`** (macOS exige el `NSMicrophoneUsageDescription` del bundle) y
Sparkle solo arranca dentro del bundle.

El script firma con la identidad self-signed **"Susurro"** del llavero si existe (estable →
los permisos TCC sobreviven a los rebuilds); si no, firma ad-hoc.

### Personalizar la tecla

El trigger está en `Sources/Susurro/HotkeyManager.swift` (`triggerKeyCode = 61`, Option
derecho). Otros keycodes útiles: Command derecho `54`, Control derecho `62`, Shift derecho
`60`. Usa una tecla **modificadora** para que el trigger no escriba caracteres en la app.

### Publicar una versión

```sh
git tag v1.0.1 && git push origin v1.0.1
```

GitHub Actions ([release.yml](.github/workflows/release.yml)) compila, firma con el
certificado "Susurro", genera el `appcast.xml` de Sparkle y publica la release con el zip.
Secrets necesarios en el repo: `SIGNING_CERT_P12_BASE64`, `SIGNING_CERT_PASSWORD`,
`KEYCHAIN_PASSWORD` y `SPARKLE_PRIVATE_KEY`.
