# Install Seda+ on your iPhone with TestFlight

This guide uses the maintainer's identifiers. In your own fork, replace `com.majidkabir.iranseda` with your
own bundle identifier in `project.yml`, in `.github/workflows/screenshots.yml` and below, and use your own repository URL.

GitHub builds and signs the app, uploads it to Apple, and your iPhone installs it from the TestFlight app.
This is the same setup as [aula-plus](https://github.com/majidkabir/aula-plus/blob/main/TESTFLIGHT.md), without the widget and App Group.

## 1. Register the identifiers (one time)

Open https://developer.apple.com/account/resources/identifiers/list.

**App Group** (the app and its widget share data through it)
1. Click the blue **+** → **App Groups** → Continue.
2. Description: `Seda Plus`, Identifier: `com.majidkabir.iranseda` (the page adds `group.` in front) → Continue → Register.

**App ID for the app**
1. Click **+** → **App IDs** → Continue → **App** → Continue.
2. Description: `Seda Plus`, Bundle ID: **Explicit** `com.majidkabir.iranseda`.
3. Tick **App Groups** → Continue → Register.
4. Open the App ID again → next to App Groups click **Configure** → tick the group → Continue → **Save**.

**App ID for the widget**
Same again with Description `Seda Plus Widget` and Bundle ID `com.majidkabir.iranseda.widget`, with the same App Group.

## 2. Create the app in App Store Connect (one time)

1. Go to https://appstoreconnect.apple.com → **Apps** → blue **+** → **New App**.
2. Platform **iOS**, Name `Seda Plus` (any name that's free), Primary language English,
   Bundle ID: pick `Seda Plus - com.majidkabir.iranseda`, SKU `iranseda`, User access **Full Access** → **Create**.

## 3. GitHub secrets (one time)

The workflow needs the same four secrets as aula-plus. GitHub never shows a secret again, so they cannot be
copied from that repo; use the values you saved when you set it up (or generate a new API key as described in
the aula-plus guide, step 4).

On your Mac:

```sh
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Then in https://github.com/majidkabir/iranseda-ios/settings/secrets/actions → **New repository secret**:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | Key ID of the App Store Connect API key |
| `ASC_ISSUER_ID` | Issuer ID shown above the key table |
| `ASC_KEY_P8` | paste (the base64 text you copied) |
| `APPLE_TEAM_ID` | Team ID from https://developer.apple.com/account → Membership details |

## 4. Build and upload

GitHub → **Actions** → **TestFlight** → **Run workflow**. It takes about 10–15 minutes.

## 5. Install on your iPhone

1. App Store Connect → the app → **TestFlight** tab. The build appears 5–20 minutes after the workflow finishes.
2. Under **Internal Testing**, click **+** → name `Me` → add yourself as tester.
3. On the iPhone: open **TestFlight** → **Install**.

A build stops working after 90 days, so run the workflow again before then.

## If the workflow fails

| Error | Fix |
|---|---|
| `Missing repository secret …` | Add that secret (step 3). |
| `ASC_KEY_P8 is not the base64 of the .p8 file` | Redo the `base64 … \| pbcopy` command and paste again. |
| `No profiles for 'com.majidkabir.iranseda' were found` / certificate errors | The API key must have **Admin** access. |
| `No suitable application records were found` | Step 2 isn't done, or the Bundle ID there differs. |
| Upload says agreements are missing | App Store Connect → **Business** → accept the latest agreement. |
