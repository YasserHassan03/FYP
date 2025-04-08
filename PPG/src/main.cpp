#include <SparkFun_Bio_Sensor_Hub_Library.h>
#include <Wire.h>

// Reset pin, MFIO pin
int resPin = 4;
int mfioPin = 5;

// Takes address, reset pin, and MFIO pin.
SparkFun_Bio_Sensor_Hub bioHub(resPin, mfioPin);

bioData body;

// Buffers for RR intervals
#define BUFFER_SIZE 30
float rrIntervals[BUFFER_SIZE];
int bufferIndex = 0;
int validRRCount = 0; // Tracks the number of valid RR intervals in the buffer

// Variables for respiratory rate calculation
int totalRespirationCycles = 0; // Rolling count of respiration cycles
int previousRespirationCycles = 0; // Tracks cycles from the previous window
unsigned long startTime = 0;    // Start time for respiratory rate calculation
#define RESPIRATION_WINDOW_MS 60000 // 60 seconds

// Rolling average for respiratory rate
float rollingRespRate = 0.0;
int rollingRespRateCount = 0;

void setup() {
  Serial.begin(115200);

  Wire.begin(21, 22); // SDA = GPIO 21, SCL = GPIO 22
  int result = bioHub.begin();
  if (result == 0) // Zero errors!
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
    memset(rrIntervals, 0, sizeof(rrIntervals)); // Clear the buffer
    bufferIndex = 0; // Reset the buffer index
    validRRCount = 0; // Reset valid RR count
    totalRespirationCycles = 0; // Reset respiration cycle count
    previousRespirationCycles = 0; // Reset previous cycle count
    startTime = millis(); // Reset the start time
    rollingRespRate = 0.0; // Reset rolling average
    rollingRespRateCount = 0;
    return;
  }

  // Validate confidence level
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

  // Ensure valid heart rate
  if (body.heartRate >= 35 && body.heartRate <= 180) { // Valid heart rate range
    float rrInterval = 60000.0 / body.heartRate; // RR interval in ms

    // Populate the buffer
    rrIntervals[bufferIndex] = rrInterval;
    bufferIndex = (bufferIndex + 1) % BUFFER_SIZE;
    if (validRRCount < BUFFER_SIZE) {
      validRRCount++; // Increment valid RR count until the buffer is full
    }

    // Detect respiratory cycles (peaks and troughs in RR intervals)
    if (validRRCount > 1) {
      float prevRR = rrIntervals[(bufferIndex - 1 + BUFFER_SIZE) % BUFFER_SIZE];
      float currRR = rrIntervals[(bufferIndex - 2 + BUFFER_SIZE) % BUFFER_SIZE];
      float nextRR = rrIntervals[bufferIndex];

      if (currRR > prevRR && currRR > nextRR) { // Peak detected
        totalRespirationCycles++;
      }
    }

    // Calculate HRV (SDNN) and respiratory rate only when the buffer is full
    if (validRRCount == BUFFER_SIZE) {
      // Calculate HRV (SDNN)
      float mean = 0;
      for (int i = 0; i < BUFFER_SIZE; i++) {
        mean += rrIntervals[i];
      }
      mean /= BUFFER_SIZE;

      float variance = 0;
      for (int i = 0; i < BUFFER_SIZE; i++) {
        variance += (rrIntervals[i] - mean) * (rrIntervals[i] - mean);
      }
      variance /= BUFFER_SIZE;

      float sdnn = sqrt(variance); // Standard Deviation of NN intervals

      // Calculate respiratory rate over the fixed time window
      unsigned long elapsedTime = millis() - startTime;
      if (elapsedTime >= RESPIRATION_WINDOW_MS) {
        int cyclesInWindow = totalRespirationCycles - previousRespirationCycles; // Cycles in the current window
        float respirationRate = (cyclesInWindow / (elapsedTime / 60000.0)); // Breaths per minute

        // Update rolling average
        rollingRespRate = ((rollingRespRate * rollingRespRateCount) + respirationRate) / (rollingRespRateCount + 1);
        rollingRespRateCount++;

        // Update previous cycle count and reset the timer
        previousRespirationCycles = totalRespirationCycles;
        startTime = millis(); // Reset the start time

        // Print HRV and respiratory rate
        Serial.print("HRV (SDNN in ms): ");
        Serial.println(sdnn);
        Serial.print("Respiratory Rate (breaths/min): ");
        Serial.println(rollingRespRate); // Print rolling average
      }
    }
  } else {
    Serial.println("Invalid heart rate detected. Please check the sensor or finger placement.");
  }

  delay(1000); // Slow down the loop
}