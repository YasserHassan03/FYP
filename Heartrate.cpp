#include <Wire.h>
#include "MAX30105.h"
#include <PeakDetection.h>
#include "KickFiltersRT.h"
#include <Adafruit_Sensor.h>
#include <Adafruit_BME280.h>
#include <DFRobot_ENS160.h>
#include <Arduino.h>
#include <vector>

DFRobot_ENS160_I2C ENS160(&Wire1, 0x53);
Adafruit_BME280 bme;

MAX30105 particleSensor;
PeakDetection peakDetection;
KickFiltersRT<float> filtersRT;

const float fs = 100;
const int BUFFER_SIZE = 10;
std::vector<unsigned long> bpmValues;

volatile float BME_T = 0;
volatile float BME_RH = 0;
volatile float ENS_TVOC = 0;
volatile float ENS_CO2 = 0;

#define debug Serial

void setup() {
  debug.begin(9600);
  debug.println("MAX30105 Basic Readings Example");
  delay(2000);

  Wire1.setPins(SDA1, SCL1);
  Wire1.begin();
  delay(2000);

  //Initialize BME280
  if (!bme.begin(0x77, &Wire1)) {
    Serial.println("BME280 initialization failed!");
    while (1);
  } else {
    Serial.println("BME280 initialized successfully!");
  }

  bme.setSampling(Adafruit_BME280::MODE_NORMAL,
                  Adafruit_BME280::SAMPLING_X4,
                  Adafruit_BME280::SAMPLING_NONE,
                  Adafruit_BME280::SAMPLING_X4,
                  Adafruit_BME280::FILTER_OFF,
                  Adafruit_BME280::STANDBY_MS_0_5);

  //Initialize ENS160
  while (NO_ERR != ENS160.begin()) {
    Serial.println("Communication with ENS160 failed, please check connection.");
    delay(3000);
  }
  Serial.println("ENS160 initialized successfully.");
  ENS160.setPWRMode(ENS160_STANDARD_MODE);
  ENS160.setTempAndHum(25.0, 50.0);

  // Initialize MAX30105
  particleSensor.begin(Wire1, 400000, 0x57);
  while (particleSensor.begin(Wire1, 400000, 0x57) == false) {
    debug.println("MAX30105 not found. Please check wiring.");
    delay(1000);
  }
  debug.println("MAX30105 found.");
  particleSensor.setup(0x1F, 4, 2, 100, 411, 16384);
  peakDetection.begin(20, 3, 0.6);
}

unsigned long lastSensorReadTime = 0;
float last = 0;
float last2 = 0;
float inter = 3000;
bool sign = false;
float lasttime = 0;
int count = 0;
float lastt = 0;
double lastbpm = 0;
double lasttime2 = 0;
double la = 0;
bool notbeat = false;

void loop() {
  double lpfiltered = filtersRT.lowpass(particleSensor.getIR(), 4, fs);
  double hpfiltered = filtersRT.highpass(lpfiltered, 1, fs);
  double difference = hpfiltered - last;
  last = hpfiltered;

  double squared = difference * difference;
  peakDetection.add(squared);
  double moving = peakDetection.getFilt();
  int peak = peakDetection.getPeak();

  if (peak == 1 && inter > 2000) {
    lasttime = millis();
  }

  if (difference > 0) {
    if (notbeat && (millis() - la) > 500) {
      float bpm = 60000 / (millis() - la);
      la = millis();
      bpmValues.push_back(bpm);

      if (bpmValues.size() == 10) {
        float sumBPM = 0;
        for (float bpm : bpmValues) {
          sumBPM += bpm;
        }
        float averageBPM = sumBPM / bpmValues.size();
        bpmValues.clear();

        BME_T = bme.readTemperature();
        BME_RH = bme.readHumidity();

        debug.print("Average BPM over last 5 beats: ");
        debug.println(averageBPM);
        Serial.print("Temperature: ");
        Serial.print(BME_T);
        Serial.println(" °C");
        Serial.print("Humidity: ");
        Serial.print(BME_RH);
        Serial.println(" %");

        uint8_t AQI = ENS160.getAQI();
        Serial.print("Air Quality Index: ");
        Serial.println(AQI);

        uint16_t TVOC = ENS160.getTVOC();
        Serial.print("TVOC Concentration: ");
        Serial.print(TVOC);
        Serial.println(" ppb");

        uint16_t ECO2 = ENS160.getECO2();
        Serial.print("Equivalent CO2 Concentration: ");
        Serial.print(ECO2);
        Serial.println(" ppm");
      }
    }
    notbeat = false;
  } else {
    notbeat = true;
  }

  double difference2 = (moving - last2) * 100;
  last2 = moving;
}
