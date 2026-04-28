# Handoff: Live Activity + workout UI (blocked in Plan mode)

Cursor was in **Plan mode**, which only allows editing markdown. **Enable Agent mode** and ask to *implement this doc*, or apply the following yourself.

## 1) URL scheme + deep links (main app)

**`App/Resources/Info.plist`** — add:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.loggy.app.deeplink</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>loggy</string>
    </array>
  </dict>
</array>
```

**`App/LoggyApp.swift`** — on the `RootView` branch, add:

```swift
.onOpenURL { url in
    env.handleWorkoutLiveURL(url)
}
```

**`App/AppEnvironment.swift`** — add `@MainActor func handleWorkoutLiveURL(_ url: URL)` that:

- Parses `loggy://workout/live-action?op=...&sid=...&wse=...&set=...&d=...` (see parser below).
- Verifies `sid == (try? workouts.activeSessionSummary()?.sessionId)` so only the active session is mutated.
- **`op=complete`**: `try workouts.completeSet(sessionId: sid, sessionExerciseId: wse!, setId: set!)` then refresh anything in-memory if you add a bus later.
- **`op=weight_delta`**: read set, `updateSet` with `weightKg: max(0, current + d)`.
- **`op=reps_delta`**: `updateSet` with `reps: max(0, current + Int(d))`.
- **`op=skip_rest`**: `if let t = try? restTimers.activeTimer(for: sid) { try? restTimers.skipTimer(timerId: t.id) }`.

Add a small **`LoggyWorkoutDeepLink.swift`** with `URLComponents` parsing (query: `op`, `sid`, `wse`, `set`, `d`).

**Health copy** — extend `NSHealthShareUsageDescription` to mention reading **active energy** for live totals.

## 2) Apple Health — efficient live kcal (main app)

**`AppleHealthWorkoutService.swift`**

- `import Combine`
- Private `liveEnergyTimer: AnyCancellable?`
- `@Published private(set) var cumulativeActiveEnergyHealthKitKcal: Double?`
- In `requestAuthorization`, add **`energyType`** to **`toRead`** (not only `heartRateType`).
- `activeWorkoutScreenAppeared`: after `startHeartRateQuery`, call `startLiveEnergyPolling(sessionStartedAt:)`:
  - `Timer.publish(every: 30, ...)` (30s is enough; user asked for efficiency).
  - Handler runs `HKStatisticsQuery` on `activeEnergyBurned`, `predicateForSamples(start: sessionStart, end: Date())`, options **`.cumulativeSum`**; set published property if `> 0.05`, else `nil`.
- `activeWorkoutScreenDisappeared`: `stopLiveEnergyPolling()`.
- Public `estimatedSessionEnergyKcalSoFar(sessionStartedAt:now:)` — same MET math as `estimatedActiveEnergySample` but for elapsed interval only (for UI fallback).
- `setSyncWorkoutsToHealthEnabled(false)`: clear cumulative + stop timer.

## 3) `WorkoutActivityAttributes` + `LiveActivityManager` + VM

**`WorkoutActivityAttributes.ContentState`** — add (all `Codable`):

- `liveSessionExerciseId: String?`
- `liveSetEntryId: String?`
- `currentSetTitle: String` — e.g. `"Set 3"` / `"W"`
- `nextSetPreview: String` — e.g. `"Next: Set 4"` or `"Next: Squat · Set 1"`
- `currentKgDisplay: String`, `currentRepsDisplay: String`
- `heartBpm: Int?`, `activeKcalDisplay: String?` — optional denormalized strings so the widget does not depend on HealthKit.

**`LiveActivityManager.update(...)`** — extend signature; **`ActiveWorkoutViewModel.pushLiveActivity`** builds snapshot from `ActiveWorkoutFocus` + current `SetRowModel` + `appleHealth.latestHeartRateBpm` + display kcal (prefer `cumulativeActiveEnergyHealthKitKcal` else `"~\(Int(estimated))"`).

## 4) Widget: lock screen + Dynamic Island

**`WorkoutLiveActivityWidget.swift`**

- **`ActivityConfiguration` lock screen**: richer layout — exercise name (title2), row with **current set title**, **previous** string if you add `previousDisplay` to state, **current kg × reps** large, **nextSetPreview**, **rest** line using **`Text(restEndsAt, style: .timer)`** when `restEndsAt != nil`.
- **`Link`** rows (not sensitive):  
  - Complete: `loggy://workout/live-action?op=complete&sid=...&wse=...&set=...` (percent-encode ids).  
  - Weight −2.5 / +2.5, reps −1 / +1 as separate `Link`s.  
  - Skip rest: `op=skip_rest&sid=...`.
- Remove or lighten `activityBackgroundTint` if you want a cleaner look; use subtle material on inner card.

**Note:** `WorkoutActivityAttributes.swift` is compiled into **both** app and `LoggyLiveActivity` extension — keep the struct **simple** (no GRDB imports).

## 5) Active workout screen (main app)

**`ActiveWorkoutView.swift`**

- **Toolbar**: principal = **title only** (`.subheadline.weight(.medium)`, `lineLimit(1)`, `minimumScaleFactor(0.75)`); trailing `HStack`: **elapsed** (`.caption.monospacedDigit()`), menu, Finish.
- **ZStack order**: (1) `RestTimerPerimeterOnly` — **only** `ScreenBorderShape` strokes inside `TimelineView`; (2) `VStack` summary + timer strip + list; (3) `RestTimerFloatingChrome` — center seconds + bottom −15 / Skip / +15 (second `TimelineView` OK).
- **Summary strip**: smaller type (`.caption2` labels, `.caption` / `.subheadline` values); show **BPM** when present; show **kcal** — Health cumulative if non-nil else `~` MET estimate from `appleHealth.estimatedSessionEnergyKcalSoFar(sessionStartedAt:)` when `sessionStartedAt` passed from VM (or read from VM published `sessionStartedAt`).
- **`SetRow`**: single **`HStack`**: label (narrow) | previous (flex, lineLimit 1) | kg field | reps field | check; **remove** rounded card; **Divider** bottom; tight vertical padding. Mode branches for duration / distance.

## 6) After coding

- `xcodebuild` for **Loggy** + **LoggyLiveActivity** targets.
- Exercise Live Activity on device: tap **Link** opens app — ensure `onOpenURL` fires and completes set.

---

**Unblock:** Cursor → **Agent mode**, then: *“Implement `Docs/LIVE_ACTIVITY_AND_WORKOUT_UI_HANDOFF.md`”*.
