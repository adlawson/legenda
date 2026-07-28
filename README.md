# Legenda

A menubar meeting timer for macOS. The name is "Legend" + "Agenda", which is the
whole joke.

Set out your agenda before the meeting starts, press play, and Legenda counts up
through it in a small panel that floats above your call — including over
full-screen windows, and without stealing focus from them when you press a button.

## Install

```sh
brew install --cask adlawson/tap/legenda
```

Or from source, with Swift 6.2 or later:

```sh
make install    # builds a universal .app and copies it to /Applications
make run        # build and launch without installing
make test
```

## The Buffer

Mark any agenda item as a **Buffer** (the diamond) and it becomes slack for the
rest of the meeting. When an item runs long, the overrun is quietly drawn from
buffer items still ahead of the playhead, so the projected finish time doesn't
move. Once the slack is gone the meeting goes into overtime and keeps counting.

Because slack is positional — only buffers *ahead* of where you are can pay for
an overrun — a buffer near the end of the agenda is the useful arrangement.

Items never advance on their own. Legenda can't know that a conversation has
moved on, and resetting the ring while someone is still talking would misreport
where the meeting actually is, so moving on is always a deliberate press of Next.

## The rings

- **Outer** — the current item. Completes when the item's planned time is up. Past
  that it splits, showing the planned share against the overrun, so ten minutes
  over never looks the same as two.
- **Inner** — the whole meeting. Item handovers are faint ticks and buffer items
  are dashed.

## Controls

| | |
|---|---|
| Click the ring | Pause / resume |
| **+1 min** | Extend the current item, funded from the buffer |
| **Next** | Move on; unused time returns to the buffer |
| **↩** | Undo the last Next, elapsed time intact |
| Menubar item | Click to show or hide the panel; right-click for pause, reset and quit |

## Sounds

Stock macOS sounds, no ticking: `Tink` for the last three seconds of an item,
`Submarine` on changing item, `Glass` when the buffer begins, `Basso` on going
into overtime and `Hero` at the end. They play to your own output — the call
doesn't hear them.

## Releasing

Versions are dates — `YYYYMMDD`, with an optional pre-release suffix such as
`20260728-rc1`. The suffix is kept out of `CFBundleVersion`, which Apple
specifies as digits and periods only, so that carries the date alone while
`CFBundleShortVersionString` gets the full string.

Tag a version and GitHub Actions builds the universal app, publishes the release
and attaches the zip:

```sh
git tag v20260728 && git push origin v20260728
```

The same run produces `legenda.rb` as a workflow artifact, which is the cask to
copy into [adlawson/homebrew-tap](https://github.com/adlawson/homebrew-tap) as
`Casks/legenda.rb`. To build both locally instead:

```sh
make release VERSION=20260728
make cask VERSION=20260728
```

The app is ad-hoc signed rather than notarised, so the cask strips the
`com.apple.quarantine` flag on install.

## Licence

[MIT](LICENSE)
