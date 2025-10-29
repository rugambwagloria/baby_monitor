/*
  Smart Baby Monitor — Spectral (Stable)
  ESP32 + DS18B20 + INMP441 (I2S) + TM1637 + Bluetooth + BLE GATT
  arduinoFFT v2.0.4 (templated API)
*/

#include <Arduino.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <TM1637Display.h>
#include "BluetoothSerial.h"
#include "driver/i2s.h"
#include <arduinoFFT.h>

// NEW: BLE includes
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define DEBUG true          // toggle all debug output
#define DEBUG_INTERVAL 1000 // milliseconds between full debug prints

// ===== PINS =====
#define ONE_WIRE_BUS 15
#define CLK 22
#define DIO 21
#define I2S_WS 25         // LRCLK/WS
#define I2S_SCK 26        // BCLK
#define I2S_SD 32         // DOUT from INMP441

// ===== LIMITS (can be adjusted via BLE) =====
float TEMP_LOW_C  = 22.0f;
float TEMP_HIGH_C = 29.0f;

// ===== AUDIO CONFIG =====
static const int SR       = 16000;
static const int N        = 1024;
static const int HOP      = N / 2;
static const i2s_port_t I2S_PORT = I2S_NUM_0;

// ===== DATA-DRIVEN RULES =====
const float PITCH_MIN_HZ    = 240.0f;
const float PITCH_MAX_HZ    = 620.0f;
const float HARMONICITY_MIN = 0.65f;
const float CENTROID_MIN_HZ = 1200.0f;
const float CENTROID_MAX_HZ = 2800.0f;
const float ROLLOFF_MAX_HZ  = 3600.0f;
const float ZCR_MAX         = 0.32f;
const float FLUX_MIN        = 1.10f;
const float RMS_MIN         = 0.006f;
const int   CRY_CONSEC_FRAMES = 1;

// ===== OBJECTS =====
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);
TM1637Display display(CLK, DIO);
BluetoothSerial SerialBT;

// NEW: BLE globals
// You can generate your own UUIDs later if you want; these are placeholders.
#define SMARTBABY_SERVICE_UUID        "12345678-9abc-4def-8000-00000000babe"
#define SMARTBABY_STATUS_CHAR_UUID    "12345678-9abc-4def-8000-00000000feed"
#define SMARTBABY_CONFIG_CHAR_UUID    "12345678-9abc-4def-8000-00000000c0ff"

BLEServer*        bleServer         = nullptr;
BLECharacteristic* statusCharacteristic = nullptr;
BLECharacteristic* configCharacteristic = nullptr;
bool bleClientConnected = false;

// ===== STATE =====
int  cryCounter = 0;
bool cryAlert   = false;

// We track lastCryTime in loop as static. We forward declare here for BLE helper.
static unsigned long lastCryTime_global = 0;

// ===== FEATURES =====
struct Features {
  float centroidHz, rolloffHz, zcr, flux, pitchHz, harmonicity;
};

class MemsFeatureExtractor {
public:
  bool begin() {
    i2s_config_t cfg = {};
    cfg.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX);
    cfg.sample_rate = SR;
    cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT;
    cfg.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
    cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
    cfg.intr_alloc_flags = 0;
    cfg.dma_buf_count = 8;
    cfg.dma_buf_len   = 256;
    cfg.use_apll = false;
    cfg.tx_desc_auto_clear = false;
    cfg.fixed_mclk = 0;
    if (i2s_driver_install(I2S_PORT, &cfg, 0, nullptr) != ESP_OK) return false;

    i2s_pin_config_t pins = {};
    pins.bck_io_num   = I2S_SCK;
    pins.ws_io_num    = I2S_WS;
    pins.data_out_num = I2S_PIN_NO_CHANGE;
    pins.data_in_num  = I2S_SD;
    if (i2s_set_pin(I2S_PORT, &pins) != ESP_OK) return false;

    if (i2s_set_clk(I2S_PORT, SR, I2S_BITS_PER_SAMPLE_32BIT, I2S_CHANNEL_MONO) != ESP_OK) return false;
    i2s_zero_dma_buffer(I2S_PORT);

    memset(_prevMag, 0, sizeof(_prevMag));
    _lastRms = 0.0f;
    return true;
  }

  // Return true when a feature frame is ready
  bool next(Features &out) {
    if (!readSamples(_frame + _writePos, HOP)) return false;
    _writePos += HOP;
    if (_writePos < N) return false;

    // High-pass + manual Hamming
    for (int i = 0; i < N; ++i) {
      float x = highpass(_frame[i]);
      _vReal[i] = x * hamming(i, N);
      _vImag[i] = 0.0;
    }

    // FFT windowing and magnitude
    _fft.windowing(FFTWindow::Rectangle, FFTDirection::Forward);
    _fft.compute(FFTDirection::Forward);
    _fft.complexToMagnitude();

    const int bins = N / 2;
    out.centroidHz   = spectralCentroid(_vReal, bins);
    out.rolloffHz    = spectralRolloff(_vReal, bins, 0.85f);
    out.zcr          = zeroCrossingRate(_frame, N);
    out.flux         = spectralFlux(_vReal, bins);
    pitchAndHarm(_frame, N, SR, 200.0f, 800.0f, out.pitchHz, out.harmonicity);

    // Slide 50 percent overlap
    memmove(_frame, _frame + HOP, (N - HOP) * sizeof(float));
    _writePos = N - HOP;
    return true;
  }

  float lastRMS() const { return _lastRms; }

private:
  bool readSamples(float *dst, int count) {
    size_t br = 0;
    const TickType_t to = 10 / portTICK_PERIOD_MS;
    double acc = 0.0;
    for (int i = 0; i < count; ++i) {
      int32_t s32 = 0;
      if (i2s_read(I2S_PORT, &s32, sizeof(s32), &br, to) != ESP_OK || br != sizeof(s32)) {
        return false;
      }
      int32_t s24 = s32 >> 8;
      float v = (float)s24 / 8388608.0f;
      dst[i] = v;
      acc += (double)v * (double)v;
    }
    _lastRms = sqrt(acc / count);
    return true;
  }

  float highpass(float x) {
    const float fc = 70.0f, dt = 1.0f / SR, RC = 1.0f / (2.0f * PI * fc);
    const float a = RC / (RC + dt);
    float y = a * (_hpPrev + x - _xPrev);
    _hpPrev = y; _xPrev = x;
    return y;
  }

  static inline float hamming(int n, int N) {
    return 0.54f - 0.46f * cosf(2.0f * PI * n / (N - 1));
  }

  float spectralCentroid(const double *mag, int bins) {
    double num = 0.0, den = 0.0;
    for (int k = 1; k < bins; ++k) { double f = (double)k * SR / N; num += f * mag[k]; den += mag[k]; }
    return den > 0.0 ? (float)(num / den) : 0.0f;
  }

  float spectralRolloff(const double *mag, int bins, float prop) {
    double total = 0.0; for (int k = 0; k < bins; ++k) total += mag[k];
    double target = prop * total, acc = 0.0;
    for (int k = 0; k < bins; ++k) { acc += mag[k]; if (acc >= target) return (float)k * SR / N; }
    return 0.0f;
  }

  float spectralFlux(const double *mag, int bins) {
    double flux = 0.0;
    for (int k = 0; k < bins; ++k) { double d = mag[k] - _prevMag[k]; if (d > 0.0) flux += d; _prevMag[k] = mag[k]; }
    return (float)flux;
  }

  float zeroCrossingRate(const float *x, int n) {
    int zc = 0; for (int i = 1; i < n; ++i) { bool a = x[i-1] >= 0.0f, b = x[i] >= 0.0f; if (a != b) zc++; }
    return (float)zc / (float)n;
  }

  void pitchAndHarm(const float *x, int n, int sr, float fmin, float fmax,
                    float &f0Hz, float &harm) {
    static float buf[N];
    double mean = 0.0; for (int i = 0; i < n; ++i) mean += x[i]; mean /= n;
    for (int i = 0; i < n; ++i) buf[i] = x[i] - (float)mean;

    int lagMin = (int)(sr / fmax), lagMax = (int)(sr / fmin);
    if (lagMax > n - 1) lagMax = n - 1;

    double e0 = 0.0; for (int i = 0; i < n; ++i) e0 += buf[i] * buf[i];

    double best = 0.0; int bestLag = 0;
    for (int L = lagMin; L <= lagMax; ++L) {
      double r = 0.0, eL = 0.0;
      for (int i = 0; i + L < n; ++i) { r += buf[i] * buf[i + L]; eL += buf[i + L] * buf[i + L]; }
      double rn = r / sqrt((e0 + 1e-9) * (eL + 1e-9));
      if (rn > best) { best = rn; bestLag = L; }
    }
    f0Hz = bestLag > 0 ? (float)sr / (float)bestLag : 0.0f;
    harm = (float)best;
  }

private:
  float  _frame[N] = {0};
  int    _writePos = 0;
  double _vReal[N];
  double _vImag[N];
  ArduinoFFT<double> _fft = ArduinoFFT<double>(_vReal, _vImag, N, SR);
  double _prevMag[N / 2] = {0};
  float  _hpPrev = 0.0f, _xPrev = 0.0f;
  float  _lastRms = 0.0f;
};

MemsFeatureExtractor fx;

bool isCryFrame(const Features &f) {
  bool rmsOK   = (fx.lastRMS() >= RMS_MIN);
  bool fluxOK  = (f.flux >= FLUX_MIN);
  bool harmOK  = (f.harmonicity >= HARMONICITY_MIN);
  bool centroidOK = (f.centroidHz >= CENTROID_MIN_HZ &&
                     f.centroidHz <= CENTROID_MAX_HZ);
  bool rolloffOK  = (f.rolloffHz  <= ROLLOFF_MAX_HZ);
  bool zcrOK      = (f.zcr <= ZCR_MAX);

  bool pitchKnown  = (f.pitchHz > 0.0f);
  bool pitchInBand = (f.pitchHz >= PITCH_MIN_HZ &&
                      f.pitchHz <= PITCH_MAX_HZ);
  bool pitchOK = (!pitchKnown) || pitchInBand;

  return rmsOK
      && fluxOK
      && harmOK
      && centroidOK
      && rolloffOK
      && zcrOK
      && pitchOK;
}

// NEW: BLE server callbacks to track connections
class SmartBabyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    bleClientConnected = true;
    Serial.println("BLE client connected");
  }
  void onDisconnect(BLEServer* pServer) override {
    bleClientConnected = false;
    Serial.println("BLE client disconnected - restarting advertising");
    // Important: restart advertising immediately for reconnection
    delay(500); // Small delay to ensure clean disconnect
    BLEDevice::startAdvertising();
  }
};

// NEW: Config characteristic callbacks to receive temperature settings
class ConfigCharCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String value = pCharacteristic->getValue();
    if (value.length() > 0) {
      Serial.print("Config received: ");
      Serial.println(value);
      
      // Parse JSON: {"temp_low":20.0,"temp_high":26.0}
      // Simple parsing without JSON library
      int lowPos = value.indexOf("\"temp_low\":");
      int highPos = value.indexOf("\"temp_high\":");
      
      if (lowPos != -1) {
        lowPos += 11; // skip "temp_low":
        float newLow = value.substring(lowPos).toFloat();
        if (newLow >= 15.0f && newLow <= 30.0f) {
          TEMP_LOW_C = newLow;
          Serial.print("Updated TEMP_LOW_C to: ");
          Serial.println(TEMP_LOW_C);
        }
      }
      
      if (highPos != -1) {
        highPos += 12; // skip "temp_high":
        float newHigh = value.substring(highPos).toFloat();
        if (newHigh >= 20.0f && newHigh <= 35.0f) {
          TEMP_HIGH_C = newHigh;
          Serial.print("Updated TEMP_HIGH_C to: ");
          Serial.println(TEMP_HIGH_C);
        }
      }
    }
  }
};

// NEW: helper to push JSON status into BLE characteristic
void bleUpdateStatus(float tempC,
                     bool tempValid,
                     bool tempAlert,
                     bool cryAlert,
                     unsigned long lastCryTime,
                     unsigned long nowMs) {
  if (!statusCharacteristic) return;

  // compute age since last cry for app display
  unsigned long ageMs = (nowMs >= lastCryTime) ? (nowMs - lastCryTime) : 0;

  // temp_alert string
  const char* tempState = "ok";
  if (!tempValid) {
    tempState = "na";
  } else if (tempC < TEMP_LOW_C) {
    tempState = "low";
  } else if (tempC > TEMP_HIGH_C) {
    tempState = "high";
  } else {
    tempState = "ok";
  }

  // cry boolean tells the app to show "crying" or "recent crying"
  // we simply expose cryAlert latch state
  const bool cryState = cryAlert;

  // small JSON. keep under ~128 bytes for safety.
  // Example:
  // {"temp_c":25.4,"temp_alert":"ok","cry":true,"cry_age_ms":1800,"connected":true}
  char payload[160];
  snprintf(payload, sizeof(payload),
           "{\"temp_c\":%.1f,\"temp_alert\":\"%s\",\"cry\":%s,"
           "\"cry_age_ms\":%lu,\"connected\":%s}",
           tempValid ? tempC : 0.0f,
           tempState,
           cryState ? "true" : "false",
           (unsigned long)ageMs,
           bleClientConnected ? "true" : "false");

  statusCharacteristic->setValue((uint8_t*)payload, strlen(payload));

  // Only notify if we have a connected client
  if (bleClientConnected) {
    statusCharacteristic->notify();
  }
}

// ===== SETUP =====
void setup() {
  Serial.begin(115200);
  delay(200);

  // SerialBT.begin("SmartBabyMonitor");  // Commented out for BLE debugging

  // NEW: set up BLE GATT
  BLEDevice::init("baby_monitor");   // advertised BLE name
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new SmartBabyServerCallbacks());

  BLEService *service = bleServer->createService(SMARTBABY_SERVICE_UUID);

  statusCharacteristic = service->createCharacteristic(
      SMARTBABY_STATUS_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ   |
      BLECharacteristic::PROPERTY_NOTIFY
  );

  // descriptor 2902 so phone can enable notify
  statusCharacteristic->addDescriptor(new BLE2902());

  // NEW: Config characteristic for receiving temperature thresholds
  configCharacteristic = service->createCharacteristic(
      SMARTBABY_CONFIG_CHAR_UUID,
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_READ
  );
  configCharacteristic->setCallbacks(new ConfigCharCallbacks());
  
  // Set initial config value
  char initialConfig[80];
  snprintf(initialConfig, sizeof(initialConfig),
           "{\"temp_low\":%.1f,\"temp_high\":%.1f}",
           TEMP_LOW_C, TEMP_HIGH_C);
  configCharacteristic->setValue(initialConfig);

  service->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SMARTBABY_SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // Functions that help with iPhone connections
  pAdvertising->setMinPreferred(0x12);
  
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started - device name: baby_monitor");

  sensors.begin();
  sensors.setResolution(12);
  display.setBrightness(0x0f);

  if (!fx.begin()) {
    Serial.println("[I2S] init failed");
    while (1) delay(1000);
  }
}

// ===== MAIN LOOP =====
void loop() {
  // persistent state across calls
  static unsigned long lastCryTime = 0;     // ms when we last saw crying
  static unsigned long lastBlink   = 0;
  static bool blinkState           = false;
  static unsigned long lastDebugOut = 0;
  static unsigned long lastAdvertCheck = 0;

  unsigned long nowMs = millis();

  // Check advertising status every 30 seconds when disconnected
  if (!bleClientConnected && (nowMs - lastAdvertCheck >= 30000)) {
    lastAdvertCheck = nowMs;
    Serial.println("No client connected - ensuring advertising is active");
    BLEDevice::startAdvertising();
  }

  // 1. read temperature
  sensors.requestTemperatures();
  float tempC = sensors.getTempCByIndex(0);
  bool tempValid = (tempC != DEVICE_DISCONNECTED_C);

  // 2. audio features and cry state
  Features f;
  bool haveFeatures = fx.next(f);

  if (haveFeatures) {
    if (isCryFrame(f)) {
      cryCounter++;
      lastCryTime = millis();     // refresh latch time whenever cry frame
    } else {
      cryCounter = 0;
    }
  }

  // 3. latch crying for 5 seconds
  const unsigned long CRY_LATCH_MS = 5000;
  cryAlert = (nowMs - lastCryTime < CRY_LATCH_MS);
  lastCryTime_global = lastCryTime; // expose to BLE helper

  // 4. build display digits
  uint8_t digits[4];
  bool tempAlert = false;

  if (tempValid) {
    int tempInt = (int)(tempC * 10); // 25.3 C -> 253
    digits[0] = display.encodeDigit((tempInt / 100) % 10);
    digits[1] = display.encodeDigit((tempInt / 10) % 10) | 0x80;
    digits[2] = display.encodeDigit(tempInt % 10);
    digits[3] = 0;

    if (tempC < TEMP_LOW_C || tempC > TEMP_HIGH_C) {
      tempAlert = true;
    }
  } else {
    for (int i = 0; i < 4; i++) {
      digits[i] = 0x40; // ---- sensor missing
    }
  }

  // 5. blink timing
  unsigned long intervalFast = 300;
  unsigned long intervalSlow = 1000;
  unsigned long activeInterval = 0;

  if (cryAlert) {
    activeInterval = intervalFast;
  } else if (tempAlert) {
    activeInterval = intervalSlow;
  } else {
    activeInterval = 0;
  }

  if (activeInterval > 0 && (nowMs - lastBlink >= activeInterval)) {
    blinkState = !blinkState;
    lastBlink  = nowMs;
  }

  // 6. final digits for display
  uint8_t outDigits[4];
  for (int i = 0; i < 4; i++) {
    outDigits[i] = digits[i];
  }

  if (cryAlert) {
    if (!blinkState) {
      outDigits[0] = 0;
      outDigits[1] = 0;
      outDigits[2] = 0;
      outDigits[3] = 0;
    }
  } else if (tempAlert) {
    if (blinkState) {
      if (tempC < TEMP_LOW_C) {
        outDigits[0] = 0;
      } else if (tempC > TEMP_HIGH_C) {
        outDigits[2] = 0;
      }
    }
  }

  display.setSegments(outDigits);

  // 7. BLE status update once per second alongside debug
  if (nowMs - lastDebugOut >= DEBUG_INTERVAL) {
    lastDebugOut = nowMs;

#if DEBUG
    // USB serial debug
    Serial.print("Temp:");
    if (tempValid) Serial.print(tempC, 1); else Serial.print("NA");
    Serial.print(" °C | Cry:");
    Serial.print(cryAlert ? "YES" : "no");
    Serial.print(" | CryCount:");
    Serial.print(cryCounter);
    Serial.print(" | TimeSinceCry(ms):");
    Serial.print(nowMs - lastCryTime);
    Serial.print(" | TempAlert:");
    Serial.print(tempAlert ? "YES" : "no");
    Serial.println();

    // Classic Bluetooth debug - commented out
    // if (SerialBT.hasClient()) {
    //   SerialBT.print("Temp:");
    //   if (tempValid) SerialBT.print(tempC, 1); else SerialBT.print("NA");
    //   SerialBT.print(" °C | Cry:");
    //   SerialBT.print(cryAlert ? "YES" : "no");
    //   SerialBT.print(" | CryCount:");
    //   SerialBT.print(cryCounter);
    //   SerialBT.print(" | TimeSinceCry(ms):");
    //   SerialBT.print(nowMs - lastCryTime);
    //   SerialBT.print(" | TempAlert:");
    //   SerialBT.print(tempAlert ? "YES" : "no");
    //   SerialBT.println();
    //   SerialBT.flush();
    // }
#endif

    // NEW: BLE notify to phone
    bleUpdateStatus(
      tempC,
      tempValid,
      tempAlert,
      cryAlert,
      lastCryTime,
      nowMs
    );
  }

  // 8. tiny delay
  delay(10);
}
