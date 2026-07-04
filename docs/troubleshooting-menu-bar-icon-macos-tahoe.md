# Menu bar icon missing on macOS Tahoe (26.x): diagnosis and fix

**TL;DR** — On macOS Tahoe, a third-party app's menu bar icon can become *permanently invisible* because of a corrupted record in Control Center's private status-item registry. The app runs fine, its hotkeys work, and System Settings → Menu Bar even shows the app as enabled — but the icon never appears, and **no user-facing control can fix it** (not the Settings toggles, not "Reset Control Centre…", not reinstalling, not rebooting). The registry lives in a Full-Disk-Access-protected file and can be repaired by hand. This document explains the mechanism, the diagnosis, and the exact repair, based on a real case fixed on 2026-07-04 (JVoice on macOS 26.5.1).

This is **not a JVoice bug** — any menu bar app can be affected. It is documented here because JVoice was the app that got hit, and the diagnosis took a full forensic session that nobody should have to repeat.

---

## Symptoms

- The app is running (hotkeys, windows, everything works) but its `NSStatusItem` never appears in the menu bar.
- Survives: app relaunch, rebuild, reinstall, macOS reboot.
- System Settings → Menu Bar lists the app with its toggle **on** (or toggling it off/on changes nothing).
- Other copies of the *same binary* — run from a different path, or with a different bundle identifier — show their icon instantly.
- In the unified log, Control Center classifies the app as a **blocked host** (see Diagnosis step 1).

## Background: how Tahoe hosts third-party menu bar items

On macOS 26, third-party status items are no longer independent app windows — they are **hosted by Control Center** (`/System/Library/CoreServices/ControlCenter.app`) via the FrontBoard scene system. When an app creates an `NSStatusItem`, Control Center looks the app up in a persistent registry keyed by **app identity**: the bundle identifier for bundled apps (`bid:` in logs), or the executable path for bare binaries (`path:` in logs). If the registry says the identity is not allowed, Control Center "tracks a blocked host": the item's window is parked off-screen at coordinates `(0, −22)` and never adopted into the menu bar. The app-side API sees nothing wrong — `NSStatusItem.isVisible` reads `true` while the item is invisible.

The registry is the `trackedApplications` key (a nested binary plist) inside:

```
~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist
```

That folder is TCC-protected (TCC is macOS's per-app privacy/permission system): reading it from a terminal requires the terminal app to have **Full Disk Access**.

Each registry entry is a pair: an identity key, then a record like `{isAllowed: Bool, location: <identity>, menuItemLocations: [<identity>, …]}`. `isAllowed: false` means the user hid that app's icon (⌘-drag off the bar, or the Menu Bar settings pane).

## The corruption (what actually happened)

In the observed case, the record for **one app the user had deliberately hidden** (VS Code, `isAllowed: false`) had somehow absorbed *other apps' identities* into its `menuItemLocations` array:

```
{'bundle': {'_0': 'com.microsoft.VSCode'}},
{'isAllowed': False,
 'location':  {'bundle': {'_0': 'com.microsoft.VSCode'}},
 'menuItemLocations': [{'bundle': {'_0': 'com.example.app-a'}},
                       {'bundle': {'_0': 'com.example.app-b'}},
                       {'bundle': {'_0': 'com.example.app-c'}},
                       {'bundle': {'_0': 'com.jvoice.app'}}]}   ← hostages
```

(Unrelated apps' identifiers redacted; the structure is verbatim from the affected machine.)

Any app listed inside a hidden app's `menuItemLocations` **inherits the hidden state** — even when its own record says `isAllowed: true`. That is why the Settings pane showed JVoice as enabled while Control Center blocked it on every launch. How the cross-contamination happened is unknown (suspects: the Tahoe menu-bar state migration, or a ⌘-drag rearrangement while multiple items moved), but once present it is self-sustaining.

## Diagnosis (10 minutes)

1. **Confirm the block.** Quit and relaunch the affected app while watching Control Center:

   ```bash
   /usr/bin/log stream --predicate 'process == "ControlCenter" AND category == "appStatusItems"'
   ```

   A healthy app logs `Starting to track host; (bid:com.example.app-Item-0-<pid>)`.
   An affected app logs `Starting to track **blocked** host; …`.

2. **Prove it's identity-keyed, not a code bug.** Copy the app (or bare binary) to a fresh path and launch the copy. If the icon appears for the copy but not the original — the block is keyed to the original's identity, and the registry is the problem. (For bundled apps the key is the bundle identifier: a copy with a changed `CFBundleIdentifier` shows the icon; a copy with the same one stays hidden.)

3. **Inspect the registry.** Grant your terminal Full Disk Access (System Settings → Privacy & Security → Full Disk Access — remove it again when done), then:

   ```bash
   python3 - <<'EOF'
   import plistlib, pathlib, pprint
   p = pathlib.Path.home()/"Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"
   d = plistlib.load(open(p,'rb'))
   apps = plistlib.loads(d["trackedApplications"])
   for i in range(0, len(apps), 2):
       pprint.pprint((apps[i], apps[i+1]), width=140)
   EOF
   ```

   Look for: (a) your app's identity inside **another** record's `menuItemLocations` where that record has `isAllowed: False` — the hostage situation above; (b) a stale record for your app's identity itself with `isAllowed: False`.

## What does NOT fix it (all verified dead ends)

Save yourself the time — every one of these was tried and failed:

| Attempt | Result |
|---|---|
| System Settings → Menu Bar toggle off/on (idle or with the app running) | Flips visually; writes an unrelated, effectively empty store; zero effect |
| The pane's **"Reset Control Centre…"** button | Resets module layout only; registry untouched |
| `defaults delete com.apple.controlcenter` (+ ByHost variants, `displayablemenuextras`, `bentoboxes`, `com.apple.systemuiserver`) + daemon restarts | Registry lives elsewhere; no effect |
| `killall ControlCenter` / `SystemUIServer` / `cfprefsd`, reboots, Safe-Mode-style cache advice from the internet | Block reloads from the group-container file every time |
| App-side fixes: setting `isVisible = true`, toggling it, setting an `autosaveName`, `NSStatusItem` recreation delays | Host-side state wins; the app cannot see or clear it |
| Re-signing the binary, LaunchServices re-registration (`lsregister -f/-u`), reinstalling to the same path | Identity unchanged → still blocked |
| Forcing the migration flag `HasAttemptedMenuBarWorkflowMigration = false` | Re-migration preserves the corrupt records |

## The fix (registry surgery)

Requires Full Disk Access for your terminal, ~5 minutes. **Back up the file first.**

1. **Back up:**

   ```bash
   cp ~/Library/Group\ Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist ~/Desktop/group-cc-backup.plist
   ```

2. **Repair.** Adapt this to what step 3 of the diagnosis showed. For the hostage case (app trapped in another record's `menuItemLocations`) reset that record's list to itself; delete any stale `isAllowed: False` record for your app's identity outright (records are re-created cleanly the next time the app connects):

   ```bash
   python3 - <<'EOF'
   import plistlib, pathlib
   p = pathlib.Path.home()/"Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"
   d = plistlib.load(open(p,'rb'))
   apps = plistlib.loads(d["trackedApplications"])

   HOSTAGE_HOLDER = "com.microsoft.VSCode"   # the hidden app whose record holds your app hostage
   DELETE_RECORDS = []                        # e.g. ["file:///path/to/stale/binary"] or ["com.example.stale"]

   def name(key):
       if "bundle" in key: return key["bundle"]["_0"]
       if "adhocBinary" in key: return key["adhocBinary"]["_0"]["relative"]
       return ""

   out = []
   for i in range(0, len(apps), 2):
       key, rec = apps[i], apps[i+1]
       if name(key) in DELETE_RECORDS:
           continue
       if name(key) == HOSTAGE_HOLDER:
           rec["menuItemLocations"] = [dict(key)]   # keep only its own item
       out += [key, rec]

   d["trackedApplications"] = plistlib.dumps(out, fmt=plistlib.FMT_BINARY)
   plistlib.dump(d, open(p,'wb'), fmt=plistlib.FMT_BINARY)
   print("written:", len(out)//2, "records")
   EOF
   ```

3. **Restart the daemons — and verify the edit survived.** Both `cfprefsd` (the preferences daemon) and Control Center cache the registry and can flush stale state back over your edit on exit, so check the file after each kill and re-run step 2 if it got clobbered:

   ```bash
   killall cfprefsd; sleep 2   # then re-run the inspection snippet — still clean?
   killall ControlCenter; sleep 3   # Control Center respawns automatically — inspect again
   ```

4. **Relaunch the app.** The log should now say `Starting to track host` (no "blocked") and the icon appears. Deliberately-hidden apps (their own records with `isAllowed: False`) stay hidden, as the user chose.

5. **Revoke Full Disk Access** from the terminal.

## Notes for menu bar app developers

- Your app cannot detect or repair this: the item reports `isVisible == true` while parked. The only in-app signal is the item's `button.window?.frame` remaining at `(0, −22, w, 22)` a second or two after creation instead of moving into the bar (y ≈ screen top, height 33).
- Debug builds may appear immune while release builds "fail" — that's just identity: an unbundled debug binary at a different path is a different registry key. Don't chase optimizer ghosts.
- A fresh bundle identifier always escapes the block, but don't ship an ID change to fix one machine — repair the machine's registry instead.

## Case study provenance

Diagnosed and fixed 2026-07-04 on macOS Tahoe 26.5.1 (build 25F80) for JVoice (`com.jvoice.app`). The full forensic trail (window-server frame dumps, Control Center log analysis, the differential identity experiments, and every dead end above) was captured in that session; this document is its distilled result.
