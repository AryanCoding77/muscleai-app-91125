# Supabase Google Authentication Setup Guide

This guide will walk you through setting up Google Sign-In with Supabase in your Muscle AI React Native Expo app.

## Prerequisites

- Expo CLI installed
- Supabase account
- Google Cloud Console account
- Node.js and npm/yarn installed

## 1. Supabase Setup

### 1.1 Create a Supabase Project

1. Go to [Supabase Dashboard](https://app.supabase.com)
2. Create a new project or use an existing one
3. Note down your:
   - **Project URL**: `https://your-project-id.supabase.co`
   - **Anon Key**: Found in Settings → API

### 1.2 Configure Google Provider

1. In Supabase Dashboard, go to **Authentication** → **Providers**
2. Enable **Google** provider
3. Keep this tab open - you'll need to add Client ID and Secret later

### 1.3 Add Redirect URLs

In the Google provider settings, add these Authorized redirect URIs:
```
https://your-project-id.supabase.co/auth/v1/callback
muscle-ai://auth/callback
com.muscleai.app://auth/callback
```

## 2. Google Cloud Console Setup

### 2.1 Create OAuth 2.0 Client ID

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project or select existing
3. Enable **Google Sign-In API**:
   - Go to APIs & Services → Library
   - Search for "Google Sign-In"
   - Click Enable

### 2.2 Configure OAuth Consent Screen

1. Go to APIs & Services → OAuth consent screen
2. Choose **External** user type
3. Fill in required information:
   - App name: Muscle AI
   - User support email: your-email@example.com
   - Developer contact: your-email@example.com
4. Add scopes:
   - `email`
   - `profile`
   - `openid`
5. Add test users if in development

### 2.3 Create Credentials

1. Go to APIs & Services → Credentials
2. Click **Create Credentials** → **OAuth client ID**
3. Choose **Web application**
4. Name: "Muscle AI Web Client"
5. Add Authorized redirect URIs:
   ```
   https://your-project-id.supabase.co/auth/v1/callback
   ```
6. Save and note down:
   - **Client ID**: `your-client-id.apps.googleusercontent.com`
   - **Client Secret**: `your-client-secret`

### 2.4 Add to Supabase

1. Return to Supabase Dashboard → Authentication → Providers → Google
2. Add your Google Client ID and Client Secret
3. Save the configuration

## 3. App Configuration

### 3.1 Environment Variables

Update `.env` file in your project root:
```env
EXPO_PUBLIC_SUPABASE_URL=https://your-project-id.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=your-anon-key-here
```

### 3.2 Deep Linking (Already Configured)

The `app.json` has been configured with:
- URL scheme: `muscle-ai`
- Android package: `com.muscleai.app`
- iOS bundle identifier: `com.muscleai.app`

### 3.3 Dependencies (Already Installed)

Required packages are already installed:
```json
{
  "@supabase/supabase-js": "^2.x.x",
  "expo-auth-session": "^5.x.x",
  "expo-linking": "^6.x.x",
  "expo-web-browser": "^13.x.x",
  "react-native-url-polyfill": "^2.x.x",
  "expo-secure-store": "^13.x.x",
  "expo-linear-gradient": "^13.x.x"
}
```

## 4. Testing the Integration

### 4.1 Development Testing

1. Start the development server:
   ```bash
   npm start
   # or
   yarn start
   # or
   npx expo start
   ```

2. Test on device/emulator:
   - Press "Continue with Google" on login screen
   - Authenticate with Google account
   - Verify redirect back to app
   - Check that user session persists

### 4.2 Testing Checklist

- [ ] Login flow works on iOS Simulator
- [ ] Login flow works on Android Emulator
- [ ] Deep linking redirects back to app
- [ ] Session persists after app restart
- [ ] Sign out works from Profile/Settings
- [ ] Protected routes redirect to login when signed out
- [ ] User info displays correctly in Profile/Settings

## 5. Production Deployment

### 5.1 iOS Configuration

For production iOS builds:

1. In `app.json`, ensure bundle identifier matches Apple Developer account
2. Configure Associated Domains in Apple Developer Console
3. Add URL Types in Xcode project settings

### 5.2 Android Configuration

For production Android builds:

1. Configure SHA-1 fingerprint in Google Cloud Console:
   ```bash
   # Get production SHA-1
   keytool -list -v -keystore your-release-key.keystore
   ```
2. Add fingerprint to OAuth client in Google Console
3. Update `app.json` with proper package name

### 5.3 Build Commands

```bash
# iOS Build
eas build --platform ios

# Android Build  
eas build --platform android

# Both platforms
eas build --platform all
```

## 6. Troubleshooting

### Common Issues

**Issue: "Invalid redirect URI"**
- Solution: Ensure redirect URIs match exactly in Google Console and Supabase

**Issue: Deep link not working**
- Solution: Check URL scheme in `app.json` matches callback URL
- For iOS: May need to rebuild with `expo prebuild --clean`
- For Android: Check intent filters in `app.json`

**Issue: Session not persisting**
- Solution: Check AsyncStorage is working properly
- Ensure `expo-secure-store` is installed

**Issue: Google Sign-In opens but doesn't redirect**
- Solution: Verify redirect URIs are added to both Google Console and Supabase
- Check that bundle/package identifiers match

## 7. Security Best Practices

1. **Never commit `.env` file** - Add to `.gitignore`
2. **Use environment variables** for all sensitive data
3. **Enable Row Level Security (RLS)** in Supabase tables
4. **Validate user sessions** on sensitive operations
5. **Use HTTPS** for all API calls
6. **Implement rate limiting** for API endpoints

## 8. Code Structure

### Key Files Created/Modified

- `/src/lib/supabase.ts` - Supabase client configuration
- `/src/contexts/AuthContext.tsx` - Authentication state management
- `/src/components/AuthGuard.tsx` - Route protection component
- `/src/screens/LoginScreen.tsx` - Google Sign-In UI
- `/src/screens/ProfileScreen.tsx` - User profile with sign-out
- `/src/screens/SettingsScreen.tsx` - Settings with sign-out
- `/App.tsx` - Navigation with auth flow
- `/app.json` - Deep linking configuration
- `/.env` - Environment variables

### Authentication Flow

1. User opens app → Check session in AuthContext
2. No session → Show LoginScreen
3. User taps "Continue with Google" → Opens browser
4. Google authentication → Redirects to Supabase
5. Supabase creates session → Redirects to app via deep link
6. App receives session → Updates AuthContext
7. User authenticated → Show main app screens

## 9. Next Steps

1. **Add more auth providers** (Apple, Facebook, etc.)
2. **Implement user profiles** in Supabase database
3. **Add email verification** flow
4. **Set up password reset** functionality
5. **Implement MFA** for enhanced security
6. **Add analytics** for auth events
7. **Create admin panel** for user management

## Support

For issues or questions:
- [Supabase Documentation](https://supabase.com/docs)
- [Expo Documentation](https://docs.expo.dev)
- [Google Identity Platform](https://developers.google.com/identity)

---

Last updated: December 2024
