# Google Drive Backup — why there's a one-time Google Console setup, and how to do it

*Why this document exists: the Android Google Drive backup feature requires one-time publisher-side registration with Google before it works on any device. This explains what that is, why Google requires it, and exactly what to do. Companion to `GOOGLE_DRIVE_RECOVERY.md`.*

---

## What this is

Before any app can talk to a Google API on a user's behalf — including reading
and writing its own hidden folder in the user's Google Drive — Google requires
the **developer** to register the app once with Google's identity platform.
That registration happens in the **Google Cloud Console**
([console.cloud.google.com](https://console.cloud.google.com)), is free, and
takes about 15 minutes.

This is the exact Google-side counterpart of what iCloud backup required on
iOS: there, the app only works because it has an App ID with the iCloud
entitlement configured in Apple's developer portal. Users never saw that
setup on iOS, and they'll never see this one on Android.

**This is not per-user setup.** Once registered, every user gets the
out-of-the-box experience: flip the "Back up to Google Drive" toggle → the
system shows Google's account picker and consent sheet → tap Allow → done.

## Why Google requires it

Three reasons, and the third one genuinely matters for a wallet:

1. **The consent sheet must name a verified app.** When the user is asked
   "Allow *Cashu* to store its own data in your Google Drive?", Google has to
   know that the thing asking really is Cashu. The registration is what backs
   that identity.

2. **Quota and abuse accounting.** API usage is tracked per registered app so
   one abusive app can't degrade the API for everyone.

3. **It locks the backup to your app.** The hidden Drive `appDataFolder` is
   scoped to the OAuth client — the only app that can ever read the backups
   Cashu writes is an app with Cashu's package name **and** Cashu's signing
   certificate. A malicious app cannot impersonate Cashu to fish seed phrases
   out of people's Drives. For a backup that contains a spendable seed, this
   is a security feature, not red tape.

## How Google identifies the app (and why there are TWO registrations)

There is **no client ID or API key in the code**. On Android, Google Play
services identifies the calling app by the pair:

> **(package name, SHA-1 fingerprint of the app's signing certificate)**

When the app calls `authorize()`, Google checks whether a registered Android
OAuth client matches that pair. Match → consent sheet / silent token. No
match → developer error.

Our Gradle config gives debug builds a different identity than release builds:

| Build | Package | Signed with |
|---|---|---|
| Release | `com.cashu.me` | your release keystore (or Google's Play App Signing key) |
| Debug | `com.cashu.me.debug` | the auto-generated debug keystore on each dev machine (`~/.android/debug.keystore`) |

Different package + different certificate = a different app in Google's eyes,
so **each needs its own OAuth client entry**. Registering only the release one
is the classic trap: the feature works in production builds but fails with a
developer error on your own dev machine, which looks like a mysterious bug.

## How this relates to the Play Store

Mostly it doesn't — that's a common confusion:

- **Google Cloud Console** (this setup) is Google's *API/identity* platform.
  It's required even if you never publish to the Play Store (e.g. APK
  sideloads, F-Droid-style distribution to GMS devices).
- **Google Play Console** is the *store*. Publishing there does not register
  any OAuth clients for you.

They intersect in exactly one place: **Play App Signing**. If the Play Store
manages your signing key (the default for new apps), Google re-signs the app
you upload — so the certificate users' devices actually see is Google's
app-signing key, not your upload key. In that case, the release SHA-1 you must
register is the **"App signing key certificate"** SHA-1 shown in
**Play Console → (your app) → Test and release → App integrity** — not your
local keystore's. If you distribute outside Play, use your own release
keystore's SHA-1 instead. Registering both is harmless.

## The checklist

At [console.cloud.google.com](https://console.cloud.google.com):

1. **Create or pick a project** (e.g. "Cashu Wallet").
2. **Enable the Drive API**: APIs & Services → Library → "Google Drive API"
   → Enable.
3. **OAuth consent screen**: APIs & Services → OAuth consent screen →
   External. Fill in app name + support/developer emails. Add the scope
   `https://www.googleapis.com/auth/drive.appdata` (the hidden app-folder
   scope — the app never asks for access to the user's real Drive files).
   - While the screen's status is **Testing**, only Google accounts you list
     as test users can grant access (up to 100) — fine for development.
   - Switch to **In production** before release so any user can enable backup.
4. **Create two Android OAuth client IDs**: APIs & Services → Credentials →
   Create credentials → OAuth client ID → type **Android**:
   - `com.cashu.me` + the release SHA-1 (from Play Console → App integrity if
     using Play App Signing, otherwise from your release keystore).
   - `com.cashu.me.debug` + your debug keystore's SHA-1. Get it with:

     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore \
       -alias androiddebugkey -storepass android | grep SHA1
     ```

     (Every developer machine has its own debug keystore, so each dev who
     wants to test the feature adds their own SHA-1 to this client.)
5. Nothing to do for **Block Store** — the second, device-transfer backup leg
   needs no Console setup at all.

No code changes result from any of this — the app is matched by package +
signature automatically.

## What users experience once this is done

Settings → Backup & Restore → Google Drive Backup → toggle on → confirm →
pick a Google account → Allow. From then on, backups run automatically after
mint changes. On a new phone: onboarding → Restore Wallet → Restore from
Google Drive → sign in → wallet found → Restore. No setup, no configuration,
nothing visible from this document ever appears to them.
