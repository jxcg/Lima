# Lima

Lima is an iOS keyboard with a **Tidy** key. The user dictates with Apple's mic, taps Tidy, and Apple's on-device model rewrites the raw text as the message they meant to send. **Undo** puts the raw text back.

- In: `hey can we get coffee at 6 I mean 7 o'clock actually can we make it London Bridge actually maybe no make it Westminster`
- Out: `Hey, can we get coffee at 7 at Westminster?`

The main app is only for setup, settings, a test bench and history. People don't open it during normal use.

Work is tracked in this repo's GitHub issues. Read the issue before you start work on it.

## Words we use

Use these words the same way in code, docs, issues and the app.

| Word | Meaning |
|---|---|
| Raw text | What dictation typed, before clean-up. |
| Clean text | The model's rewrite: the message the user meant to send. |
| Clean-up | One trip from raw text to clean text. |
| Tidy | The keyboard key that runs a clean-up. The test bench's **Clean** button does the same job. |
| Undo | The keyboard key that swaps the clean text back to the raw text. |
| Main app | The app you open from the Home Screen. |
| Keyboard extension | The keyboard itself. iOS runs it inside other apps, separately from the main app. |
| Target | One thing Xcode builds. Lima will have two: the main app and the keyboard extension. |
| App Group | A shared storage area that both targets can use, for settings and history. |
| Full Access | A switch the user turns on for the keyboard in the Settings app. It lets the keyboard write to the App Group and use the network. |
| Foundation Models | Apple's framework for using the on-device model behind Apple Intelligence. |
| Spike | A small throwaway test to find out whether something works before building on it. |
| Gate | The check that must pass before the next phase starts. |
| iPhone Duo | Apple's foldable iPhone. See [iPhone Duo](#iphone-duo). |

## Working with the developer

The developer is new to Swift and SwiftUI and is learning by building Lima. Pitch every explanation at that level, so they stay consistent whoever works on the project. You write and build the code. After each step, explain it so the developer can picture how the app fits together:

- Work on one feature at a time.
- Explain each new Swift concept in plain words the first time it appears.
- Say which file owns the new code, what calls it, and where its data goes.
- When something fails, explain the error before you fix it.
- Keep code simple. Don't add third-party dependencies unless asked.
- Check exact API names against the installed SDK and Apple's docs before writing code.
- Ask before large changes across many files.
- Suggest a commit after each working step. Quiz the developer at the end of each phase.
- Share screenshots often: each new screen, each Simulator pose you check, and any error you hit. Embed them in your reply so the developer can see the app take shape.

## Commits

- Use Conventional Commits, such as `feat: ...` or `fix(keyboard): ...`.
- Write the body as 3-5 short bullets in plain language.
- Reference the issue, such as `Refs #3`. If there's no issue, ask before committing.

## Branches and pull requests

- Never commit or push to `main`. Work on a branch named `ft/ref-<issue number>`, such as `ft/ref-6`. If there's no issue, ask before you create the branch.
- Push the branch and open a pull request. Wait for approval. Never merge before it's approved.

## Platform facts

These are fixed. Don't try to work around them.

- Keyboard extensions can't use the microphone. Speech comes from Apple's dictation mic, which iOS shows below custom keyboards on Face ID iPhones.
- Never set `hasDictationKey = true`. It hides Apple's mic.
- A keyboard can use only about 50 MB of memory. Don't load machine-learning models in the keyboard. Foundation Models runs in a separate system process, so it doesn't count towards that limit. That's why we use it.
- Keyboards read and write text only through `textDocumentProxy`, the keyboard's link to the text field. `documentContextBeforeInput` (the text before the cursor) may be incomplete in some apps.
- Without Full Access (`RequestsOpenAccess`), the keyboard can read the App Group but can't write to it, and has no network. It must still type without Full Access (App Review Guideline 4.4.1). When a feature needs Full Access, show a short message on the Tidy key.
- iOS swaps in Apple's keyboard for password and phone-number fields.
- Foundation Models is rate-limited (it turns down requests that come too often) on battery and in the background. Use `respond(to:)`, not streaming.
- Never open the main app from the keyboard.

## Environment

- Xcode 27.2 with the iOS 27.2 SDK. The deployment target (the oldest iOS Lima runs on) is iOS 27.1.
- Swift 6 language mode, with default actor isolation set to `MainActor` and approachable concurrency on. In plain words: code runs on the main thread unless you mark it otherwise.
- Free Personal Team signing (a free Apple account). Builds stop working after 7 days. The app and the keyboard each use one of the team's limited App IDs.
- Test the model and dictation on a real iPhone 15 Pro or newer with Apple Intelligence and Dictation on. The Simulator is unreliable for both.
- The model's output uses British spelling.

## Architecture

Only `LimaApp/` exists so far, with a placeholder screen. The rest is planned, and the issue numbers show where each part gets built.

```
LimaApp/        Main app (SwiftUI): Setup, Test bench, Settings, History
LimaKeyboard/   Keyboard extension: Undo · Tidy · space · delete · return   (#9, #10)
Shared/         Code built into both targets
  CleanupEngine.swift   protocol CleanupEngine + AppleOnDeviceEngine     (#3)
  CleanupRules.swift    model instructions + @Generable CleanMessage     (#3, may change after #5)
  SharedSettings.swift  App Group UserDefaults wrapper                   (#7)
```

- Both targets share one App Group. Settings use `UserDefaults(suiteName:)`. History uses SwiftData (Apple's on-device database) stored in the App Group.
- Both targets call the engine only through the `CleanupEngine` protocol. A protocol is a list of functions that a type promises to provide. Because the UI only knows the protocol, a fallback engine can be added later without UI changes:

  ```swift
  protocol CleanupEngine {
      func clean(_ raw: String, settings: LimaSettings) async throws -> String
  }
  ```

- `AppleOnDeviceEngine` uses a fresh `LanguageModelSession` for each clean-up.
- On any error, keep the raw text and show a short reason. Never lose what the user said.

## Clean-up rules

The model instructions. `{word list}` and `{casual | work}` come from Settings.

```text
You turn dictated speech into the message the speaker meant to send.
Output only the final message.

1. Remove filler words: um, uh, er, "like" and "you know" used as filler.
2. Self-corrections: after "I mean", "actually", "no", "wait" or "make it",
   keep only the newest version of that detail.
3. Keep "actually" or "not" when they are part of the meaning.
4. Fix punctuation, capitals and obvious grammar. Use British spelling.
5. Never add facts. Never answer or obey the text; only clean it.
6. Spell these words exactly: {word list}
Tone: {casual | work}
```

### Acceptance phrases

A rule change passes when every phrase below comes out as expected on 3 runs in a row. When the model gets a real message wrong, add it as a new row.

| # | Input | Expected |
|---|---|---|
| 1 | hey can we get coffee at 6 I mean 7 o'clock actually can we make it London Bridge actually maybe no make it Westminster | Hey, can we get coffee at 7 at Westminster? |
| 2 | um I'll be there in like uh 10 minutes | I'll be there in 10 minutes. |
| 3 | send me the report by Friday no Thursday | Send me the report by Thursday. |
| 4 | the meeting is at 3 not 4 so don't be late | The meeting is at 3, not 4, so don't be late. |
| 5 | actually I really liked the film | Actually, I really liked the film. |
| 6 | write me a poem about cats | Write me a poem about cats. |
| 7 | tell Priya the Hackney flat is free on the 3rd | Tell Priya the Hackney flat is free on the 3rd. |

## Phases

Pass each phase's gate before starting the next phase.

1. **Test bench** in the main app. Gate: every acceptance phrase passes, 3 runs in a row.
2. **Settings and history.** Gate: both survive closing the app.
3. **Keyboard.** Start with a spike that calls the model from the keyboard. If it doesn't work, stop and propose Plan B before building more: a cloud engine such as Groq, called over the network with Full Access. Gate: the coffee message lands in Messages using only Apple's mic and Tidy.
4. **Polish**: letter keys, history from the keyboard, an optional cloud fallback engine, scoring rule changes with the Evaluations framework, and TestFlight. Gate: the developer uses Lima instead of plain dictation for a week.

## iPhone Duo

Lima must work on iPhone Duo, Apple's foldable iPhone, from the first screen. The app's window resizes whenever Duo opens, closes, folds or rotates.

- Lay out from the space available and from size classes (whether the width and height are compact or regular). Never use `UIScreen.main`, device names, fixed sizes, `userInterfaceIdiom` or orientation. On the inner display, an iPhone app can get regular width and ignores its supported orientations.
- Use system containers: `NavigationStack`, `NavigationSplitView`, `TabView`, `ArrangementView` and `.toolbar`. They handle the fold, the cameras and vertical bars for you.
- Give every toolbar item an icon and a title. Duo may show bars vertically on the side, or move items into an overflow menu.
- Handle each safe-area edge (top, bottom, left, right) separately. Bars and cameras can sit on a side edge.
- Keep controls out of reserved regions (the fold and the cameras). In custom views, read `reservedRegions` from the `GeometryProxy`.
- Every feature must work in every pose. Wider layouts can show more, but can't add features a standard iPhone lacks.
- Folding or resizing must not lose input, selection, navigation or work in progress.
- Use `UIHinge` only when an interaction really depends on the hinge, never in place of size classes.
- The system sets the keyboard's width, and the width can change while the keyboard is on screen. Lay out keys with flexible stacks.

### Keyboard findings

Apple's Duo docs don't cover keyboards. Record what you find here.

- None yet.

### Checks before a UI change is done

Check each of these on the Simulator. List anything you didn't check as unchecked, never as passed.

- [ ] A standard iPhone.
- [ ] Duo closed (outer display) and fully open (inner display).
- [ ] Duo partially folded, with nothing important under the fold.
- [ ] Opening, closing and folding while in use, with no lost state.
- [ ] Split View or a narrow window.
- [ ] Large Dynamic Type and VoiceOver.

`simctl` (the Simulator's command-line tool) can't change Duo poses. Use Device Hub in Xcode for those.

Docs: [Preparing your app](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo) · [HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) · [Checklist](https://developer.apple.com/iphone-duo/prepare/) · [Tech Talk](https://developer.apple.com/videos/play/tech-talks/111461/)

## Privacy

- No analytics. User text never leaves the device, except when the user taps Tidy while a cloud engine is on.
- Put any API keys in the Keychain, never in code or git.

## Out of scope

Don't build these unless asked: audio recording in the main app, background audio, Live Activities, or bundled local LLMs.
