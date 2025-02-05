#include <Wire.h>
#include "MAX30105.h"

MAX30105 particleSensor;

void setup() {
  Serial.begin(115200);
  Serial.println("Initializing MAX30101 Sensor...");

  // Initialize the sensor
  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30101 sensor not found. Please check wiring/power.");
    while (1);
  }

  // Configure the sensor
  particleSensor.setup(); // Default settings
  particleSensor.setPulseAmplitudeRed(0x0A); // Turn Red LED to low to indicate sensor is running
  particleSensor.setPulseAmplitudeGreen(0); // Turn off Green LED

  Serial.println("MAX30101 Sensor Initialized!");
}

void loop() {
  // Read raw PPG data
  int32_t redValue = particleSensor.getRed();
  int32_t irValue = particleSensor.getIR();

  // Print the values to the Serial Monitor
  Serial.print("Red: ");
  Serial.print(redValue);
  Serial.print(", IR: ");
  Serial.println(irValue);

  // Add a small delay to avoid flooding the Serial Monitor
  delay(100);
}