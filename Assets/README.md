# Official app icon

`Amplifier.icns` is copied unchanged from
[microsoft/amplifier assets/branding/icons](https://github.com/microsoft/amplifier/blob/33b75749920472257d1d85d20a5699ecf9d1ece7/assets/branding/icons/Amplifier.icns).
Source revision: `33b75749920472257d1d85d20a5699ecf9d1ece7`.
Git blob: `384532560959429dceff542c43ed87fec438b146`.

This is the official multi-resolution macOS icon (16–1024 pixels). The build
preserves it in `Contents/Resources` and decodes all ten representations into a
temporary app icon set. Apple's `actool` compiles `Assets.car` and `AppIcon.icns`
into the main bundle, with its generated `CFBundleIconName` / `CFBundleIconFile`
declarations merged before signing. No runtime download or replacement artwork
is used. Temporary icon sets are removed after compilation.

Acceptance includes a fresh delivered notification and the updater dialog from
the packaged app; resolving an icon by its file path does not verify those system
surfaces.

Menu-bar template assets already match this upstream directory byte-for-byte;
they stay in the SwiftPM resource bundle for explicit template-image loading.
The desktop avatar remains the user's separately selected appearance.
