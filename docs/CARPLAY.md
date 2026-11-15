# CarPlay

The code for a CarPlay audio app is in `IranSeda/Core/CarPlay.swift`: three tabs (favourites, stations,
recently played) and the system Now Playing screen. The scene is declared in `project.yml`.

It stays invisible in the car until the app carries Apple's CarPlay audio entitlement. Apple grants that
per developer account, on request.

## Turn it on

1. Request the entitlement at https://developer.apple.com/contact/carplay/ and choose **Audio**.
   Apple replies by email; it can take days or weeks.
2. When granted, open https://developer.apple.com/account/resources/identifiers/list, open the app's
   App ID, tick **CarPlay Audio App** under Additional Capabilities, and save.
3. Add the entitlement to the app target in `project.yml`:

   ```yaml
       entitlements:
         path: IranSeda/IranSeda.entitlements
         properties:
           com.apple.developer.carplay-audio: true
   ```

4. Build and upload as usual.

Adding step 3 before Apple has granted the entitlement makes signing fail, so it is left out of the
repository on purpose.

## Try it without a car

Xcode's simulator has a CarPlay window: **I/O → External Displays → CarPlay**. The simulator does not
check the entitlement, so step 3 alone is enough there.
