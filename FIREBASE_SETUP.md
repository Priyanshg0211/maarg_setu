# Firebase Setup Instructions

To enable Google Sign-In with Firebase, you need to complete the following steps:

## 1. Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project" and follow the setup wizard
3. Enable Google Analytics (optional)

## 2. Add Android App

1. In Firebase Console, click "Add app" and select Android
2. Register your app with package name (check `android/app/build.gradle.kts` for `applicationId`)
3. Download `google-services.json`
4. Place it in `android/app/` directory
5. Add the following to `android/build.gradle.kts` (project-level):
   ```kotlin
   dependencies {
       classpath("com.google.gms:google-services:4.4.0")
   }
   ```
6. Add to `android/app/build.gradle.kts` (app-level) at the bottom:
   ```kotlin
   apply plugin: 'com.google.gms.google-services'
   ```

## 3. Add iOS App (if needed)

1. In Firebase Console, click "Add app" and select iOS
2. Register your app with Bundle ID (check `ios/Runner/Info.plist`)
3. Download `GoogleService-Info.plist`
4. Place it in `ios/Runner/` directory
5. Add to `ios/Runner/Info.plist`:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleTypeRole</key>
           <string>Editor</string>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>YOUR_REVERSED_CLIENT_ID</string>
           </array>
       </dict>
   </array>
   ```
   (Get REVERSED_CLIENT_ID from GoogleService-Info.plist)

## 4. Enable Google Sign-In

1. In Firebase Console, go to Authentication > Sign-in method
2. Enable "Google" sign-in provider
3. Add your support email
4. Save

## 5. Get SHA-1 Fingerprint (Android)

Run this command to get your SHA-1:
```bash
cd android
./gradlew signingReport
```

Copy the SHA-1 fingerprint and add it to Firebase Console:
- Go to Project Settings > Your Android App
- Add SHA certificate fingerprint

## 6. Install Dependencies

Run:
```bash
flutter pub get
```

## 7. Run the App

```bash
flutter run
```

The app will now show a login screen with Google Sign-In button. After signing in, you'll be redirected to the map screen.

