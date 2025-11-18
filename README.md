# Mārg Setu – Hyperlocal Mobility Copilot 🛣️

Mārg Setu is a hackathon-built Flutter app that fuses Google Maps, Firebase Auth, AI insights, and an immersive AR navigation layer to help commuters pick safer, faster and more contextual routes in Indian metros.

## Why it matters
- Gives hyperlocal route intelligence (traffic heatmaps, AI predictions, transport mode tips)
- Bridges the gap between 2D maps and the real world with an AR heads-up display
- Designed for quick validation during hackathons: opinionated architecture, ready-to-demo flows

## Feature Highlights
- 🔐 **Auth gateway** – Firebase Email/Google sign-in with personalized onboarding
- 🗺️ **Smart map canvas** – Google Maps with live traffic, nearby places, multi-stop routing
- 🤖 **Gemini-powered insights** – hyperlocal advisories, business intel, route recommendations
- 🛣️ **Route optimizer** – alternatives, ETA/distance cards, mode suggestions (car, bike, Rapido, transit)
- 📡 **Contextual widgets** – traffic heatmaps, alerts, AI overlays, real-time distance/ETA cards
- 🕶️ **AR navigation** – camera view with arrows, compass, distance chips, and navigation instructions

## Tech Stack
- Flutter 3 / Dart 3 (Material You + Google Fonts)
- Firebase (Auth, Core) + `flutterfire` config
- Google Maps Platform (Maps, Directions, Places, Roads)
- Camera, Sensors Plus, Location, Permissions for AR mode
- Clean-ish feature modules (`features/auth`, `features/map`, etc.)

## Getting Started
### Prerequisites
- Flutter ≥ 3.22 & Dart ≥ 3.0 (`flutter --version`)
- Firebase project + `google-services.json` (Android) / `GoogleService-Info.plist` (iOS/macOS)
- Google Maps API key with Maps, Directions, Places, Roads enabled
- Android/iOS devices with camera + location sensors (for AR mode)

### Setup Steps
1. **Clone & install**
   ```bash
   git clone <repo-url>
   cd google_map
   flutter pub get
   ```
2. **Configure Firebase**
   - Option A: keep the provided `lib/firebase_options.dart`
   - Option B: run `flutterfire configure` to regenerate platform configs
3. **Add Google Maps key**
   - Android: `android/app/src/main/AndroidManifest.xml` → `com.google.android.geo.API_KEY`
   - iOS: `ios/Runner/AppDelegate.swift` / `Info.plist` (if needed)
4. **Run**
   ```bash
   flutter run
   ```

### Enabling AR Navigation
1. Grant **camera** + **location** permissions when prompted.
2. Search/start a route → tap the **camera icon** on the navigation HUD/FAB.
3. Move the device to let sensors stabilize; arrows + distance bubbles appear inline with the street.

## Project Structure
```
lib/
 ├── app/                // App shell & theme
 ├── core/constants/     // Map & API constants
 ├── features/
 │   ├── auth/           // Auth screens + services
 │   └── map/
 │       ├── presentation/screens/map_screen.dart
 │       ├── presentation/screens/ar_navigation_screen.dart
 │       └── services/ (directions, traffic, AI, etc.)
 └── firebase_options.dart
```

## Hackathon Pitch
- **Problem**: Commuters struggle to trust vanilla maps during peak traffic or in unfamiliar localities.
- **Solution**: Blend AI, hyperlocal insights, and AR to deliver “look-up-and-go” navigation.
- **Demo flow**: Splash → Auth → Map (select route) → Toggle AR → Showcase insights & AI overlays.
- **Scalability**: Modular services for adding more city data sources, public transport APIs, or voice copilots.

## Testing & Quality
```bash
flutter analyze
flutter test
```

## Contributing / Future Work
- Add offline cache + download tiles
- Integrate rideshare APIs beyond Rapido
- Multilingual voice guidance + TTS cues
- Expand AR markers (POIs, alerts, friend location)

---
Built with ❤️ during a hackathon sprint – fork, remix, and keep shipping! 🚀
