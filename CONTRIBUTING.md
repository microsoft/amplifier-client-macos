# Contributing

Start with the [vision](docs/VISION.md), [architecture](docs/architecture.md) and
[interaction contract](docs/ux-contract.md). Keep current behavior and proposed
capabilities distinct in changes and release notes.

Use Xcode 26.3 or newer, then run `bash build-app.sh`. For release-tooling changes,
run `python3 -m unittest discover -s scripts -p 'test_*.py'`. The native checks run
without needing a live Amplifier account. Changes to transport or recovery need
meaningful failure-path coverage, not only a successful response.

Use synthetic state and an isolated host for integration work. Do not change a
shared or live host to validate a client patch. Native interaction changes need
real Mac acceptance; document the source, OS/hardware and limitations.

Do not commit credentials, private configuration, chat history, build output or
personal screenshots. Keep third-party licenses and artwork attribution intact.
External contributions are not currently accepted, as explained in the canonical
Contributing section of the README. Maintainers use focused pull requests that
describe behavior, motivation and validation. Repository-owner policies and
templates also apply.
