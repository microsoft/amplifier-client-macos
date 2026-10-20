# Amplifier for Mac

A native Mac client for Amplifier, with quick chat, desktop notifications and
**Tempo**, an optional floating companion that keeps your work within reach.

**Early public preview.** The current app connects to an existing
Amplifier Unified host. Its full workspace opens in your browser or installed
web app. An integrated workspace window and optional device capabilities are
planned, not included in this preview.

## Install

Download `Amplifier-macOS.dmg` from
[Releases](https://github.com/microsoft/amplifier-client-macos/releases).
Official releases are Developer ID signed and Apple notarized. Development
workflow artifacts are for testing and are not qualified public installers.

1. Open the disk image and drag **Amplifier.app** to **Applications**.
2. Open Amplifier. It appears in the menu bar; this preview has no Dock window.
3. In **Settings → Connection**, enter your host's HTTPS address and choose
   **Connect in browser**. Sign in, compare the code and approve this Mac.
4. Enable notifications if you want them. Choose **Hide Tempo** if you prefer
   just the menu bar and notifications.

Requires macOS 13 or later. Universal builds contain Apple silicon and Intel
code. Liquid Glass uses the native macOS 26 treatment, with native material on
older systems. Hardware and interaction qualification is tracked in
[release readiness](docs/release-readiness.md).

Your host must support browser device approval and the companion API. Obtain
its address and access from its owner. The app never installs or updates a
server. Older compatible hosts can use a manual access token under disclosure;
that fallback grants full host authority and should not be shared for setup.
Browser approval provides restricted chat access. See [connection and privacy](docs/connection-and-privacy.md).

## Stay close to your work

- See work and unread updates in the menu bar. Counts represent attention, not
  every active chat. Reading the latest response in a focused chat clears its
  shared unread state on the next poll.
- Reply from a native notification or open **New message…** to start or continue
  a chat. Saved or uncertain messages can be inspected and explicitly retried.
- Show Tempo for movable artwork, compact activity bubbles and quick chat.
  Drag it or the notice stack to reposition it. Double-click the avatar to open
  Amplifier; click a notice to open that chat. Passive interaction preserves the
  current application's keyboard focus.
- Choose among six shapes, eight colors and Clear / Dark finishes. New installs
  use blue Relay with Clear glass. The status pill uses consistent semantic
  colors independently of the artwork.

Notifications default to pinned chats and chats used from this app. Existing
activity establishes a quiet baseline on first connection. You can include all
chats, show ongoing work, or opt into login startup in Settings.

**Check for Updates…** uses the signed public update channel in official builds.
Automatic checks are optional. Quit stops the client; work already accepted by
its host continues. [Uninstall and connection controls](docs/connection-and-privacy.md#disconnect-and-uninstall)
explain what stays on your Mac and how to revoke host access.

## Direction

Amplifier for Mac is growing around three experiences: a full workspace, quick
interaction, and the optional Tempo companion. Native integration belongs to the
Mac client; conversation execution remains with the connected host. Read the
[product vision](docs/VISION.md), [architecture](docs/architecture.md), and
[roadmap](docs/roadmap.md) for the distinction between current behavior and plans.

## Build and contribute

Use Xcode 26.3 or newer with its macOS SDK:

```sh
git clone https://github.com/microsoft/amplifier-client-macos.git
cd amplifier-client-macos
bash build-app.sh
open dist/Amplifier.app
```

The build runs core and native checks, then produces a universal app, ZIP and
DMG under `dist/`. Without distribution configuration it is ad-hoc signed and
has no automatic update feed. See [contributing](CONTRIBUTING.md) and
[release instructions](docs/releasing.md).

This is an experimental preview; see the [support policy](SUPPORT.md).
Do not post host credentials, private chats or personal addresses.
Security concerns follow the [Microsoft security reporting policy](SECURITY.md).

## License and artwork

Source is available under the [MIT license](LICENSE). Official Amplifier app and
menu-bar icons retain their [upstream attribution](Assets/README.md).
[Tempo artwork provenance](Sources/AmplifierApp/Resources/ARTWORK.md) is included.
Sparkle is a separately licensed dependency; its license ships in its framework.

## Contributing

> [!NOTE]
> This project is not currently accepting external contributions, but we're actively working toward opening this up. We value community input and look forward to collaborating in the future. For now, feel free to fork and experiment!

Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
