# Gemini AI Setup Guide

This app uses Google's Gemini AI for advanced hyperlocal traffic predictions and route optimization.

## Getting Your Gemini API Key

1. Go to [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Sign in with your Google account
3. Click "Create API Key"
4. Copy your API key

## Configuration

1. Open `lib/core/constants/map_constants.dart`
2. Find the line: `static const String geminiApiKey = 'YOUR_GEMINI_API_KEY';`
3. Replace `YOUR_GEMINI_API_KEY` with your actual API key

```dart
static const String geminiApiKey = 'your-actual-api-key-here';
```

## Features Enabled with Gemini AI

- **AI-Powered Traffic Predictions**: Advanced predictions based on real-time data and local patterns
- **Hyperlocal Route Optimization**: Routes optimized for local markets, vendors, and community patterns
- **Business Insights**: Peak hours and best visit times for local businesses
- **Smart Recommendations**: AI-generated tips for avoiding traffic and finding optimal routes

## Fallback Mode

If the Gemini API key is not configured, the app will use intelligent fallback predictions based on:
- Time of day analysis
- Day of week patterns
- Nearby place types
- Historical traffic patterns

The app will work perfectly fine without the API key, but AI-powered features will use fallback algorithms instead of Gemini AI.

## Security Note

⚠️ **Important**: For production, store your API key securely:
- Use environment variables
- Never commit API keys to version control
- Use Google Cloud API key restrictions
- Enable only necessary APIs in Google Cloud Console

