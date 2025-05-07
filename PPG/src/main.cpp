#include <Arduino.h>
#include <WiFi.h>
#include <esp_wpa2.h>
#include <FirebaseESP32.h>
#include <Wire.h>
#include <MAX30105.h>
#include <spo2_algorithm.h>
#include "Secrets.h" // WiFi/Firebase credentials

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e"

MAX30105 particleSensor;

// Firebase
FirebaseData firebaseData;
FirebaseConfig config;
FirebaseAuth auth;
FirebaseJson json;

// Sensor variables
const byte RATE_SIZE = 15;
float rates[RATE_SIZE];
byte rateSpot = 0;
float beatsPerMinute = 0, beatAvg = 75;
uint32_t irBuffer[100], redBuffer[100];
int32_t spo2;
int8_t validSPO2;
int32_t bufferLength = 100;
int sampleCounter = 0;
unsigned long lastSampleTime = 0, lastSpO2Update = 0;
bool needSpO2Update = false;
#define USE_FILTER true
float alpha = 0.7;
long irFiltered = 0, irPrevious = 0, redFiltered = 0, redPrevious = 0;
const int MAX_PPG_PEAKS = 500;
unsigned long ppgPeakTimes[MAX_PPG_PEAKS];
int ppgPeakCount = 0;
unsigned long lastPPGPeakTime = 0;
long ppgRRIntervals[MAX_PPG_PEAKS - 1];
int ppgRRCount = 0;
float sessionHRV = 0.0;
bool recording = false;
static float filteredBPM = 0;
float bpmAlpha = 0.3;
static float prevFiltered = 0;
static bool wasRising = false;
static unsigned long pulseStartTime = 0;
static float pulseMin = 0, pulseMax = 0;
static unsigned long pulseMinTime = 0;
static unsigned long pulseMaxTime = 0;

// Session info
String userId = "";
String sessionId = "";
unsigned long lastSendTime = 0;

// BLE globals
BLECharacteristic *pCharacteristic;
String bleCommand = "";

void resetHRValues();
float calculateSessionHRV();
long filterValue(long newValue, long prevValue);

class CommandCallbacks : public BLECharacteristicCallbacks
{
  void onWrite(BLECharacteristic *pCharacteristic)
  {
    std::string value = pCharacteristic->getValue();
    if (value.length() > 0)
    {
      bleCommand = String(value.c_str());
      Serial.print("Received BLE command: ");
      Serial.println(bleCommand);
      if (bleCommand.startsWith("START"))
      {
        int firstSpace = bleCommand.indexOf(' ');
        int secondSpace = bleCommand.indexOf(' ', firstSpace + 1);
        userId = bleCommand.substring(firstSpace + 1, secondSpace);
        sessionId = bleCommand.substring(secondSpace + 1);
        recording = true;
        resetHRValues();
        ppgPeakCount = 0;
        ppgRRCount = 0;
        lastPPGPeakTime = 0;

        // Create a new session in Firebase
        String sessionPath = "/users/" + userId + "/sessions/" + sessionId;
        json.clear();
        json.set("startTime", String(millis()));
        Firebase.setJSON(firebaseData, sessionPath, json);
        Serial.println("New session started: " + sessionId);
      }
      else if (bleCommand.startsWith("STOP"))
      {
        recording = false;
        sessionHRV = calculateSessionHRV();
        String qPath = "/users/" + userId + "/sessions/" + sessionId + "/questionnaire/hrv";
        Firebase.setFloat(firebaseData, qPath, sessionHRV);
        Serial.println("Session stopped.");
      }
    }
  }
};

void setup()
{
  Serial.begin(115200);

  // BLE setup
  BLEDevice::init("ESP32-PPG"); // BLE device name
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_WRITE);
  pCharacteristic->setCallbacks(new CommandCallbacks());
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06); // iOS compatibility
  pAdvertising->setMinPreferred(0x12);
  pAdvertising->start();
  Serial.println("BLE device started, waiting for commands...");

  // WPA2 Enterprise WiFi setup
  WiFi.disconnect(true);
  WiFi.mode(WIFI_STA);
  esp_wifi_sta_wpa2_ent_set_identity((uint8_t *)WIFI_USERNAME, strlen(WIFI_USERNAME));
  esp_wifi_sta_wpa2_ent_set_username((uint8_t *)WIFI_USERNAME, strlen(WIFI_USERNAME));
  esp_wifi_sta_wpa2_ent_set_password((uint8_t *)WIFI_PASSWORD, strlen(WIFI_PASSWORD));
  esp_wifi_sta_wpa2_ent_enable();
  WiFi.begin(WIFI_SSID);

  Serial.print("Connecting to WiFi");
  unsigned long startAttemptTime = millis();
  const unsigned long timeout = 10000;

  while (WiFi.status() != WL_CONNECTED && millis() - startAttemptTime < timeout)
  {
    delay(500);
    Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED)
  {
    Serial.println("\nConnected to WiFi");
    Serial.println("IP Address: " + WiFi.localIP().toString());
  }
  else
  {
    Serial.println("\nFailed to connect to WiFi. Continuing without WiFi...");
  }

  // Firebase setup
  config.database_url = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // Sensor setup
  Wire.begin(21, 22);
  particleSensor.begin(Wire, I2C_SPEED_FAST);
  particleSensor.setup();
  particleSensor.setPulseAmplitudeRed(0x3F);
  particleSensor.setPulseAmplitudeGreen(0);
  for (byte i = 0; i < RATE_SIZE; i++)
    rates[i] = 75;
  beatAvg = 75;
}

void loop()
{
  if (WiFi.status() != WL_CONNECTED)
  {
    Serial.println("WiFi disconnected. Attempting to reconnect...");
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID);

    // Wait for reconnection
    int retryCount = 0;
    while (WiFi.status() != WL_CONNECTED && retryCount < 20)
    { // Retry up to 20 times
      delay(500);
      Serial.print(".");
      retryCount++;
    }

    if (WiFi.status() == WL_CONNECTED)
    {
      Serial.println("\nReconnected to WiFi");
      Serial.println("IP Address: " + WiFi.localIP().toString());
    }
    else
    {
      Serial.println("\nFailed to reconnect to WiFi");
    }
  }

  if (!recording)
  {
    delay(100);
    return;
  }

  // Sensor reading and filtering
  long irValue = particleSensor.getIR();
  long redValue = particleSensor.getRed();
  irFiltered = filterValue(irValue, irPrevious);
  redFiltered = filterValue(redValue, redPrevious);
  irPrevious = irFiltered;
  redPrevious = redFiltered;

  // Peak detection for HR/HRV
  static long prev1 = 0, prev2 = 0;
  static unsigned long lastPeakTime = 0;
  if (prev2 < prev1 && prev1 > irFiltered && prev1 > 50000)
  {
    unsigned long now = millis();
    if ((now - lastPeakTime) > 500)
    {
      if (ppgPeakCount < MAX_PPG_PEAKS)
        ppgPeakTimes[ppgPeakCount++] = now;
      if (lastPeakTime > 0)
      {
        long delta = now - lastPeakTime;
        beatsPerMinute = 60.0 / (delta / 1000.0);
        if (beatsPerMinute < 255 && beatsPerMinute > 20)
        {
          if (beatAvg > 0 && (beatsPerMinute < 0.7 * beatAvg || beatsPerMinute > 1.3 * beatAvg))
          {
            // Ignore outlier
          }
          else
          {
            if (filteredBPM == 0)
              filteredBPM = beatsPerMinute;
            else
              filteredBPM = bpmAlpha * beatsPerMinute + (1 - bpmAlpha) * filteredBPM;
            rates[rateSpot++] = filteredBPM;
            rateSpot %= RATE_SIZE;
            beatAvg = 0;
            for (byte x = 0; x < RATE_SIZE; x++)
              beatAvg += rates[x];
            beatAvg /= RATE_SIZE;
          }
        }
      }
      lastPeakTime = now;
    }
  }
  prev2 = prev1;
  prev1 = irFiltered;

  // BP estimation
  if (!wasRising && irFiltered > prevFiltered)
  {
    pulseMin = prevFiltered;
    pulseMinTime = millis();
    wasRising = true;
    pulseStartTime = pulseMinTime;
  }
  if (wasRising && irFiltered < prevFiltered)
  {
    pulseMax = prevFiltered;
    pulseMaxTime = millis();
    wasRising = false;
    float pulseAmplitude = pulseMax - pulseMin;
    float pulseWidth = pulseMaxTime - pulseStartTime;
    float heartRate = filteredBPM;
    float estimatedSBP = 120 + (pulseAmplitude * 0.005) - (pulseWidth * 0.05) + (heartRate * 0.2);
    float estimatedDBP = 80 + (pulseAmplitude * 0.002) - (pulseWidth * 0.02) + (heartRate * 0.1);
    if (millis() - lastSendTime > 1000)
    {
      lastSendTime = millis();
      if (userId.length() > 0 && sessionId.length() > 0)
      {
        String path = "/users/" + userId + "/sessions/" + sessionId + "/readings";
        json.clear();
        json.set("heartRate", filteredBPM);
        json.set("avgHeartRate", beatAvg);
        json.set("sbp", estimatedSBP);
        json.set("dbp", estimatedDBP);
        json.set("oxygen", spo2);
        json.set("timestamp", millis());
        Firebase.pushJSON(firebaseData, path, json);
      }
    }
  }
  prevFiltered = irFiltered;

  // SpO2 calculation
  if (millis() - lastSampleTime > 10)
  {
    lastSampleTime = millis();
    irBuffer[sampleCounter] = irFiltered;
    redBuffer[sampleCounter] = redFiltered;
    sampleCounter++;
    if (sampleCounter >= 100)
    {
      needSpO2Update = true;
      sampleCounter = 0;
    }
  }
  if (needSpO2Update && millis() - lastSpO2Update > 1000)
  {
    int32_t tempHeartRate;
    int8_t tempHRvalid;
    maxim_heart_rate_and_oxygen_saturation(irBuffer, bufferLength, redBuffer,
                                           &spo2, &validSPO2, &tempHeartRate, &tempHRvalid);
    lastSpO2Update = millis();
    needSpO2Update = false;
  }
}

void resetHRValues()
{
  beatsPerMinute = 0;
  beatAvg = 75;
  filteredBPM = 0;
  for (byte i = 0; i < RATE_SIZE; i++)
    rates[i] = 75;
  spo2 = 0;
  validSPO2 = 0;
  ppgPeakCount = 0;
  ppgRRCount = 0;
  lastPPGPeakTime = 0;
}

float calculateSessionHRV()
{
  ppgRRCount = 0;
  for (int i = 1; i < ppgPeakCount; i++)
  {
    long rr = ppgPeakTimes[i] - ppgPeakTimes[i - 1];
    if (rr > 500 && rr < 1200)
      ppgRRIntervals[ppgRRCount++] = rr;
  }
  if (ppgRRCount == 0)
    return 0.0;
  long sum = 0;
  for (int i = 0; i < ppgRRCount; i++)
    sum += ppgRRIntervals[i];
  float mean = (float)sum / ppgRRCount;
  float variance = 0.0;
  for (int i = 0; i < ppgRRCount; i++)
    variance += pow(ppgRRIntervals[i] - mean, 2);
  variance /= ppgRRCount;
  return sqrt(variance);
}

long filterValue(long newValue, long prevValue)
{
  if (USE_FILTER)
  {
    if (prevValue == 0)
      return newValue;
    return (long)(alpha * newValue + (1 - alpha) * prevValue);
  }
  else
  {
    return newValue;
  }
}