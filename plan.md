# Baby Monitor Companion App: Plan

## 1. Goal

Mobile companion app for the ESP32 based baby monitor.  
The app connects over Bluetooth Low Energy.  
It shows live temperature and cry state, provides alert notifications, and lets the user pick a soothing visual theme.

No cloud. No login. Local only.

The app must be usable by a half-asleep parent at 03:17.

---

## 2. Core Features

1. Live monitor view  
   - Current room / baby temperature in °C  
   - Comfort state: OK, Low, High  
   - Cry state: Crying, Recently crying, Calm  
   - Time since last cry  
   - Connection status to the device  
   - Recent alert events

2. Alerts  
   - Local phone audio notification when baby is crying  
   - Local phone audio notification when temperature is out of range  
   - Respect mute / quiet mode options

3. Theme customisation  
   - Parent can switch between calm palettes:  
     Beige (default)  
     Purple  
     Pink  
     Blue  
   - Layout stays the same; only colours / accents change

4. BLE status and control  
   - Show Connected, Reconnecting, Disconnected  
   - Manual reconnect / rescan button

5. Settings  
   - Theme picker  
   - Enable or disable cry alerts  
   - Enable or disable temperature alerts  
   - Choose alert sound style  
   - Temporary mute window  
   - Device info

---

## 3. Screens

### 3.1 Monitor Screen (Home)
This is tab one and also initial landing screen.

Elements in order:

1. ConnectionBanner  
   - "Connected to baby_monitor" with coloured dot  
   - State colours:  
     Green: connected  
     Amber: reconnecting  
     Red: disconnected  
   - Tap: opens BLE scan / reconnect modal

2. TemperatureCard  
   - Big number: e.g. `25.4 °C`  
   - Subtext: `Comfort 22–26 °C`  
   - Status chip: OK / Low / High  
   - Card border / accent colour reflects state:  
     normal: neutral  
     low temp: cool blue tint  
     high temp: warm red tint

3. CryCard  
   - Headline:  
     Crying  
     Recently crying  
     Calm  
   - Subtext:  
     `Last cry: 2 s ago`  
     or  
     `No cry in last 5 min`  
   - Crying state tints the card background softly (not harsh red)  
   - Small animated icon next to Crying (pulsing waveform / speaker)

4. RecentEventsList  
   - Scrollable list of recent events, latest first, e.g.:  
     `[02:14] Cry detected`  
     `[02:14] Nursery temperature high 27.1 °C`  
     `[02:20] Cry cleared`  
   - This provides context: what just happened while I was away

5. Mute Floating Button  
   - Circular FAB at bottom right  
   - Icon: bell or bell-off  
   - Tap to mute alerts for a short window  
   - When muted, show a small chip "Muted 5 min" somewhere on screen

Behaviour:
- If disconnected:  
  - cards are greyed  
  - show placeholder values `--.- °C`, `Status: offline`  
  - show banner "Not connected. Scanning..." with spinner

Typography:
- Large readable main values (temperature, cry state)  
- Small neutral supporting text  
- No dense technical text

Accessibility:
- Use clear, warm wording:  
  "Crying now"  
  "No recent crying"  
  "Too hot"  
  "Too cold"  
  "Back in range"

---

### 3.2 Settings Screen (Tab two)

Sections (ListView style):

Device
- Device name: `baby_monitor`
- Connection status
- "Reconnect / Scan" button

Appearance
- Theme colour: Beige (default), Purple, Pink, Blue
- Displayed as colour chips or radio tiles
- This updates the global app theme immediately

Notifications
- Cry alerts: toggle
- Temperature alerts: toggle
- Alert sound: dropdown (Soft chime, Standard, Loud)
- "Mute all alerts" toggle or timed mute

Silence Window
- "Mute alerts for:" Off / 5 min / 30 min
- Selecting sets mute countdown and reflects in Monitor mute state

About
- App version
- Firmware version (read from BLE when available)

---

## 4. Colour Themes

There is no dark mode vs light mode.  
Instead: the app always uses a light base but you can swap accent palette.

ThemeType enum:
```dart
enum ThemeType { beige, purple, pink, blue }
```

Palettes:

Beige (default)
- primary: #F5E6CC
- secondary: #8C6E54
- background: #FBF8F3
- mood: warm, natural, nursery lamp

Purple
- primary: #D6C9F0
- secondary: #8066B0
- background: #F6F3FA
- mood: calm bedtime, lavender

Pink
- primary: #FFE0E9
- secondary: #D6336C
- background: #FFF6F9
- mood: nurturing, soft, reassuring

Blue
- primary: #CCE5FF
- secondary: #2A75C8
- background: #F5FAFF
- mood: clean, airy, classic baby monitor

---

## 5. BLE Data Contract

The ESP32 should expose a BLE GATT service `SmartBabyService` with one characteristic `status` that notifies once per second.

Payload format: JSON string for development clarity.

Example:
```json
{
  "temp_c": 25.4,
  "temp_alert": "ok",   // "ok", "low", "high"
  "cry": true,
  "cry_age_ms": 1800,
  "connected": true
}
```

---

## 6. Alerts and Notifications

Goal: the phone yells at the parent when necessary.

Rules:
- When `cry` goes from false to true:
  - if cry alerts enabled
  - if not muted
  - play cry alert sound and show local notification

- When `temp_alert` changes between ok and non-ok:
  - if temp alerts enabled
  - and not muted
  - play temperature alert sound

Debounce logic:
- Do not spam sound continuously every second.
- Only trigger again if:
  - state changes (calm → crying, ok temp → high temp), or
  - at least N seconds passed since last alert of that type.

---

## 7. Build Order

1. Static UI with beige theme  
2. Theme switching (beige, purple, pink, blue)  
3. BLE connection and JSON parsing  
4. Live updates in Monitor screen  
5. Notifications and sound feedback  
6. Mute system and event log  
7. Polish and packaging
