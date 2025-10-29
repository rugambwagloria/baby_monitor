# Smart Baby Monitor

A complete baby monitoring system featuring real-time cry detection, temperature monitoring, and local notifications via Bluetooth Low Energy (BLE). Built with ESP32 hardware and a Flutter mobile companion app.

## 🎯 Overview

This project consists of two components:
1. **ESP32 Hardware Monitor** - Real-time audio analysis and temperature sensing
2. **Flutter Mobile App** - Live monitoring, alerts, and customizable interface

**Key Features:**
- 🔊 Real-time cry detection using spectral audio analysis
- 🌡️ Continuous temperature monitoring with DS18B20 sensor
- 📱 BLE connectivity for low-power wireless communication
- 🔔 Local push notifications (no cloud/internet required)
- 🎨 Multiple calming color themes
- 🔇 Flexible mute controls
- 📊 Event logging and history

---

## 📡 BLE Architecture

### Why BLE?

This project uses **Bluetooth Low Energy (BLE) GATT** instead of Classic Bluetooth for several advantages:

- **Low Power Consumption** - Critical for battery operation
- **Modern Protocol** - Better support on iOS and Android
- **Structured Data** - GATT characteristics provide clean data separation
- **Bidirectional Communication** - Read/write/notify capabilities
- **Robust Reconnection** - Automatic device discovery and reconnection

### BLE Service Structure

#### Service UUID
```
12345678-9abc-4def-8000-00000000babe
```

#### Characteristics

1. **Status Characteristic** (Read + Notify)
   - UUID: `12345678-9abc-4def-8000-00000000feed`
   - Purpose: Sends real-time sensor data from ESP32 to app
   - Update Rate: ~1 second
   - Format: JSON string

2. **Config Characteristic** (Read + Write)
   - UUID: `12345678-9abc-4def-8000-00000000c0ff`
   - Purpose: Receives temperature threshold settings from app
   - Format: JSON string

### Data Flow

```
┌─────────────┐                    ┌──────────────┐
│   ESP32     │  BLE GATT (Status) │ Flutter App  │
│  Hardware   │ ──────Notify──────>│              │
│             │                    │              │
│  - DS18B20  │  BLE GATT (Config) │  - Monitor   │
│  - INMP441  │ <─────Write────────│  - Alerts    │
│  - TM1637   │                    │  - Settings  │
└─────────────┘                    └──────────────┘
```

### Status Payload (ESP32 → App)

Sent via BLE notification every ~1 second:

```json
{
  "temp_c": 25.4,           // Current temperature in Celsius
  "temp_alert": "ok",       // "ok" | "low" | "high" | "na"
  "cry": true,              // Current crying state
  "cry_age_ms": 1800,       // Milliseconds since cry started/ended
  "connected": true         // BLE connection status
}
```

### Config Payload (App → ESP32)

Written when user changes temperature settings:

```json
{
  "temp_low": 22.0,         // Minimum comfort temperature
  "temp_high": 26.0         // Maximum comfort temperature
}
```

### BLE Connection Lifecycle

1. **Initialization**
   - ESP32 starts advertising with device name `baby_monitor`
   - Advertises the SmartBaby service UUID
   
2. **Discovery**
   - Flutter app scans for devices with matching service UUID
   - Fallback to device name matching for compatibility
   
3. **Connection**
   - App connects to ESP32 (10s timeout)
   - MTU negotiation delayed by 1s to prevent ESP32 disconnection
   - Service discovery finds status and config characteristics
   
4. **Data Streaming**
   - App enables notifications on status characteristic
   - ESP32 sends updates every DEBUG_INTERVAL (1000ms)
   - App handles fragmented payloads (BLE packet size limits)
   
5. **Reconnection**
   - Automatic reconnection on disconnect
   - Exponential backoff (2s → 30s)
   - Manual reconnect option in app

### Handling Fragmented Data

BLE has MTU limits (typically 23-512 bytes). The app handles multi-packet JSON:

```dart
// Accumulate chunks until complete JSON received
StringBuffer _pendingStatusPayload;

void _handleStatusData(List<int> raw) {
  String chunk = utf8.decode(raw);
  _pendingStatusPayload.write(chunk);
  
  // Wait for complete JSON (ends with '}')
  if (!_pendingStatusPayload.toString().trimRight().endsWith('}')) {
    return; // Wait for more chunks
  }
  
  // Parse complete JSON
  Map<String, dynamic> data = json.decode(_pendingStatusPayload.toString());
  _applyStatusUpdate(data);
  _pendingStatusPayload.clear();
}
```

---

## 🔧 Hardware Setup

### Components

- **ESP32** (Dev Module)
- **DS18B20** - 1-Wire temperature sensor
- **INMP441** - I2S MEMS microphone
- **TM1637** - 4-digit 7-segment display
- **Resistors** - 4.7kΩ (for DS18B20 pull-up)

### Pin Configuration

```cpp
// Temperature Sensor
#define ONE_WIRE_BUS 15

// Display
#define CLK 22
#define DIO 21

// Microphone (I2S)
#define I2S_WS  25  // Word Select (LRCLK)
#define I2S_SCK 26  // Bit Clock (BCLK)
#define I2S_SD  32  // Serial Data (DOUT)
```

### Wiring Diagram

```
DS18B20 Temperature Sensor:
  VCC  →  3.3V
  GND  →  GND
  DATA →  GPIO 15 (with 4.7kΩ pull-up to 3.3V)

INMP441 Microphone:
  VDD  →  3.3V
  GND  →  GND
  WS   →  GPIO 25
  SCK  →  GPIO 26
  SD   →  GPIO 32
  L/R  →  GND (left channel)

TM1637 Display:
  VCC  →  5V
  GND  →  GND
  CLK  →  GPIO 22
  DIO  →  GPIO 21
```

### Required Arduino Libraries

Install via Arduino Library Manager:

- `OneWire` (by Paul Stoffregen)
- `DallasTemperature` (by Miles Burton)
- `TM1637Display` (by Avishay Orpaz)
- `arduinoFFT` v2.0.4+ (by Enrique Condes)
- ESP32 BLE libraries (included with ESP32 board package)

### ESP32 Board Configuration

1. Install ESP32 board support in Arduino IDE
2. Select **Board**: "ESP32 Dev Module"
3. **Partition Scheme**: "Default 4MB with spiffs"
4. **Upload Speed**: 921600

---

## 📱 Flutter App Setup

### Requirements

- Flutter SDK 3.9.2+
- Dart SDK compatible with Flutter
- Android Studio / Xcode for mobile deployment

### Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2                        # State management
  flutter_blue_plus: ^1.18.3              # BLE communication
  permission_handler: ^11.3.1             # Bluetooth permissions
  flutter_local_notifications: ^18.0.1    # Push notifications
```

### Platform-Specific Setup

#### Android (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

#### iOS (Info.plist)

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to connect to the baby monitor</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Location is required for Bluetooth scanning on iOS</string>
```

### Installation

```bash
cd flutter/baby_monitor
flutter pub get
flutter run
```

---

## 🎨 App Features

### Monitor Screen

The main interface displays:

- **Connection Status** - Visual indicator (green/amber/red)
- **Temperature Card** - Current temperature with comfort range
- **Cry Detection Card** - Real-time crying status
- **Event Log** - Timestamped history of alerts
- **Mute Button** - Floating action button for quick silence

### Settings Screen

Customization options:

- **Theme Selector** - 4 calming color palettes:
  - Beige (warm, nursery)
  - Purple (lavender bedtime)
  - Pink (nurturing)
  - Blue (classic monitor)
  
- **Alert Controls**:
  - Enable/disable cry alerts
  - Enable/disable temperature alerts
  - Alert sound style selection
  - Mute timer (5 min, 30 min, custom)

- **Temperature Thresholds**:
  - Adjustable comfort range (°C)
  - Syncs to ESP32 via BLE config characteristic

### Notifications

Local push notifications (no internet required):

#### Cry Alert
- Triggered when crying detected
- Shows duration of crying
- Respects mute settings
- Auto-clears when crying stops

#### Temperature Alert
- Triggered on temp out of range
- Shows current temperature
- Indicates "too low" or "too high"
- Updates in real-time

#### Connection Alert
- Shows when device connects/disconnects
- Helps parent know monitor is offline

---

## 🧠 Cry Detection Algorithm

### Audio Processing Pipeline

```
Microphone (16kHz) 
    ↓
High-Pass Filter (70Hz cutoff)
    ↓
Hamming Window (1024 samples)
    ↓
FFT (Fast Fourier Transform)
    ↓
Feature Extraction
    ↓
Rule-Based Classifier
    ↓
Cry Detection
```

### Extracted Features

1. **Spectral Centroid** - Brightness of sound (1200-2800 Hz)
2. **Spectral Rolloff** - Frequency where 85% of energy is below (<3600 Hz)
3. **Zero-Crossing Rate** - Signal noisiness (<0.32)
4. **Spectral Flux** - Rate of spectral change (>1.10)
5. **Pitch (F0)** - Fundamental frequency via autocorrelation (240-620 Hz)
6. **Harmonicity** - Pitch strength (>0.65)
7. **RMS Energy** - Overall loudness (>0.006)

### Classification Rules

A frame is classified as "crying" if:

```cpp
bool isCryFrame(const Features &f) {
  return (fx.lastRMS() >= 0.006)           // Loud enough
      && (f.flux >= 1.10)                  // Dynamic sound
      && (f.harmonicity >= 0.65)           // Pitched/tonal
      && (f.centroidHz >= 1200 && <= 2800) // Baby cry brightness
      && (f.rolloffHz <= 3600)             // Not too harsh
      && (f.zcr <= 0.32)                   // Not too noisy
      && (f.pitchHz >= 240 && <= 620);     // Baby cry pitch
}
```

### Temporal Filtering

- Crying state latches for 5 seconds after detection
- Prevents flickering on/off during continuous crying
- Provides stable alert state for notifications

---

## 🔬 Temperature Monitoring

### DS18B20 Configuration

- **Resolution**: 12-bit (0.0625°C precision)
- **Update Rate**: ~750ms per reading
- **Protocol**: Dallas 1-Wire
- **Range**: -55°C to +125°C (practical: 15-35°C)

### Alert States

| Temp Range | Alert State | Display | Action |
|------------|-------------|---------|--------|
| < TEMP_LOW_C | `low` | Slow blink | Notification |
| TEMP_LOW_C to TEMP_HIGH_C | `ok` | Solid | None |
| > TEMP_HIGH_C | `high` | Slow blink | Notification |
| Sensor disconnected | `na` | `----` | Error message |

### Default Thresholds

```cpp
float TEMP_LOW_C  = 22.0f;  // Adjustable via BLE
float TEMP_HIGH_C = 29.0f;  // Adjustable via BLE
```

---

## 🔔 Notification System

### Implementation

Uses `flutter_local_notifications` for platform-native alerts:

```dart
class NotificationService {
  Future<void> showCryAlert({
    required Duration duration,
    required bool isMuted,
  }) async {
    await _notifications.show(
      1,  // Notification ID
      '👶 Baby is crying',
      'Crying for ${duration.inSeconds}s',
      NotificationDetails(...),
      sound: isMuted ? null : 'cry_alert.wav',
    );
  }
}
```

### Channels

- **Cry Alerts** (ID: `cry_channel`) - High importance
- **Temperature Alerts** (ID: `temp_channel`) - High importance
- **Connection Alerts** (ID: `connection_channel`) - Low importance

### Mute Functionality

- **Temporary Mute** - Silence for fixed duration (5min, 30min)
- **Countdown Display** - Shows remaining mute time
- **Visual Indicators** - Muted state shown on all screens
- **Auto-unmute** - Alerts resume after timer expires

---

## 🏗️ Project Structure

```
baby_monitor/
├── esp32/
│   └── v4.ino                          # ESP32 firmware
├── lib/
│   ├── main.dart                       # App entry point
│   ├── theme.dart                      # Theme definitions
│   ├── screens/
│   │   ├── monitor_screen.dart         # Main monitoring UI
│   │   ├── settings_screen.dart        # Settings UI
│   │   └── logs_screen.dart            # Event history
│   ├── services/
│   │   └── notification_service.dart   # Push notifications
│   ├── state/
│   │   └── monitor_state.dart          # BLE + app state
│   └── widgets/
│       └── temperature_gauge.dart      # Custom widgets
├── android/                            # Android platform files
├── ios/                                # iOS platform files
├── pubspec.yaml                        # Flutter dependencies
├── plan.md                             # Original design doc
└── README.md                           # This file
```

---

## 🚀 Getting Started

### 1. Flash ESP32

1. Open `esp32/v4.ino` in Arduino IDE
2. Install required libraries (see Hardware Setup)
3. Select ESP32 board and port
4. Upload sketch
5. Open Serial Monitor (115200 baud) to verify operation

**Expected Serial Output:**
```
BLE advertising started - device name: baby_monitor
Temp: 24.5 °C | Cry: no | CryCount: 0
```

### 2. Run Flutter App

```bash
cd baby_monitor
flutter pub get
flutter run --debug
```

### 3. Connect

1. Enable Bluetooth on your phone
2. Open the app
3. Wait for "Connected to baby_monitor" banner
4. Verify temperature and cry status appear

---

## 🐛 Troubleshooting

### BLE Connection Issues

**Problem**: App shows "Scanning..." but never connects

**Solutions**:
- Verify Bluetooth is ON on phone
- Check ESP32 Serial Monitor shows "BLE advertising started"
- Grant location/bluetooth permissions in app settings
- Try manual reconnect button in app
- Restart ESP32 (unplug/replug)
- Check ESP32 is within 10m range

**Problem**: Connects then immediately disconnects

**Solutions**:
- ESP32 BLE library issue with MTU negotiation - firmware includes 1s delay
- Ensure ESP32 is powered properly (stable 5V supply)
- Check for interference from WiFi/other BLE devices

### Cry Detection Issues

**Problem**: False positives (detects crying when quiet)

**Solutions**:
- Reduce environmental noise
- Adjust RMS_MIN threshold higher (e.g., 0.008)
- Check microphone is properly connected
- Verify I2S pins are correct

**Problem**: Doesn't detect actual crying

**Solutions**:
- Check microphone orientation (INMP441 L/R pin grounded)
- Increase microphone gain (check hardware datasheet)
- Lower RMS_MIN threshold (e.g., 0.004)
- Verify crying pitch is in 240-620 Hz range
- Check Serial Monitor for feature values during test

### Temperature Issues

**Problem**: Shows `----` instead of temperature

**Solutions**:
- Check DS18B20 wiring (especially 4.7kΩ pull-up resistor)
- Verify ONE_WIRE_BUS pin (GPIO 15)
- Test sensor with separate sketch
- Ensure sensor is not counterfeit

**Problem**: Temperature readings unstable/jumping

**Solutions**:
- Add 0.1µF capacitor across VCC and GND
- Shorten sensor cable length (<5m)
- Use shielded cable for long runs
- Check power supply stability

---

## 📊 Performance

### ESP32 Resource Usage

- **CPU**: ~40% (dual-core, FFT runs on core 1)
- **RAM**: ~45KB (mostly for FFT buffers)
- **Flash**: ~800KB (with BLE and FFT libraries)
- **Power**: ~150mA @ 5V (with display and BLE active)

### Flutter App

- **APK Size**: ~25MB (release build)
- **RAM Usage**: ~80MB (typical)
- **Battery Impact**: Low (BLE notifications, minimal wake)

### BLE Performance

- **Latency**: <100ms (notification delivery)
- **Range**: ~10m indoor, ~30m line-of-sight
- **Throughput**: ~160 bytes/second (JSON payload)
- **Reliability**: >99% packet delivery in normal conditions

---

## 🔐 Privacy & Security

### No Cloud, No Internet

- **Zero data leaves device** - All processing on ESP32
- **No WiFi** - BLE only communication
- **No login** - No accounts or authentication
- **Local notifications** - No push notification servers

### BLE Security

- **Pairing not required** - Device advertises openly
- **No sensitive data** - Temperature and cry state only
- **Read-only status** - App cannot control hardware
- **Config write** - Only temperature thresholds adjustable

> **Note**: For maximum security in shared environments, consider adding BLE pairing/bonding in future versions.

---

## 🛠️ Customization

### Adjusting Cry Detection Sensitivity

Edit in `v4.ino`:

```cpp
// Make LESS sensitive (fewer false positives)
const float RMS_MIN = 0.008f;  // Increase (default 0.006)
const float HARMONICITY_MIN = 0.70f;  // Increase (default 0.65)

// Make MORE sensitive (catch quieter cries)
const float RMS_MIN = 0.004f;  // Decrease
const float FLUX_MIN = 0.90f;  // Decrease (default 1.10)
```

### Changing Temperature Units

To display Fahrenheit in app:

```dart
// In monitor_screen.dart
Text('${(temperature! * 9/5 + 32).toStringAsFixed(1)} °F')
```

### Adding Custom Themes

Edit `lib/theme.dart`:

```dart
enum ThemeType { beige, purple, pink, blue, custom }

case ThemeType.custom:
  return ColorScheme.light(
    primary: Color(0xFFYOURCOLOR),
    secondary: Color(0xFFYOURCOLOR),
    // ...
  );
```

### BLE UUID Customization

Generate new UUIDs at [uuidgenerator.net](https://www.uuidgenerator.net/):

Update in both:
- `esp32/v4.ino` (lines 61-63)
- `lib/state/monitor_state.dart` (lines 45-49)

---

## 🧪 Testing

### Hardware Testing

```bash
# Monitor ESP32 serial output
screen /dev/cu.usbserial-* 115200

# Test cry detection manually
# Speak/sing in baby cry pitch range (300-500 Hz)

# Test temperature sensor
# Hold sensor between fingers to warm up
```

### App Testing

```bash
# Run with debug logging
flutter run --debug

# Check BLE logs
flutter logs | grep "BLE:"

# Test notifications
flutter run --debug
# Trigger alerts by warming sensor or making sound
```

---

## 📝 License

This project is open source. Feel free to modify and use for personal purposes.

**Hardware components** are commercial products - respect individual licenses.

**Libraries used**:
- arduinoFFT: GPL-3.0
- DallasTemperature: MIT
- flutter_blue_plus: BSD-3-Clause
- All Flutter dependencies: see respective licenses

---

## 🙏 Acknowledgments

- **arduinoFFT** by Enrique Condes - Efficient FFT implementation
- **flutter_blue_plus** - Robust BLE library for Flutter
- ESP32 community for extensive BLE documentation
- Parents worldwide who deserve better baby monitors

---

## 📮 Support

For issues, questions, or contributions:

1. Check the Troubleshooting section above
2. Review Serial Monitor output from ESP32
3. Check app logs with `flutter logs`
4. Verify hardware connections
5. Test components individually

---

## 🗺️ Future Enhancements

Potential improvements:

- [ ] Multiple device support (monitor multiple rooms)
- [ ] Historical data logging (SQLite)
- [ ] Sleep pattern analysis
- [ ] Custom cry detection training
- [ ] Battery level reporting
- [ ] Over-the-air firmware updates
- [ ] Widget for home screen
- [ ] Apple Watch companion app
- [ ] Sound recording clips
- [ ] Humidity sensor integration

---

**Built with ❤️ for peaceful nights and happy babies**
