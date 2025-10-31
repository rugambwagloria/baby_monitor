/*
 * Smart Baby Monitor — IMMEDIATE BEEP AT 29.1°C + ESCALATING + CRY BEEP
 * ESP32 + DS18B20 + INMP441 + TM1637 + BLE + Buzzer
 */

#include <Arduino.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <TM1637Display.h>
#include "driver/i2s.h"
#include <arduinoFFT.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define DEBUG true
#define DEBUG_INTERVAL 1000

// ===== PINS =====
#define ONE_WIRE_BUS 15
#define CLK 22
#define DIO 21
#define I2S_WS 25
#define I2S_SCK 26
#define I2S_SD 32
#define BUZZER_PIN 18

// ===== TEMP ALERT CONFIG (CHANGEABLE VIA BLE) =====
float TEMP_HIGH_THRESHOLD = 29.1f;  // Now a variable!
float TEMP_HYSTERESIS     = 0.3f;
#define TEMP_MAX_C          35.0f

// ===== BUZZER CONFIG =====
#define CRY_BUZZER_FREQ     3000
#define TEMP_BASE_FREQ      1500
#define TEMP_MAX_FREQ       4000
#define BASE_BEEP_DURATION  150UL
#define MIN_BEEP_INTERVAL   300UL
#define MAX_BEEP_INTERVAL   2000UL

// ===== AUDIO CONFIG =====
static const int SR       = 16000;  // Fixed: was missing 'static const int'
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

// ===== BUZZER HELPERS =====
inline void buzzerTone(uint16_t freq) { tone(BUZZER_PIN, freq); }
inline void buzzerOff()               { noTone(BUZZER_PIN); }

// ===== NON-BLOCKING BEEP SYSTEM =====
static unsigned long beepStart = 0;
static bool beepActive = false;
static uint16_t currentFreq = 0;
static unsigned long nextBeepTime = 0;
static bool isTempBeeping = false;

void triggerBeep(uint16_t freq, unsigned long duration) {
  if (!beepActive) {
    currentFreq = freq;
    buzzerTone(freq);
    beepStart = millis();
    beepActive = true;
  }
}

void updateBeep() {
  if (beepActive && millis() - beepStart >= BASE_BEEP_DURATION) {
    buzzerOff();
    beepActive = false;
  }
}

// ===== OBJECTS =====
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);
TM1637Display display(CLK, DIO);

// BLE globals
#define SMARTBABY_SERVICE_UUID        "12345678-9abc-4def-8000-00000000babe"
#define SMARTBABY_STATUS_CHAR_UUID    "12345678-9abc-4def-8000-00000000feed"
#define SMARTBABY_CONFIG_CHAR_UUID    "12345678-9abc-4def-8000-00000000c0ff"

BLEServer*        bleServer         = nullptr;
BLECharacteristic* statusCharacteristic = nullptr;
BLECharacteristic* configCharacteristic = nullptr;
bool bleClientConnected = false;

// ===== STATE VARIABLES =====
int  cryCounter = 0;
bool cryAlert   = false;
static unsigned long lastCryTime_global = 0;
static float lastKnownTemp = 25.0f;

// ===== FEATURE EXTRACTOR CLASS =====
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

  bool next(float features[6]) {
    if (!readSamples(_frame + _writePos, HOP)) return false;
    _writePos += HOP;
    if (_writePos < N) return false;

    for (int i = 0; i < N; ++i) {
      float x = highpass(_frame[i]);
      _vReal[i] = x * hamming(i, N);
      _vImag[i] = 0.0;
    }

    _fft.windowing(FFTWindow::Rectangle, FFTDirection::Forward);
    _fft.compute(FFTDirection::Forward);
    _fft.complexToMagnitude();

    const int bins = N / 2;
    features[0] = spectralCentroid(_vReal, bins);
    features[1] = spectralRolloff(_vReal, bins, 0.85f);
    features[2] = zeroCrossingRate(_frame, N);
    features[3] = spectralFlux(_vReal, bins);
    pitchAndHarm(_frame, N, SR, 200.0f, 800.0f, features[4], features[5]);

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
      if (i2s_read(I2S_PORT, &s32, sizeof(s32), &br, to) != ESP_OK || br != sizeof(s32)) return false;
      int32_t s24 = s32 >> 8;
      float v = (float)s24 / 8388608.0f;
      dst[i] = v;
      acc += (double)v * (double)v;
    }
    _lastRms = sqrt(acc / count);
    return true;
  }

  float highpass(float x) {
    const float fc = 70.0f;
    const float dt = 1.0f / SR;
    const float RC = 1.0f / (2.0f * PI * fc);
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
    for (int k = 1; k < bins; ++k) { 
      double f = (double)k * SR / N; 
      num += f * mag[k]; 
      den += mag[k]; 
    }
    return den > 0.0 ? (float)(num / den) : 0.0f;
  }

  float spectralRolloff(const double *mag, int bins, float prop) {
    double total = 0.0; 
    for (int k = 0; k < bins; ++k) total += mag[k];
    double target = prop * total, acc = 0.0;
    for (int k = 0; k < bins; ++k) { 
      acc += mag[k]; 
      if (acc >= target) return (float)k * SR / N; 
    }
    return 0.0f;
  }

  float spectralFlux(const double *mag, int bins) {
    double flux = 0.0;
    for (int k = 0; k < bins; ++k) { 
      double d = mag[k] - _prevMag[k]; 
      if (d > 0.0) flux += d; 
      _prevMag[k] = mag[k]; 
    }
    return (float)flux;
  }

  float zeroCrossingRate(const float *x, int n) {
    int zc = 0; 
    for (int i = 1; i < n; ++i) { 
      if ((x[i-1] >= 0) != (x[i] >= 0)) zc++; 
    }
    return (float)zc / (float)n;
  }

  void pitchAndHarm(const float *x, int n, int sr, float fmin, float fmax, float &f0Hz, float &harm) {
    static float buf[N];
    double mean = 0.0; 
    for (int i = 0; i < n; ++i) mean += x[i]; 
    mean /= n;
    for (int i = 0; i < n; ++i) buf[i] = x[i] - (float)mean;

    int lagMin = (int)(sr / fmax), lagMax = (int)(sr / fmin);
    if (lagMax > n - 1) lagMax = n - 1;

    double e0 = 0.0; 
    for (int i = 0; i < n; ++i) e0 += buf[i] * buf[i];

    double best = 0.0; 
    int bestLag = 0;
    for (int L = lagMin; L <= lagMax; ++L) {
      double r = 0.0, eL = 0.0;
      for (int i = 0; i + L < n; ++i) { 
        r += buf[i] * buf[i + L]; 
        eL += buf[i + L] * buf[i + L]; 
      }
      double rn = r / sqrt((e0 + 1e-9) * (eL + 1e-9));
      if (rn > best) { 
        best = rn; 
        bestLag = L; 
      }
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

bool isCryFrame(const float f[6]) {
  bool rmsOK   = (fx.lastRMS() >= RMS_MIN);
  bool fluxOK  = (f[3] >= FLUX_MIN);
  bool harmOK  = (f[5] >= HARMONICITY_MIN);
  bool centroidOK = (f[0] >= CENTROID_MIN_HZ && f[0] <= CENTROID_MAX_HZ);
  bool rolloffOK  = (f[1] <= ROLLOFF_MAX_HZ);
  bool zcrOK      = (f[2] <= ZCR_MAX);
  bool pitchKnown  = (f[4] > 0.0f);
  bool pitchInBand = (f[4] >= PITCH_MIN_HZ && f[4] <= PITCH_MAX_HZ);
  bool pitchOK = (!pitchKnown) || pitchInBand;
  return rmsOK && fluxOK && harmOK && centroidOK && rolloffOK && zcrOK && pitchOK;
}

// ===== BLE CALLBACKS =====
class SmartBabyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override { bleClientConnected = true; }
  void onDisconnect(BLEServer* pServer) override {
    bleClientConnected = false;
    delay(500);
    BLEDevice::startAdvertising();
  }
};

class ConfigCharCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String value = pCharacteristic->getValue();
    if (value.length() == 0) return;
    int highPos = value.indexOf("\"temp_high\":");
    if (highPos != -1) {
      float v = value.substring(highPos + 12).toFloat();
      if (v >= 28.0f && v <= 35.0f) {
        TEMP_HIGH_THRESHOLD = v;
        Serial.printf("BLE: Temp threshold updated to %.1f°C\n", v);
      }
    }
  }
};

void bleUpdateStatus(float tempC, bool tempValid, bool tempAlert, bool cryAlert,
                     unsigned long lastCryTime, unsigned long nowMs) {
  if (!statusCharacteristic) return;
  unsigned long ageMs = (nowMs >= lastCryTime) ? (nowMs - lastCryTime) : 0;
  const char* tempState = tempValid ? (tempC >= TEMP_HIGH_THRESHOLD ? "high" : "ok") : "na";
  char payload[160];
  snprintf(payload, sizeof(payload),
           "{\"temp_c\":%.1f,\"temp_alert\":\"%s\",\"cry\":%s,\"cry_age_ms\":%lu,\"connected\":%s}",
           tempValid ? tempC : 0.0f, tempState, cryAlert ? "true" : "false",
           ageMs, bleClientConnected ? "true" : "false");
  statusCharacteristic->setValue((uint8_t*)payload, strlen(payload));
  if (bleClientConnected) statusCharacteristic->notify();
}

// ===== SETUP =====
void setup() {
  Serial.begin(115200);
  delay(200);
  pinMode(BUZZER_PIN, OUTPUT);
  buzzerOff();

  BLEDevice::init("baby_monitor");
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new SmartBabyServerCallbacks());
  BLEService *service = bleServer->createService(SMARTBABY_SERVICE_UUID);

  statusCharacteristic = service->createCharacteristic(SMARTBABY_STATUS_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  statusCharacteristic->addDescriptor(new BLE2902());

  configCharacteristic = service->createCharacteristic(SMARTBABY_CONFIG_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ);
  configCharacteristic->setCallbacks(new ConfigCharCallbacks());

  char cfg[80];
  snprintf(cfg, sizeof(cfg), "{\"temp_high\":%.1f}", TEMP_HIGH_THRESHOLD);
  configCharacteristic->setValue(cfg);
  service->start();
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SMARTBABY_SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  sensors.begin();
  sensors.setResolution(12);
  display.setBrightness(0x0f);

  if (!fx.begin()) {
    Serial.println("I2S init failed");
    while (1) delay(1000);
  }
}

// ===== MAIN LOOP =====
// ===== MAIN LOOP =====
void loop() {
  static unsigned long lastCryTime = 0, lastBlink = 0, lastDebugOut = 0, lastAdvertCheck = 0;
  static bool blinkState = false, prevCryAlert = false;

  unsigned long nowMs = millis();

  // BLE advertising
  if (!bleClientConnected && nowMs - lastAdvertCheck >= 30000) {
    lastAdvertCheck = nowMs;
    BLEDevice::startAdvertising();
  }

  // === TEMPERATURE ===
  sensors.requestTemperatures();
  float tempC = sensors.getTempCByIndex(0);
  bool tempValid = (tempC != DEVICE_DISCONNECTED_C);

  bool tempTooHigh = false;
  if (tempValid) {
    if (tempC >= TEMP_HIGH_THRESHOLD + TEMP_HYSTERESIS) {
      tempTooHigh = true;
    }
    else if (tempC < TEMP_HIGH_THRESHOLD) {
      tempTooHigh = false;
    }
    else {
      tempTooHigh = (lastKnownTemp >= TEMP_HIGH_THRESHOLD);
    }
    lastKnownTemp = tempC;
  }

  // === ESCALATING TEMP BEEP ===
  float scale = 0.0f;
  if (tempTooHigh && tempValid) {
    isTempBeeping = true;
    float over = tempC - TEMP_HIGH_THRESHOLD;
    scale = constrain(over / (TEMP_MAX_C - TEMP_HIGH_THRESHOLD), 0.0f, 1.0f);

    uint16_t freq = TEMP_BASE_FREQ + (uint16_t)(scale * (TEMP_MAX_FREQ - TEMP_BASE_FREQ));
    unsigned long interval = MAX_BEEP_INTERVAL - (unsigned long)(scale * (MAX_BEEP_INTERVAL - MIN_BEEP_INTERVAL));

    if (nowMs >= nextBeepTime && !beepActive) {
      triggerBeep(freq, BASE_BEEP_DURATION);
      nextBeepTime = nowMs + interval;
    }
  } else {
    isTempBeeping = false;
  }

  // === CRY DETECTION (WITH DEBUG) ===
  float features[6] = {0};
  bool haveFeatures = fx.next(features);

  bool isCry = false;
  if (haveFeatures) {
    float rms = fx.lastRMS();
    float centroid = features[0];
    float rolloff = features[1];
    float zcr = features[2];
    float flux = features[3];
    float pitch = features[4];
    float harm = features[5];

    // === RELAXED CRY RULES (WORK IN REAL WORLD) ===
    bool rmsOK      = rms >= 0.004f;                    // Lowered from 0.006
    bool fluxOK     = flux >= 0.8f;                     // Lowered
    bool harmOK     = harm >= 0.55f;                    // Lowered
    bool centroidOK = centroid >= 1000.0f && centroid <= 3200.0f;
    bool rolloffOK  = rolloff <= 4000.0f;
    bool zcrOK      = zcr <= 0.35f;
    bool pitchOK    = (pitch == 0) || (pitch >= 220.0f && pitch <= 700.0f);

    isCry = rmsOK && fluxOK && harmOK && centroidOK && rolloffOK && zcrOK && pitchOK;

    // === DEBUG: Print cry features every 500ms ===
    static unsigned long lastCryDebug = 0;
    if (nowMs - lastCryDebug >= 500) {
      lastCryDebug = nowMs;
      Serial.printf("CRY: RMS:%.4f C:%.0f R:%.0f Z:%.3f F:%.2f P:%.0f H:%.2f | CRY:%d\n",
                    rms, centroid, rolloff, zcr, flux, pitch, harm, isCry);
    }
  }

  if (isCry) {
    cryCounter++;
    lastCryTime = nowMs;
  } else {
    cryCounter = 0;
  }

  const unsigned long CRY_LATCH_MS = 5000;
  cryAlert = (nowMs - lastCryTime < CRY_LATCH_MS);
  lastCryTime_global = lastCryTime;

  // === CRY BEEP (LOUD & CLEAR) ===
  if (cryAlert && !prevCryAlert) {
    triggerBeep(CRY_BUZZER_FREQ, 400);  // Longer beep
    nextBeepTime = nowMs + 1200;        // Prevent overlap
    Serial.println("CRY DETECTED → BEEP!");
  }
  prevCryAlert = cryAlert;

  updateBeep();

  // === DISPLAY ===
    // === DISPLAY ===
  uint8_t digits[4];
  if (tempValid) {
    int tempInt = (int)(tempC * 10);
    digits[0] = display.encodeDigit((tempInt / 100) % 10);
    digits[1] = display.encodeDigit((tempInt / 10) % 10) | 0x80;
    digits[2] = display.encodeDigit(tempInt % 10);
    digits[3] = 0;
  } else {
    for (int i = 0; i < 4; i++) digits[i] = 0x40;
  }

  unsigned long blinkInterval = 0;
  if (cryAlert) {
    blinkInterval = 200;
  } else if (tempTooHigh) {
    blinkInterval = 800;
  }

  if (blinkInterval && nowMs - lastBlink >= blinkInterval) {
    blinkState = !blinkState;
    lastBlink = nowMs;
  }

  uint8_t outDigits[4];
  for (int i = 0; i < 4; i++) outDigits[i] = digits[i];

  if (cryAlert && !blinkState) {
    memset(outDigits, 0, 4);
  } else if (tempTooHigh && blinkState) {
    outDigits[2] = 0;
  }

  display.setSegments(outDigits);

  // === BLE UPDATE ===
  if (nowMs - lastDebugOut >= DEBUG_INTERVAL) {
    lastDebugOut = nowMs;
    bleUpdateStatus(tempC, tempValid, tempTooHigh, cryAlert, lastCryTime, nowMs);
  }

  delay(10);
}