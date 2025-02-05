#include <Wire.h>
#include "MAX30105.h"

MAX30105 particleSensor;

void setup() {
  Serial.begin(9600);
  delay(1000);  
  Serial.println("Initializing MAX30105 on Wire1...");

  Wire1.setPins(SDA1, SCL1);  
  Wire1.begin();  
  

  if (particleSensor.begin(Wire1) == false) {
    Serial.println("MAX30105 not found on Wire1. Please check your wiring.");
    while (1);  
  }

  particleSensor.setup();  
  Serial.println("MAX30105 initialized on Wire1.");
}

void loop() {
  long irValue = particleSensor.getIR();
  long redValue = particleSensor.getRed();
  long greenValue = particleSensor.getGreen();
  
  Serial.print("IR: ");
  Serial.print(irValue);
  Serial.print(" | Red: ");
  Serial.println(redValue);
  Serial.print(" | Green: ");
  Serial.println(greenValue);
  
  delay(100);  
}
