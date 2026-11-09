# Lima

An iOS keyboard that tidies up dictation.

**Status:** early development. The keyboard isn't built yet, so this README describes the plan. See the [issues](../../issues) for progress.

Dictate with Apple's mic, tap **Tidy**, and Lima rewrites what you said as the message you meant to send. Tap **Undo** to get what you said back. Tidy uses Apple's on-device model, so your text stays on your iPhone. An optional cloud engine is planned for later. Your text will only leave your iPhone if you turn it on.

> hey can we get coffee at 6 I mean 7 o'clock actually can we make it London Bridge actually maybe no make it Westminster
>
> **Hey, can we get coffee at 7 at Westminster?**

## Requirements

- An iPhone that supports Apple Intelligence (iPhone 15 Pro or newer), with Apple Intelligence and Dictation turned on
- iOS 27.1 or later
- Xcode 27.2 or later

## Run it

1. Open `Lima.xcodeproj` in Xcode.
2. Under **Signing & Capabilities**, choose your team and change the bundle identifier to your own, such as `com.yourname.Lima`. A free Apple account works.
3. Connect your iPhone, pick it as the run destination, and press **⌘R**. For now this opens a placeholder screen.

The first time, your iPhone may ask you to turn on Developer Mode and to trust your developer certificate in **Settings › General › VPN & Device Management**.

With a free Apple account, the app stops working after 7 days. Run it from Xcode again to renew it.

## Working on Lima

[AGENTS.md](AGENTS.md) is the project brief for people and AI agents: the words we use, the architecture, the clean-up rules and the phases.

[Welcome interaction previews](Docs/Previews/README.md) contains GIFs of the Duo handoff and subtle ripple variation, plus verification results and pending device checks.
