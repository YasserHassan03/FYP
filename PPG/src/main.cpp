#include <SparkFun_Bio_Sensor_Hub_Library.h>
#include <Wire.h>
#include <math.h>

// Reset pin, MFIO pin
int resPin = 4;
int mfioPin = 5;

// Takes address, reset pin, and MFIO pin.
SparkFun_Bio_Sensor_Hub bioHub(resPin, mfioPin);

bioData body;

// Buffers for HRV and respiratory rate
#define HRV_BUFFER_SIZE 30
#define RESP_BUFFER_SIZE 30
float hrvBuffer[HRV_BUFFER_SIZE];
float respBuffer[RESP_BUFFER_SIZE];
int hrvBufferIndex = 0;
int respBufferIndex = 0;
int validHRVCount = 0; // Tracks the number of valid HRV intervals in the buffer
int validRespCount = 0; // Tracks the number of valid respiratory intervals in the buffer


int totalRespirationCycles = 0; // Rolling count of respiration cycles
unsigned long startTime = 0;    // Start time for respiratory rate calculation
#define RESPIRATION_WINDOW_MS 20000 

void setup() {
  Serial.begin(115200);

  Wire.begin(21, 22); // SDA = GPIO 21, SCL = GPIO 22
  int result = bioHub.begin();
  if (result == 0) 
    Serial.println("Sensor started!");
  else
    Serial.println("Could not communicate with the sensor!");

  Serial.println("Configuring Sensor....");
  int error = bioHub.configBpm(MODE_TWO); // Configuring just the BPM settings.
  if (error == 0) { // Zero errors
    Serial.println("Sensor configured.");
  } else {
    Serial.println("Error configuring sensor.");
    Serial.print("Error: ");
    Serial.println(error);
  }

  Serial.println("Loading up the buffer with data....");
  delay(4000);
  startTime = millis(); // Initialize the start time
}

void loop() {
  body = bioHub.readBpm();

  // Check if a finger is detected
  if (body.status != 3) { // 3 indicates a finger is detected
    Serial.println("No finger detected. Please place your finger on the sensor.");
    memset(hrvBuffer, 0, sizeof(hrvBuffer)); // Clear HRV buffer
    memset(respBuffer, 0, sizeof(respBuffer)); // Clear respiratory buffer
    hrvBufferIndex = 0;
    respBufferIndex = 0;
    validHRVCount = 0;
    validRespCount = 0;
    totalRespirationCycles = 0;
    startTime = millis(); // Reset the start time
    return;
  }

  if (body.confidence < 75) {
    Serial.println("Low confidence in readings. Please adjust finger placement.");
    return;
  }

  // Print heart rate, blood oxygen, and confidence
  Serial.print("Heartrate (BPM): ");
  Serial.println(body.heartRate);
  Serial.print("Blood Oxygen (%): ");
  Serial.println(body.oxygen);
  Serial.print("Confidence (%): ");
  Serial.println(body.confidence);


  if (body.heartRate >= 35 && body.heartRate <= 180) { // Valid heart rate range
    float rrInterval = 60000.0 / body.heartRate; // RR interval in ms

    // Populate HRV buffer
    hrvBuffer[hrvBufferIndex] = rrInterval;
    hrvBufferIndex = (hrvBufferIndex + 1) % HRV_BUFFER_SIZE;
    if (validHRVCount < HRV_BUFFER_SIZE) {
      validHRVCount++; // Increment valid HRV count until the buffer is full
    }

    // Populate respiratory buffer
    respBuffer[respBufferIndex] = rrInterval;
    respBufferIndex = (respBufferIndex + 1) % RESP_BUFFER_SIZE;
    if (validRespCount < RESP_BUFFER_SIZE) {
      validRespCount++; // Increment valid respiratory count until the buffer is full
    }

    // Detect respiratory cycles (peaks and troughs in RR intervals)
    if (validRespCount > 1) {
      float prevRR = respBuffer[(respBufferIndex - 1 + RESP_BUFFER_SIZE) % RESP_BUFFER_SIZE];
      float currRR = respBuffer[(respBufferIndex - 2 + RESP_BUFFER_SIZE) % RESP_BUFFER_SIZE];
      float nextRR = respBuffer[respBufferIndex];

      if (currRR > prevRR && currRR > nextRR) { // Peak detected
        totalRespirationCycles++;
      }
    }

    // Calculate HRV (SDNN) when HRV buffer is full
    if (validHRVCount == HRV_BUFFER_SIZE) {
      float mean = 0;
      for (int i = 0; i < HRV_BUFFER_SIZE; i++) {
        mean += hrvBuffer[i];
      }
      mean /= HRV_BUFFER_SIZE;

      float variance = 0;
      for (int i = 0; i < HRV_BUFFER_SIZE; i++) {
        variance += (hrvBuffer[i] - mean) * (hrvBuffer[i] - mean);
      }
      variance /= HRV_BUFFER_SIZE;

      float sdnn = sqrt(variance); // Standard Deviation of NN intervals


      Serial.print("HRV (SDNN in ms): ");
      Serial.println(sdnn);
    }

    // Calculate respiratory rate when respiratory buffer is full
    unsigned long elapsedTime = millis() - startTime;
    if (elapsedTime >= RESPIRATION_WINDOW_MS && validRespCount == RESP_BUFFER_SIZE) {
      int cyclesInWindow = totalRespirationCycles; // Cycles in the current window
      float respirationRate = (cyclesInWindow / (elapsedTime / 60000.0)); // Breaths per minute

      Serial.print("Respiratory Rate (breaths/min): ");
      Serial.println(respirationRate);

      // Reset respiratory buffer and variables
      memset(respBuffer, 0, sizeof(respBuffer)); // Clear respiratory buffer
      respBufferIndex = 0;
      validRespCount = 0;
      totalRespirationCycles = 0;
      startTime = millis(); // Reset the start time
    }
  } else {
    Serial.println("Invalid heart rate detected. Please check the sensor or finger placement.");
  }

  delay(1000); 
}