#include <Wire.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"

MAX30105 particleSensor;

#define MAX_BRIGHTNESS 255

uint32_t irBuffer[100]; 
uint32_t redBuffer[100]; 
int32_t bufferLength = 100; 

int32_t spo2;
int8_t validSPO2;
int32_t heartRate;
int8_t validHeartRate;

float prevHeartRate = 70;
float prevSpo2 = 95;

const float MIN_SIGNAL_AMPLITUDE = 5000; // Minimum signal amplitude to consider valid data

void setup()
{
  Serial.begin(115200);
  Wire1.setPins(SDA1, SCL1);
  Wire1.begin();
  delay(2000);

  if (!particleSensor.begin(Wire1, 400000, 0x57))
  {
    Serial.println(F("MAX30105 not found."));
    while (1);
  }

  particleSensor.setup(60, 4, 2, 100, 411, 4096);
}

void loop()
{
  bufferLength = 100;

  for (byte i = 0; i < bufferLength; i++)
  {
    while (particleSensor.available() == false)
      particleSensor.check();

    redBuffer[i] = particleSensor.getRed();
    irBuffer[i] = particleSensor.getIR();
    particleSensor.nextSample();
  }

  maxim_heart_rate_and_oxygen_saturation(irBuffer, bufferLength, redBuffer, &spo2, &validSPO2, &heartRate, &validHeartRate);

  if (validHeartRate && validSPO2)
  {
    // Signal Quality Check
    if (calculateSignalAmplitude(irBuffer, bufferLength) > MIN_SIGNAL_AMPLITUDE)
    {
      heartRate = adaptiveFilter(heartRate, prevHeartRate);
      spo2 = adaptiveFilter(spo2, prevSpo2);

      // Range Check to remove extreme values
      if (heartRate > 200 || heartRate < 40) heartRate = prevHeartRate;
      if (spo2 > 100 || spo2 < 70) spo2 = prevSpo2;
      
      prevHeartRate = heartRate;
      prevSpo2 = spo2;
    }
    else
    {
      Serial.println(F("Signal too weak, skipping..."));
      return;
    }
  }

  Serial.print(F("HR="));
  Serial.print(heartRate);
  Serial.print(F(", SPO2="));
  Serial.println(spo2);

  delay(1000);
}

float adaptiveFilter(float currentValue, float previousValue)
{
  float alpha = 0.2;  // Adjust alpha for smoothing (higher = more responsive, lower = smoother)
  return alpha * currentValue + (1 - alpha) * previousValue;
}

float calculateSignalAmplitude(uint32_t *buffer, int length)
{
  uint32_t maxVal = 0, minVal = UINT32_MAX;
  for (int i = 0; i < length; i++)
  {
    if (buffer[i] > maxVal) maxVal = buffer[i];
    if (buffer[i] < minVal) minVal = buffer[i];
  }
  return maxVal - minVal;
}
