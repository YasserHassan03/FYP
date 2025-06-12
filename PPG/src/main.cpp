#define LOG_LOCAL_LEVEL ESP_LOG_WARN
#include "esp_log.h"
#include <Arduino.h>
#include <Wire.h>
#undef I2C_BUFFER_LENGTH // Fix redefinition warning
#include <MAX30105.h>
#include <spo2_algorithm.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define RX_CHAR_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e" // Write (App -> ESP)
#define TX_CHAR_UUID "6e400003-b5a3-f393-e0a9-e50e24dcca9e" // Notify (ESP -> App)

MAX30105 particleSensor;

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

BLECharacteristic *txCharacteristic;
BLECharacteristic *rxCharacteristic;

unsigned long lastDataSentTime = 0; // Track the last time data was sent

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
      String bleCommand = String(value.c_str());
      Serial.print("Received BLE command: ");
      delay(10);
      Serial.println(bleCommand);
      delay(10);
      if (bleCommand.startsWith("START"))
      {
        recording = true;
        resetHRValues();
        ppgPeakCount = 0;
        ppgRRCount = 0;
        lastPPGPeakTime = 0;
        Serial.println("Session started.");
        delay(10);
      }
      else if (bleCommand.startsWith("STOP"))
      {
        recording = false;
        sessionHRV = calculateSessionHRV();
        Serial.println("Session stopped.");
        delay(10);
        // Send HRV summary to app
        String summary = String("{\"hrv\":") + String(sessionHRV, 2) + "}";
        txCharacteristic->setValue(summary.c_str());
        txCharacteristic->notify();
      }
    }
  }
};

void setup()
{
  Serial.begin(230400);
  delay(1000);
  Serial.println("Before BLE setup...");
  delay(1000);

  // BLE setup
  BLEDevice::init("ESP32-PPG");
  delay(10000);
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);

  rxCharacteristic = pService->createCharacteristic(
      RX_CHAR_UUID,
      BLECharacteristic::PROPERTY_WRITE);
  rxCharacteristic->setCallbacks(new CommandCallbacks());

  txCharacteristic = pService->createCharacteristic(
      TX_CHAR_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);
  txCharacteristic->addDescriptor(new BLE2902());

  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  pAdvertising->start();
  Serial.println("BLE device started, waiting for commands...");
  delay(10);

  // Sensor setup
  Wire.begin(21, 22);
  particleSensor.begin(Wire, I2C_SPEED_FAST);
  particleSensor.setup();
  particleSensor.setPulseAmplitudeRed(0x3F);
  particleSensor.setPulseAmplitudeGreen(0);
  for (byte i = 0; i < RATE_SIZE; i++)
    rates[i] = 75;
  beatAvg = 0;
}

void loop()
{
  
  if (!recording)
  {
    delay(100);
    return;
  }

  // Declare pulse variables at the beginning of the loop
  float pulseAmplitude = 0;
  float pulseWidth = 0;

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
    pulseAmplitude = pulseMax - pulseMin;
    pulseWidth = pulseMaxTime - pulseMinTime;
  }

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

  // --- SEND DATA EVERY SECOND, NO MATTER WHAT ---
  unsigned long currentTime = millis();
  if (currentTime - lastDataSentTime >= 1000)
  {
    float estimatedSBP = 115 + (pulseAmplitude * 0.004) - (pulseWidth * 0.04) + (filteredBPM * 0.15);
float estimatedDBP = 75 + (pulseAmplitude * 0.0015) - (pulseWidth * 0.015) + (filteredBPM * 0.08);

    String data = String("{\"heartRate\":") + String(filteredBPM, 1) +
                  ",\"avgHeartRate\":" + String(beatAvg, 1) +
                  ",\"sbp\":" + String(estimatedSBP, 1) +
                  ",\"dbp\":" + String(estimatedDBP, 1) +
                  ",\"oxygen\":" + String(spo2) +
                  ",\"timestamp\":" + String(millis()) + "}";
    txCharacteristic->setValue(data.c_str());
    txCharacteristic->notify();
    Serial.println("Data sent to app: " + data);

    lastDataSentTime = currentTime;
  }
}
void resetHRValues()
{
  beatsPerMinute = 0;
  beatAvg = 0;
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