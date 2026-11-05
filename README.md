# Lima

An iOS keyboard that tidies up dictation.

**Status:** early development. The keyboard isn't built yet. This README describes the plan. See the [issues](../../issues) for progress.

Dictate with Apple's mic, tap **Tidy**, and Lima rewrites what you said as the message you meant to send. Tap **Undo** to get the original back. Tidy uses Apple's on-device model, so Lima doesn't send your text anywhere.

> hey can we get coffee at 6 I mean 7 o'clock actually can we make it London Bridge actually maybe no make it Westminster
>
> **Hey, can we get coffee at 7 at Westminster?**

## Requirements

- An iPhone that supports Apple Intelligence, with Apple Intelligence and Dictation turned on
- iOS 27.1 or later
- Xcode 27.1 or later

## Run it

1. Open `Lima.xcodeproj` in Xcode.
2. Under **Signing & Capabilities**, choose your team and change the bundle identifier to your own, such as `com.yourname.Lima`.
3. Pick your iPhone and press **⌘R**. For now this opens a placeholder screen.

With a free Apple account, the build stops working after 7 days. Run it again from Xcode to renew it.
