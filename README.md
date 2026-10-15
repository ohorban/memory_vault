# Memory Vault

A personal iPhone app for capturing your life's stories, one memory at a time, and having them come back to you later.

Open the app and you're already on **Log a memory**. Type, or tap the mic and just talk. Hit **Save**. Claude tags who was in the story, what kind of story it is, and roughly when it happened. If it isn't sure which "Alex" you mean, it asks.

## Features

**Logging (the home screen)**
- Type, or record your voice. OpenAI transcribes it and the exact transcript is saved. The original transcript and audio are kept even if you edit the text later.
- The date defaults to today. You can set an exact day, or something approximate: a month, a season ("Summer 2012"), a year, a decade, "around…", or "not sure". If you add your birth year in Settings you can also date a memory by age ("I was about 7").
- If you leave the date as today and the story says when it happened ("last Christmas", "in 2015"), Claude fills in the date.
- Optionally tag people by hand or mark a memory as a favorite before saving.
- Unsaved drafts survive the app being closed.
- **Today's memory** card at the top: one memory per day, chosen by a daily shuffle. It prefers "on this day" anniversaries, and the 🔀 button shuffles to another.

**People**
- Each person has a profile with a name, what you call them ("Mom"), relationship, other names, notes, birthday, and a photo. You can pick the photo from your library or import it from Contacts.
- After you save, Claude finds the people in the story and matches them to your contacts:
  - one clear match is tagged automatically;
  - two possible matches (two Alexes) ask **"Which Alex?"**, with your best guess preselected and each person's relationship shown so you can tell them apart;
  - someone new gets a one-tap **"Add as a new person"**.
- The app remembers new ways you refer to people. Once you link "Mama" to Mom, it recognizes "Mama" next time.
- If you can't decide right now, tap **Later**. The memory shows a "Confirm people" badge until you finish.

**Browsing (Memories tab)**
- **Timeline**, grouped by year
- **Calendar**: a month grid. Days with memories get a dot, and month- or season-level memories appear under "Sometime in …". You can jump straight to any year.
- **People**: everyone, ranked by how many memories you share
- **Types**: funny 😂, heartwarming 🥹, sad 😢, embarrassing 🙈, adventure, travel, milestone, and more, plus tone (positive / negative / bittersweet), favorites, and your own custom tags
- Search across text, titles, people, and tags
- 🎲 random memory
- 💬 **Ask your memories**: "What are my funniest stories?", "What have I done with Mom over the years?"

**Remembering**
- Optional **reminder notifications** (daily, every other day, twice a week, or weekly, at a time you choose). Each one shows a random memory, or an "On this day" one. Tap it to open the memory.
- **Speech helper** (on any person's page): pick an occasion (birthday, wedding toast, retirement, eulogy…), a style (heartfelt, funny, gentle roast), and a length. Claude drafts a speech using **only your real stories with that person**. You can also ask it just to pick the best stories.

**Data and privacy**
- Everything is stored on the phone (SwiftData). API keys are kept in the iPhone Keychain.
- Memory text is sent to Anthropic for tagging, and audio is sent to OpenAI for transcription. Nothing else leaves the device.
- Export and import a JSON backup from Settings. Voice recordings aren't included in the backup.

## Running it on your iPhone

You need a Mac with **Xcode 16 or newer** (the project uses Xcode 16's folder-synced project format) and an iPhone on **iOS 17+**.

1. Clone this repo and open `MemoryVault.xcodeproj`.
2. Select the **MemoryVault** target → **Signing & Capabilities**:
   - Team: choose your Apple ID. Add it under Xcode → Settings → Accounts if it isn't listed. A free Apple ID works.
   - Bundle Identifier: change `com.ohorban.MemoryVault` to something unique if Xcode complains.
3. Plug in your iPhone and select it as the run destination. On the phone, turn on **Settings → Privacy & Security → Developer Mode** (the phone will restart).
4. Press **Run** (⌘R). The first time, the phone may ask you to trust the developer certificate: **Settings → General → VPN & Device Management**.
5. In the app's **Settings** tab, paste in:
   - an **Anthropic API key** (console.anthropic.com) for tagging, the speech helper, and Ask
   - an **OpenAI API key** (platform.openai.com) for voice transcription

> **Free vs paid Apple developer account:** with a free Apple ID, the app expires after 7 days. Your data stays on the phone, and you just press Run again from Xcode. A paid developer account ($99/yr) makes builds last a year and lets you install through TestFlight without a cable.

### Costs (rough)
- Tagging a memory with Claude Haiku 5.5 ($0.10 / $0.50 per million input / output tokens) costs a small fraction of a cent.
- Transcribing with `gpt-4o-transcribe` costs about $0.006 per minute of audio.
- A speech draft or an "Ask" question sends your relevant memories as context. That's still cents, even with thousands of memories.

## Changing the AI model

- **Another Claude model:** Settings → Models → type a model ID (blank = `claude-haiku-5-5`). Use a model that supports the `effort` setting (Claude 4.6 or newer).
- **Another provider:** all AI calls go through the `LLMClient` protocol (`MemoryVault/Services/LLMClient.swift`). Write a new client that conforms to it and return it from `LLMFactory.makeClient()`. Nothing else needs to change.
- **Transcription model:** Settings → Models (`gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1`).

## Project layout

```
MemoryVault/
  MemoryVaultApp.swift        App entry, notification taps
  RootView.swift              Tabs: Log · Memories · People · Settings
  Models/                     Memory, Person (SwiftData), MemoryDate (approximate dates), categories
  Services/
    LLMClient.swift           Provider-neutral AI interface + factory
    ClaudeClient.swift        Claude Messages API over HTTPS (structured JSON output, prompt caching)
    MemoryAnalyzer.swift      Prompt + JSON schema for extracting people / types / tone / date
    MemoryProcessor.swift     Matching mentions to people ("which Alex?"), applying results
    TranscriptionService.swift OpenAI speech-to-text
    RecallService.swift       Speech helper and "Ask your memories"
    ReminderScheduler.swift   Local notifications
    DailyPick.swift           Memory of the day / on this day
    Audio.swift, Keychain.swift, BackupService.swift, ContactImporter.swift, AppSettings.swift
  Views/                      Log, Memories, People, Settings, shared components
```

## Ideas for next steps

- **Home-screen and lock-screen widget** showing the memory of the day
- **Action button / Siri shortcut**: "Log a memory" goes straight to recording (App Intents)
- **Interview mode**: Claude asks follow-up questions ("What did Mom say then?") to draw out more detail
- **Photos on memories**, plus "this photo reminds me…" prompts from your camera roll
- **Birthday reminders** that bring up your stories with that person a few days early (useful for cards and toasts)
- **iCloud sync and backup** through CloudKit (needs a paid developer account)
- **Face ID lock** for privacy
- **Life chapters**: yearly summaries, or a printable "book" of your stories
