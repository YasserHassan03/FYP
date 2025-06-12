// /*
//   Heart Rate and SpO2 Monitor with WiFi/Firebase Integration
//   For ESP32 with MAX30105 sensor
// */

// #include <Arduino.h>
// #include <Wire.h>
// #include <WiFi.h>
// #include <WiFiUdp.h>
// #include <FirebaseESP32.h>
// #include "MAX30105.h"
// #include "heartRate.h"
// #include "spo2_algorithm.h"
// #include "Secrets.h" // Define your WiFi and Firebase credentials in this file
// #include <time.h>
// #include "esp_wpa2.h"

// // Sensor and measurement variables
// MAX30105 particleSensor;

// // Heart Rate Variables
// const byte RATE_SIZE = 4; // Number of samples to average
// byte rates[RATE_SIZE]; // Array of heart rates
// byte rateSpot = 0;
// long lastBeat = 0; // Time at which the last beat occurred
// float beatsPerMinute;
// int beatAvg;

// // ESP32 pin assignments
// const int pulseLED = 19; // ESP32 PWM capable pin
// const int readLED = 2;   // ESP32 built-in LED

// // SpO2 Variables
// uint32_t irBuffer[100]; // IR sensor data buffer
// uint32_t redBuffer[100]; // Red sensor data buffer
// int32_t spo2; // SpO2 value
// int8_t validSPO2; // Indicator for valid SpO2
// int32_t bufferLength = 100; // Buffer length
// int sampleCounter = 0;
// unsigned long lastSampleTime = 0;
// unsigned long lastSpO2Update = 0;
// bool needSpO2Update = false;

// // Signal filtering variables
// #define USE_FILTER true  
// float alpha = 0.7;       // Higher alpha = less filtering but quicker response
// long irFiltered = 0;
// long redFiltered = 0;
// long irPrevious = 0;
// long redPrevious = 0;

// // Track if finger is present
// bool fingerPresent = false;
// unsigned long lastFingerCheck = 0;
// const unsigned long FINGER_TIMEOUT = 1000; // Time in ms to consider finger removed

// // HRV Variables (PPG-based)
// const int MAX_PPG_PEAKS = 500;
// unsigned long ppgPeakTimes[MAX_PPG_PEAKS];
// int ppgPeakCount = 0;
// unsigned long lastPPGPeakTime = 0;
// long ppgRRIntervals[MAX_PPG_PEAKS - 1];
// int ppgRRCount = 0;
// float sessionHRV = 0.0; // HRV for the entire session

// // Network and Firebase variables
// WiFiServer server(80);
// WiFiClient client;
// WiFiUDP udp;
// const int discoveryPort = 8266; // Port for device discovery

// // Firebase and sensor setup
// FirebaseData firebaseData;
// FirebaseConfig config;
// FirebaseAuth auth;
// FirebaseJson json;

// String userId = "";
// String sessionId;
// bool recording = false;

// // Function prototypes
// void setupWiFi();
// void setupFirebase();
// void setupTimeSync();
// void setupDiscoveryService();
// void startSession(String newUserId);
// void stopSession();
// void handleDiscoveryRequests();
// void handleCommands();
// void processAndSendSensorData();
// void checkWiFiConnection();
// long filterValue(long newValue, long prevValue);
// void resetHRValues();
// float calculateSessionHRV();

// // Main setup function
// void setup()
// {
//   Serial.begin(115200);
//   Serial.println("\n\n--- ESP32 Heart Rate & SpO2 Monitor Initializing ---");

//   // Set up LED pins
//   pinMode(pulseLED, OUTPUT);
//   pinMode(readLED, OUTPUT);
  
//   // Blink LED to show we're starting up
//   digitalWrite(readLED, HIGH);
//   delay(300);
//   digitalWrite(readLED, LOW);

//   // Setup WiFi first
//   setupWiFi();
  
//   // Setup discovery service for app connectivity
//   setupDiscoveryService();
//   server.begin();
  
//   // Setup Firebase for data storage
//   setupFirebase();
  
//   // Setup time synchronization (for timestamping data)
//   setupTimeSync();

//   // Now initialize the sensor
//   // ESP32 I2C pins (default: SDA=21, SCL=22)
//   Wire.begin(21, 22);

//   // Initialize sensor
//   if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) // Use default I2C port, 400kHz speed
//   {
//     Serial.println("MAX30105 was not found. Please check wiring/power.");
//     while (1) {
//       digitalWrite(readLED, !digitalRead(readLED));
//       delay(100);
//     }
//   }
//   Serial.println("MAX30105 found!");

//   // Use identical setup as the working code
//   particleSensor.setup();
//   particleSensor.setPulseAmplitudeRed(0x0A); // Match the working code's setting
//   particleSensor.setPulseAmplitudeGreen(0); // Turn off Green LED
  
//   // Initialize HR array
//   for (byte i = 0; i < RATE_SIZE; i++) {
//     rates[i] = 0;
//   }

//   // Initialize average heart rate to 75
//   beatAvg = 75;

//   // Initialize PPG peak detection
//   ppgPeakCount = 0;
//   ppgRRCount = 0;
  
//   Serial.println("Place your index finger on the sensor with steady pressure.");
//   Serial.println("System ready! Waiting for commands...");
// }

// // Main loop function
// void loop()
// {
//   // Check WiFi connection
//   checkWiFiConnection();

//   // Handle discovery requests from app
//   handleDiscoveryRequests();

//   // Handle commands from app
//   handleCommands();

//   // Get both IR and Red values
//   long irValue = particleSensor.getIR();
//   long redValue = particleSensor.getRed();
  
//   // Simple filtering
//   irFiltered = filterValue(irValue, irPrevious);
//   redFiltered = filterValue(redValue, redPrevious);
//   irPrevious = irFiltered;
//   redPrevious = redFiltered;
  
//   // Blink the read LED to show activity
//   if (millis() % 1000 < 50) {
//     digitalWrite(readLED, !digitalRead(readLED));
//   }

//   // Check for finger presence
//   bool currentFingerPresent = (irValue > 50000);
  
//   // Update finger present state
//   if (currentFingerPresent) {
//     fingerPresent = true;
//     lastFingerCheck = millis();
//   } else if (millis() - lastFingerCheck > FINGER_TIMEOUT) {
//     // No finger detected for a period - reset values
//     if (fingerPresent) {
//       resetHRValues(); // Only reset values when finger is first removed
//     }
//     fingerPresent = false;
//   }

//   // --- PPG Peak Detection for HRV ---
//   static long prev1 = 0, prev2 = 0;
//   if (fingerPresent) {
//     if (prev2 < prev1 && prev1 > irFiltered && prev1 > 50000) { // crude peak detection
//       unsigned long now = millis();
//       if (ppgPeakCount < MAX_PPG_PEAKS && (now - lastPPGPeakTime) > 300) { // ignore peaks too close (<300ms)
//         ppgPeakTimes[ppgPeakCount++] = now;
//         lastPPGPeakTime = now;
//       }
//     }
//     prev2 = prev1;
//     prev1 = irFiltered;
//   } else {
//     prev1 = 0;
//     prev2 = 0;
//   }
//   // --- End PPG Peak Detection ---

//   // Only process heart rate when finger is present
//   if (fingerPresent) {
//     // Heart rate detection using the proven method
//     if (checkForBeat(irValue) == true) // Use raw IR value like original code
//     {
//       // We sensed a beat!
//       digitalWrite(pulseLED, HIGH);
      
//       long delta = millis() - lastBeat;
//       lastBeat = millis();

//       beatsPerMinute = 60 / (delta / 1000.0);

//       if (beatsPerMinute < 255 && beatsPerMinute > 20)
//       {
//         rates[rateSpot++] = (byte)beatsPerMinute; // Store this reading in the array
//         rateSpot %= RATE_SIZE; // Wrap variable

//         // Take average of readings
//         beatAvg = 75;
//         for (byte x = 0; x < RATE_SIZE; x++)
//           beatAvg += rates[x];
//         beatAvg /= RATE_SIZE;
//       }
      
//       delay(20);
//       digitalWrite(pulseLED, LOW);
//     }

//     // Collect data for SpO2 calculation
//     if (millis() - lastSampleTime > 10) { // Sample at ~100Hz
//       lastSampleTime = millis();
      
//       // Store filtered values in buffer
//       irBuffer[sampleCounter] = irFiltered;
//       redBuffer[sampleCounter] = redFiltered;
//       sampleCounter++;
      
//       // Check if we have enough samples for SpO2
//       if (sampleCounter >= 100) {
//         needSpO2Update = true;
//         sampleCounter = 0;
//       }
//     }
    
//     // Update SpO2 calculation if needed
//     if (needSpO2Update && millis() - lastSpO2Update > 1000) {
//       int32_t tempHeartRate;
//       int8_t tempHRvalid;
      
//       maxim_heart_rate_and_oxygen_saturation(irBuffer, bufferLength, redBuffer, 
//                                             &spo2, &validSPO2, &tempHeartRate, &tempHRvalid);
      
//       lastSpO2Update = millis();
//       needSpO2Update = false;
//     }
//   } else {
//     // No finger present, ensure SpO2 isn't calculated with old data
//     needSpO2Update = false;
//     sampleCounter = 0;
//   }

//   // Process sensor data and send to Firebase if recording
//   processAndSendSensorData();

//   Serial.println("IP address: " + WiFi.localIP().toString());

//   // Print results to serial
//   Serial.print("IR=");
//   Serial.print(irValue);
  
//   // Only show BPM when finger is present
//   if (fingerPresent) {
//     Serial.print(", BPM=");
//     Serial.print(beatsPerMinute);
//     Serial.print(", Avg BPM=");
//     Serial.print(beatAvg);

//     // Show SpO2 when valid and finger is present
//     if (validSPO2 && spo2 > 0) {
//       Serial.print(", SpO2=");
//       Serial.print(spo2);
//       Serial.print("%");
//     }
//   } else {
//     Serial.print(" No finger detected");
//   }

//   Serial.println();
  
//   // Keep sampling interval similar to original code
//   delay(10);
// }

// // Reset heart rate values when finger is removed
// void resetHRValues() {
//   beatsPerMinute = 0;
//   beatAvg = 75; // Reset average heart rate to 75
//   lastBeat = 0;
  
//   // Reset the rates array
//   for (byte i = 0; i < RATE_SIZE; i++) {
//     rates[i] = 0;
//   }
  
//   // Reset SpO2 values
//   spo2 = 0;
//   validSPO2 = 0;

//   // Reset PPG peak detection
//   ppgPeakCount = 0;
//   ppgRRCount = 0;
//   lastPPGPeakTime = 0;
  
//   Serial.println("Finger removed - heart rate values reset");
// }

// // Function to calculate HRV (SDNN) for the entire session using PPG peaks
// float calculateSessionHRV()
// {
//   // Calculate RR intervals from PPG peaks
//   ppgRRCount = 0;
//   for (int i = 1; i < ppgPeakCount; i++) {
//     ppgRRIntervals[ppgRRCount++] = ppgPeakTimes[i] - ppgPeakTimes[i-1];
//   }
//   if (ppgRRCount == 0) return 0.0;

//   long sum = 0;
//   float mean = 0.0;

//   for (int i = 0; i < ppgRRCount; i++) {
//     sum += ppgRRIntervals[i];
//   }
//   mean = (float)sum / ppgRRCount;

//   float variance = 0.0;
//   for (int i = 0; i < ppgRRCount; i++) {
//     variance += pow(ppgRRIntervals[i] - mean, 2);
//   }
//   variance /= ppgRRCount;

//   return sqrt(variance); // SDNN
// }

// // Start a new recording session
// void startSession(String newUserId)
// {
//   userId = newUserId;

//   // Generate session ID using UTC time
//   time_t now = time(nullptr);
//   struct tm *timeinfo = gmtime(&now); // Use gmtime for UTC
//   char buffer[20];
//   strftime(buffer, sizeof(buffer), "%Y%m%d%H%M%S", timeinfo);
//   sessionId = String(buffer);

//   // Create a new session in Firebase
//   String sessionPath = "/users/" + userId + "/sessions/" + sessionId;
//   json.clear();
//   json.set("startTime", buffer);
//   json.set("deviceId", WiFi.macAddress());
//   Firebase.setJSON(firebaseData, sessionPath, json);

//   if (firebaseData.httpCode() == FIREBASE_ERROR_HTTP_CODE_OK)
//   {
//     Serial.println("Recording started. Session ID: " + sessionId);
//     recording = true;

//     // Reset session RR intervals (PPG)
//     ppgPeakCount = 0;
//     ppgRRCount = 0;
//     sessionHRV = 0.0;
//     lastPPGPeakTime = 0;
//   }
//   else
//   {
//     Serial.print("Firebase error: ");
//     Serial.println(firebaseData.errorReason());
//     recording = false;
//   }
// }

// // Stop the recording session
// void stopSession()
// {
//   if (recording)
//   {
//     recording = false;
//     Serial.println("Recording stopped.");

//     // Debug: Print RR intervals and count
//     Serial.print("PPG RR Intervals: ");
//     for (int i = 0; i < ppgRRCount; i++) {
//         Serial.print(ppgRRIntervals[i]);
//         Serial.print(" ");
//     }
//     Serial.println();
//     Serial.print("Number of PPG RR Intervals: ");
//     Serial.println(ppgRRCount);

//     // Calculate HRV for the session using PPG peaks
//     sessionHRV = calculateSessionHRV();
//     Serial.print("Session HRV (SDNN, PPG): ");
//     Serial.println(sessionHRV, 2);

//     // Update session end time and HRV in Firebase
//     if (userId.length() > 0 && sessionId.length() > 0)
//     {
//       time_t now = time(nullptr);
//       struct tm *timeinfo = gmtime(&now);
//       char buffer[20];
//       strftime(buffer, sizeof(buffer), "%Y%m%d%H%M%S", timeinfo);

//       String sessionPath = "/users/" + userId + "/sessions/" + sessionId;
//       Firebase.setString(firebaseData, sessionPath + "/endTime", buffer);

//       // Save HRV only if it is greater than 0
//       if (sessionHRV > 0) {
//           Firebase.setFloat(firebaseData, sessionPath + "/hrv", sessionHRV);
//       } else {
//           Serial.println("HRV is 0. Not saving to Firebase.");
//       }
//     }
//   }
// }

// // WiFi setup for WPA2 Enterprise
// void setupWiFi() {
//   Serial.println("Connecting to WPA2-Enterprise WiFi...");

//   // Set WiFi to station mode
//   WiFi.mode(WIFI_STA);

//   // Configure enterprise authentication
//   // esp_wifi_sta_wpa2_ent_set_identity((uint8_t *)WIFI_USERNAME, strlen(WIFI_USERNAME));
//   // esp_wifi_sta_wpa2_ent_set_username((uint8_t *)WIFI_USERNAME, strlen(WIFI_USERNAME));
//   // esp_wifi_sta_wpa2_ent_set_password((uint8_t *)WIFI_PASSWORD, strlen(WIFI_PASSWORD));
//   // esp_wifi_sta_wpa2_ent_enable();

//   // Begin connection with SSID only
//   WiFi.begin(iphoneName,iphonePassword);

//   int attempts = 0;
//   while (WiFi.status() != WL_CONNECTED && attempts < 20) {
//     delay(500);
//     Serial.print(".");
//     attempts++;
//   }

//   if (WiFi.status() == WL_CONNECTED) {
//     Serial.println("\nWiFi connected successfully!");
//     Serial.print("IP address: ");
//     Serial.println(WiFi.localIP());
//   } else {
//     Serial.println("\nFailed to connect to WiFi. Please check credentials.");
//   }
// }

// // Firebase setup
// void setupFirebase() {
//   config.database_url = FIREBASE_HOST;
//   config.signer.tokens.legacy_token = FIREBASE_AUTH;
//   Firebase.begin(&config, &auth);
//   Firebase.reconnectWiFi(true);

//   Serial.println("Firebase initialized");
// }

// // Time synchronization
// void setupTimeSync() {
//   configTime(0, 0, "pool.ntp.org", "time.nist.gov");
//   Serial.println("Waiting for time synchronization...");

//   int timeoutCounter = 0;
//   while (time(nullptr) < 100000 && timeoutCounter < 20) {
//     delay(500);
//     Serial.print(".");
//     timeoutCounter++;
//   }

//   if (time(nullptr) > 100000) {
//     Serial.println("\nTime synchronized");
//   } else {
//     Serial.println("\nFailed to synchronize time.");
//   }
// }

// // Discovery service setup
// void setupDiscoveryService() {
//   udp.begin(discoveryPort);
//   Serial.println("Discovery service started on port " + String(discoveryPort));
// }

// void checkWiFiConnection()
// {
//   static unsigned long lastWiFiCheck = 0;
//   unsigned long currentMillis = millis();

//   // Check WiFi every 30 seconds
//   if (currentMillis - lastWiFiCheck >= 30000)
//   {
//     lastWiFiCheck = currentMillis;
    
//     Serial.print("Checking WiFi connection... ");
    
//     if (WiFi.status() != WL_CONNECTED)
//     {
//       Serial.println("Disconnected. Reconnecting...");
      
//       // Important: Don't reconfigure WPA2 every time - this could cause the issue
//       WiFi.disconnect(true);  // True to disable/reset the WiFi
//       delay(1000);  // Give it time to clean up
      
//       // Begin connection with SSID only - the WPA2 settings should still be active
//       WiFi.begin(WIFI_SSID);

//       // Wait up to 10 seconds for reconnection with better handling
//       int attempts = 0;
//       while (WiFi.status() != WL_CONNECTED && attempts < 20)
//       {
//         delay(500);
//         Serial.print(".");
//         attempts++;
//       }

//       if (WiFi.status() == WL_CONNECTED)
//       {
//         Serial.println("\nWiFi reconnected!");
//         Serial.print("IP address: ");
//         Serial.println(WiFi.localIP());
//       }
//       else
//       {
//         Serial.println("\nFailed to reconnect to WiFi");
        
//         if (recording)
//         {
//           Serial.println("Stopping recording due to connection issues");
//           recording = false;
//         }
//       }
//     }
//     else
//     {
//       Serial.println("Connected! IP: " + WiFi.localIP().toString());
//     }
//   }
// }

// // Handle discovery requests
// void handleDiscoveryRequests() {
//   int packetSize = udp.parsePacket();
//   if (packetSize) {
//     char incomingPacket[255];
//     int len = udp.read(incomingPacket, 255);
//     if (len > 0) {
//       incomingPacket[len] = 0;
//     }

//     String request = String(incomingPacket);
//     if (request == "DISCOVER_ESP32") {
//       IPAddress remoteIP = udp.remoteIP();
//       uint16_t remotePort = udp.remotePort();
//       String response = "ESP32_DEVICE:" + WiFi.macAddress();
//       udp.beginPacket(remoteIP, remotePort);
//       udp.print(response);
//       udp.endPacket();
//     }
//   }
// }

// // Handle commands
// void handleCommands() {
//   if (server.hasClient()) {
//     client = server.available();
//     String command = client.readStringUntil('\n');
//     command.trim();

//     if (command.startsWith("START ")) {
//       String userId = command.substring(6);
//       startSession(userId);
//       client.println("OK: Recording started");
//     } else if (command == "STOP") {
//       stopSession();
//       client.println("OK: Recording stopped");
//     } else {
//       client.println("ERROR: Unknown command");
//     }

//     client.stop();
//   }
// }

// // Process and send sensor data
// void processAndSendSensorData() {
//   static unsigned long lastSendTime = 0;
//   if (recording && millis() - lastSendTime >= 1000) {
//     lastSendTime = millis();

//     if (fingerPresent && beatsPerMinute > 20 && beatsPerMinute < 255) {
//       json.clear();
//       json.set("heartRate", beatsPerMinute);
//       json.set("avgHeartRate", beatAvg);

//       if (validSPO2 && spo2 > 0) {
//         json.set("oxygen", spo2);
//       }

//       json.set("timestamp", time(nullptr));
//       String path = "/users/" + userId + "/sessions/" + sessionId + "/readings";
//       Firebase.pushJSON(firebaseData, path, json);
//     }
//   }
// }

// // Simple filter function
// long filterValue(long newValue, long prevValue) {
//   if (USE_FILTER) {
//     if (prevValue == 0) return newValue; // First reading
//     return (long)(alpha * newValue + (1 - alpha) * prevValue);
//   } else {
//     return newValue; // No filtering
//   }
// }