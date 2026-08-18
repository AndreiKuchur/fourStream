# FourStream

An iPhone app that broadcasts camera and microphone to any public RTMP
destination (Twitch and friends). Enter an ingest address and stream key once,
then go live and stop from a single screen.

iOS 16+, iPhone, portrait. UIKit in code, MVVM, Swift 6 language mode with
`SWIFT_STRICT_CONCURRENCY = complete`. Swift Concurrency only — actors,
`AsyncStream`, `@MainActor`; no GCD, no Combine, no delegates. One dependency:
HaishinKit 2.2.5. **82 unit tests** over ~2 700 lines of production code.

```sh
# open FourStream/FourStream.xcodeproj, then a physical iPhone + your signing team
xcodebuild test -scheme FourStream -project FourStream/FourStream.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The Simulator has no camera, so anything past an empty preview needs hardware.
Credentials come from Twitch (*Settings → Stream*) and live in the Keychain —
there are no config files or secrets in the repo.

---

## Architecture

```
UIKit         ConfigurationViewController     BroadcastViewController + MTHKView preview
              renders a state, forwards intent, holds no business logic
                  │                               │
@MainActor    ConfigurationViewModel          BroadcastViewModel
              validate · persist              state machine · timers · deadlines
                  │                               │
boundaries    CredentialsStoring              MediaAuthorizing · Broadcasting (actor)
                  │                               │
platform      KeychainCredentialsStore        SystemMediaAuthorizer · HaishinKitBroadcaster
              (Security)                      (AVFoundation)        ← the only file that
                                                                      imports the SDK

pure values   BroadcastState · BroadcastError · StreamQuality · CredentialsValidator
```

Intent goes down as method calls, state comes back up as `AsyncStream<State>`.
Two invariants, both grep-checkable: **`import RTMPHaishinKit` appears in exactly
one file**, and **no `*ViewModel.swift` imports UIKit**. Everything below follows
from those.

### `BroadcastState` — the state machine

One enum, one pure transition: `applying(_ event: Event, at now:) -> BroadcastState`.

Three booleans (`isStreaming`, `isConnecting`, `hasError`) give eight
combinations of which only four mean anything, and nothing prevents the other
four. The hard part of this screen is that "publish confirmed", "connection
dropped", "user pressed Stop", "app backgrounded" and "camera taken by another
app" can all land in the same second, in any order. An explicit transition table
makes illegal combinations unrepresentable and legal ones reviewable at a glance.

`now` is a parameter rather than a clock read, so all 12 tests for the table are
synchronous and deterministic. One asymmetry worth noting: `Reconnecting` carries
the *original* `startedAt`, so a reconnect doesn't reset the duration viewers see.

### `Broadcasting` — the streaming boundary

```swift
protocol Broadcasting: Actor {
    var events: AsyncStream<BroadcastEvent> { get }
    func prepare(quality: StreamQuality) async throws
    func attachPreview(_ surface: PreviewSurface) async
    func start(to credentials: StreamCredentials) async throws
    func stop() async
    func teardown() async
    func captureConfiguration() -> CaptureConfiguration
    func switchCamera(to position: CameraPosition) async throws
    func setMicrophoneEnabled(_ enabled: Bool) async
}
```

The one abstraction that clearly earns its keep: `AVCaptureSession` and RTMP
cannot exist in a unit test, so without this seam the interesting logic —
deadlines, reconnect, teardown ordering, permission timing — would only be
verifiable by hand on a device. With it, 31 tests drive the whole screen.

- **`: Actor`**, because capture state is mutated from several tasks and the
  compiler should enforce the isolation. The test double is an actor too, so
  tests face the same interleaving as production.
- **Four lifecycle methods, not two**, because there are four distinct moments:
  capture exists before a broadcast does, and a stopped broadcast releases less
  than a closed screen. Collapsing them holds the camera too long or drops the
  preview too early.
- **Events as `AsyncStream`**, consumed in one `for await` tied to the render
  task's lifetime. Cancelling unsubscribes; there is no delegate to forget.
- **No `connecting` event.** The screen enters Connecting because the *user* asked
  for a broadcast. An inbound event could let a connection nobody is waiting for
  put the screen back on air.

### `HaishinKitBroadcaster` — where the awkward reality lives

- **Session counter.** Opening a connection takes seconds and an actor admits the
  next call at every `await`. `stop()`/`teardown()` bump `session`; a connection
  that finishes opening after its session was superseded is discarded, not
  announced. Without it, Start→Stop→Start can leave an orphaned publish.
- **Throughput watchdog.** RTMP has no status code for "accepted your publish and
  is receiving nothing". Three consecutive zero-byte samples *after* the first
  byte are reported as a drop; samples before it are ignored, because a fresh
  publish is legitimately quiet.
- **Errors separated by how far the attempt got.** A refused destination and a
  dead network both surface as a failed connect, and naming the wrong one sends
  the user to fix the wrong thing. Only a socket that never carried a
  conversation is "no network"; once the server answered — including by closing
  after the handshake, which is what a wrong app path looks like — the address
  and key are what the user can act on.
- **System interruptions** (audio interruption, capture runtime error, camera
  taken by another app) become user-facing failures. Backgrounding also
  interrupts capture and is deliberately *not* an error — that path ends the
  broadcast on its own.

### View models

`@MainActor final class`, each with `private(set) var state` plus an
`AsyncStream<State>` the controller renders from. Hand-rolled rather than Combine
because the codebase is already structured-concurrency and two async idioms for
one job is worse than one; tests also read `viewModel.state` synchronously
without subscribing.

Everything time-shaped lives here: the elapsed ticker, the **10 s connect
deadline** and the **15 s reconnect bound**, both injectable `Duration`s so tests
exercise timeouts in milliseconds. They exist because the RTMP layer's own bounds
are looser than the product needs (15 s socket + 3 s per command) and *nothing*
bounds the wait for the destination to confirm a publish.

`BroadcastScreenState` is one struct; `render(_:)` is a switch over it. Derived
questions ("is the preview obscured?", "does leaving need confirmation?") are
computed properties on the view model, so the controller never re-derives policy.

### The three concurrency hazards

| Hazard | When it bites | Answer |
|---|---|---|
| prepare/release overlap | Backgrounding and returning quickly — a release that started first finishes last, undoing a successful prepare and freezing the preview | `performCapture(_:)` chains each transition onto the previous `Task` |
| connection outliving intent | Start→Stop→Start faster than the handshake | the `session` counter; superseded connections discarded |
| double-tap on Start | State must not read Offline while preparation is in flight | `Connecting` is entered **before the first suspension point** |

---

## Extensibility seam (the clock overlay)

The assignment asks for a foundation for drawing on the outgoing picture. There
is exactly one place, and it is marked in the code:

```swift
private func configureEncodedScreen(size: CGSize) async {
    await Task { @ScreenActor in
        mixer.screen.size = size
        // Overlay seam: try mixer.screen.addChild(TextScreenObject())
    }.value
}
```

`MediaMixer.screen` is HaishinKit's compositor — it already composites camera
frames with screen objects, so a clock is a `TextScreenObject` added here and
touches nothing else: not the protocol, not the state machine, not a view.

**No `OverlayComposing` protocol, no registry.** The foundation already exists
inside the SDK; wrapping it adds a layer whose only client is a hypothetical
clock. When a second and third overlay appear — with ordering and visibility
rules — that's when a descriptor type pays for itself. What matters now is that
the seam is identified, isolated, and one line wide.

---

## Tests

82 tests, Simulator-only, none of them waiting out a real second.

| Area | # | What is pinned down |
|---|---:|---|
| `BroadcastViewModel` | 31 | start/stop, both timeouts, one-attempt reconnect, permission timing, camera flip, mic intent vs. reality, backgrounding, prepare/release serialisation |
| `CredentialsValidator` | 12 | schemes, hosts, whitespace, which field each message belongs to |
| `BroadcastState` | 12 | the full table, including transitions that must be ignored |
| `ConfigurationViewModel` | 11 | load, validate, save, Keychain read/write failures |
| `StreamQuality` | 8 | every unsupported-parameter reason |
| `BroadcastError` + `ElapsedTime` | 8 | wording, offered action per failure, duration formatting |

**Three hand-written doubles, one per boundary** — the entire mocking
infrastructure, ~210 lines, no framework. They record call *order*, which is what
makes "releasing capture never interleaves with preparing it" and "the microphone
was never requested before the first Start" expressible at all.

**Not unit-tested:** capture and RTMP. Neither exists in a Simulator, and a stub
of `AVCaptureSession` deep enough to be meaningful is just testing the stub.
Those paths are checked on a device against a real channel — permissions and
preview, go live and stop, controls while live, each failure path, backgrounding,
and the stream parameters as reported by Twitch's own inspector.

---

## What I deliberately did not build

"Simple" and "unfinished" look alike in a diff, so: there are **exactly three
protocols**, each existing to make a specific set of tests possible. No facade
over the broadcaster, no coordinator over two screens and one push, no repository
over one Keychain item, no DI container for three objects built in
`SceneDelegate`, no `UseCase` per button.

The one place navigation might have justified a coordinator is one injected
closure — `ConfigurationViewController` gets
`makeBroadcastScreen: (StreamCredentials) -> UIViewController`, so the first
screen pushes the second without ever holding the streaming or permission
boundaries.

The effort went into correctness at the edges instead: teardown ordering,
superseded sessions, bounded waits, permission timing, actionable error messages,
and enough test density that changing something tells you immediately whether you
broke it. **Fewer layers, more covered behaviour.**

---

## Requirements that read two ways

Each of these is implemented; the "later" notes are about depth, not gaps.

**1. "Initialize the camera only after explicit user action" vs. "the screen
immediately activates the camera for preview."** Read as separating *capture*
from *broadcasting*. Nothing is touched at launch or on the configuration screen;
arriving on the broadcast screen (which requires saving credentials — a
deliberate act) starts capture and preview; the encoder, RTMP connection and
microphone attach **only on Start**. *Later:* an explicit "Enable camera"
placeholder would satisfy the strict reading at the cost of a tap — a product
call, not mine to make unilaterally.

**2. "Don't show a live preview while the stream is disconnected or failed."**
Taken literally this contradicts the mandatory immediate preview. Read as *a live
image must never be mistaken for a live broadcast*: the image stays in every
state, the panel always names the true state, and in Error/Reconnecting the
picture is **blurred and dimmed** under the message. A frozen last frame would be
worse — a still reads as a stalled broadcast rather than an inactive one.

**3. "Pause on backgrounding… without stale state."** These pull opposite ways: a
paused RTMP session *is* state that can go stale. Backgrounding therefore **ends**
the broadcast — full teardown, Offline on return, no prompt, since backgrounding
is a system event. Leaving by Back or the pop gesture *is* a choice, so while
live it asks for confirmation. *Later:* a real pause needs a grace window, a
"be right back" card in the video track, and a background-audio entitlement.

**4. Reconnect policy is unspecified.** Chosen: exactly one automatic attempt,
bounded at 15 s, no backoff, no counter; the duration keeps running; failure
lands in Error with Retry. A silent retry loop is worse than a clear failure with
a button. *Later:* an injectable policy with capped exponential backoff, jitter,
and reachability-triggered retry — the reconnect is already one method with
injected bounds.

**5. Microphone "on/off" — mute or detach?** Both, at different moments. While
live it **mutes the mixer**, because audio and video share one `AVCaptureSession`
and attaching an input reconfigures it, visibly stalling the picture. On **stop**
the device is genuinely detached and the audio session deactivated, so the system
indicator clears between broadcasts. The camera isn't released there — the
preview outlives the broadcast. The view model also tracks *intent* separately
from what the hardware is doing, so the control shows the user's choice while
Offline and reality while live.

**6. "Guarantee the outgoing stream matches configured settings."** Impossible to
guarantee against a remote server, so: pre-flight validation against the device's
real `AVCaptureDevice.formats` with the reason named ("Unsupported resolution:
1280×720.", "Codec not available: H.264.") — nothing fails silently; the encoder
transposed to **720×1280** so a portrait phone yields a portrait stream and
preview matches output; and measured video bitrate and frame rate reported in the
sheet, falling back to configured only while the SDK reports nothing.

**7. Bottom sheet — "bitrates, codec, status…"** Shows state, failure reason,
picture size, both bitrates, frame rate, both codecs; duration stays on the panel
that opened it. *Later:* RTT, dropped frames, a bitrate sparkline — and blanking
the last measured numbers when the state leaves Online instead of leaving them on
screen.

**8. Orientation.** The assignment offers three options; chosen: **portrait lock,
documented**. Landscape needs a second layout for both screens plus a
viewer-facing decision about rotating mid-broadcast, none of which demonstrates
anything about RTMP. *Later:* unlock rotation with orientation fixed for the
duration of a broadcast — chrome rotates, the encoded picture doesn't.

**9. Where the key is "saved."** Keychain, generic password,
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, masked field, never logged. A
stream key is a bearer credential; `UserDefaults` is a plist in the container.

**10. "A phone missing a frontal camera."** Camera positions are *discovered*, not
assumed: one camera disables the flip control and says why, **zero** cameras is a
named failure. An empty set means "capture hasn't reported yet", not a claim
about the device. Same care for restricted (not merely denied) access, which
offers no Settings route because Settings can't fix a device policy.

**11. SwiftUI is offered; I used UIKit.** A control call, not a comfort one: this
screen's correctness is view-lifecycle precision — attaching `MTHKView` as a
capture output, releasing capture only when actually leaving, intercepting the
pop gesture before a live broadcast dies, disabling the idle timer exactly while
on air. In SwiftUI each becomes a `UIViewRepresentable` or a workaround. The view
models import no UIKit, so a SwiftUI front end would be additive anyway.

---

## Permissions, in one table

Nothing is requested at launch or on the configuration screen.

| Permission | When | Why then |
|---|---|---|
| Camera | entering the broadcast screen | the preview can't exist without it, and that navigation is the deliberate action justifying the prompt |
| Microphone | first Start, or first turn-on of the mic control | the preview needs no audio; asking earlier prompts for a feature not in use |

Refused camera access explains itself and offers **Open Settings**; granting it
there and returning restores the preview with no relaunch. A refused microphone
still lets the broadcast start, silent, keeping a route to Settings. Recovery is
per-failure, not one generic Retry: a camera failure rebuilds capture, a
connection failure reconnects, a permission failure opens Settings — and a
recovered camera does not clear a rejected stream key.

---

## Limitations

- Physical iPhone required for anything past the preview.
- Portrait only; one fixed quality preset (720p30, H.264 + AAC, 2 500 / 128 kbit/s).
- One reconnect attempt per drop, 15 s bound, no backoff.
- No logging or analytics at all — nothing leaks a stream key, but nothing is
  diagnosable after the fact either.
- English only; no account, no platform API, no backend.

## What a production version would add

**Packages.** Split into `StreamingCore` (protocol + pure values),
`StreamingHaishinKit` (adapter), `Credentials`, and the app — so "only one file
imports the SDK" is enforced by the build graph instead of a grep, and swapping
the SDK is a package-level change.

**Inverted dependencies.** Protocols owned by the package that defines the
abstraction rather than sitting beside their implementations; one composition
root per feature instead of `SceneDelegate`; the clock injected as a protocol so
*all* time-dependent behaviour is deterministic, not just the two deadlines.

**Observability.** Structured `Logger` per subsystem with privacy annotations so
a key can never reach a log, signposts around prepare/connect/publish, then
metrics (connect success rate, time-to-first-byte, reconnect frequency, drop
cause) and crash breadcrumbs of the last N state transitions. Diagnosing "my
stream dropped" from a user report is impossible without this — it is the single
biggest gap between this code and production code.

**Plus:** CI running build/tests/lint per PR, snapshot and UI tests over the two
flows, a device farm for the capture paths unit tests can't reach, localisation
(every string already lives in an enum), accessibility labels and Dynamic Type,
and adaptive bitrate driven by real telemetry.
