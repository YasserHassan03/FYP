#include <WiFi.h>
#include <WiFiUdp.h>
#include <FirebaseESP32.h>
#include <Wire.h>
#include <SparkFun_Bio_Sensor_Hub_Library.h>
#include "Secrets.h" // Define your WiFi and Firebase credentials in this file
#include <time.h>

// Secrets.h should contain:
// #define WIFI_SSID "your_wifi_ssid"
// #define WIFI_PASSWORD "your_wifi_password"
// #define FIREBASE_HOST "your-project.firebaseio.com"
// #define FIREBASE_AUTH "your-firebase-database-secret"

WiFiServer server(80);
WiFiClient client;
WiFiUDP udp;
const int discoveryPort = 8266;  // Port for device discovery

// Firebase and sensor setup
FirebaseData firebaseData;
FirebaseConfig config;
FirebaseAuth auth;
FirebaseJson json;

// Bio Sensor Hub initialization (adjust pins as needed)
// Reset pin = 4, MFIO pin = 5
SparkFun_Bio_Sensor_Hub bioHub(4, 5);
bioData body;

String userId = "";
String sessionId;
bool recording = false;

void setupWiFi() {
  Serial.println("Connecting to WiFi...");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected successfully!");
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nFailed to connect to WiFi. Please check credentials.");
  }
}

void setupFirebase() {
  config.database_url = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  
  Serial.println("Firebase initialized");
}

void setupBioSensor() {
  Wire.begin(21, 22); // SDA, SCL pins (adjust if needed)
  
  if (bioHub.begin() == 0) {
    Serial.println("Bio Sensor Hub initialized");
    bioHub.configBpm(MODE_TWO); // Configure for BPM and SpO2 readings
    Serial.println("Sensor in BPM mode");
  } else {
    Serial.println("Failed to initialize Bio Sensor Hub. Please check connections.");
  }
}

void setupTimeSync() {
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.println("Waiting for time synchronization...");
  
  int timeoutCounter = 0;
  while (time(nullptr) < 100000 && timeoutCounter < 20) {
    delay(500);
    Serial.print(".");
    timeoutCounter++;
  }
  
  if (time(nullptr) > 100000) {
    Serial.println("\nTime synchronized with NTP server");
    time_t now = time(nullptr);
    struct tm* timeinfo = gmtime(&now);
    char buffer[80];
    strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", timeinfo);
    Serial.print("Current UTC time: ");
    Serial.println(buffer);
  } else {
    Serial.println("\nFailed to sync time. Some features may not work correctly.");
  }
}

void setupDiscoveryService() {
  udp.begin(discoveryPort);
  Serial.println("ESP32 discovery service started on port " + String(discoveryPort));
}

void startSession(String newUserId) {
  userId = newUserId;

  // Generate session ID using UTC time
  time_t now = time(nullptr);
  struct tm* timeinfo = gmtime(&now); // Use gmtime for UTC
  char buffer[20];
  strftime(buffer, sizeof(buffer), "%Y%m%d%H%M%S", timeinfo);
  sessionId = String(buffer);

  // Create a new session in Firebase
  String sessionPath = "/users/" + userId + "/sessions/" + sessionId;
  json.clear();
  json.set("startTime", buffer);
  json.set("deviceId", WiFi.macAddress());
  Firebase.setJSON(firebaseData, sessionPath, json);

  if (firebaseData.httpCode() == FIREBASE_ERROR_HTTP_CODE_OK) {
    Serial.println("Recording started. Session ID: " + sessionId);
    recording = true;
  } else {
    Serial.print("Firebase error: ");
    Serial.println(firebaseData.errorReason());
    recording = false;
  }
}

void stopSession() {
  if (recording) {
    recording = false;
    Serial.println("Recording stopped.");
    
    // Update session end time if possible
    if (userId.length() > 0 && sessionId.length() > 0) {
      time_t now = time(nullptr);
      struct tm* timeinfo = gmtime(&now);
      char buffer[20];
      strftime(buffer, sizeof(buffer), "%Y%m%d%H%M%S", timeinfo);
      
      String sessionPath = "/users/" + userId + "/sessions/" + sessionId + "/endTime";
      Firebase.setString(firebaseData, sessionPath, buffer);
    }
  }
}

void handleDiscoveryRequests() {
  int packetSize = udp.parsePacket();
  if (packetSize) {
    char incomingPacket[255];
    int len = udp.read(incomingPacket, 255);
    if (len > 0) {
      incomingPacket[len] = 0;  // Null terminate the string
    }
    
    String request = String(incomingPacket);
    
    // Check if it's a discovery request
    if (request == "DISCOVER_ESP32") {
      // Send a response with device info
      IPAddress remoteIP = udp.remoteIP();
      uint16_t remotePort = udp.remotePort();
      
      String responseMsg = "ESP32_DEVICE:" + WiFi.macAddress();
      udp.beginPacket(remoteIP, remotePort);
      udp.print(responseMsg);
      udp.endPacket();
      
      Serial.println("Responded to discovery from " + remoteIP.toString());
    }
  }
}

void handleCommands() {
  if (server.hasClient()) {
    client = server.available();
    String cmd = client.readStringUntil('\n');
    cmd.trim();
    
    Serial.print("Received command: ");
    Serial.println(cmd);

    if (cmd.startsWith("START ")) {
      String uid = cmd.substring(6);
      Serial.print("Starting session for user: ");
      Serial.println(uid);
      startSession(uid);
      client.println("OK: Started recording");
    } else if (cmd == "STOP") {
      stopSession();
      client.println("OK: Stopped recording");
    } else {
      client.println("ERROR: Unknown command");
    }
    
    client.stop();
  }
}

void processAndSendSensorData() {
  if (recording) {
    // Get data from the sensor
    body = bioHub.readBpm();
    
    // Print sensor data to serial for debugging
    Serial.print("Status: ");
    Serial.print(body.status);
    Serial.print(", Heart rate: ");
    Serial.print(body.heartRate);
    Serial.print(", Oxygen: ");
    Serial.print(body.oxygen);
    Serial.print(", Confidence: ");
    Serial.println(body.confidence);
    
    // Only send to Firebase if the reading is valid
    if (body.status == 3 && body.confidence > 75) {
      json.clear();
      json.set("heartRate", body.heartRate);
      json.set("oxygen", body.oxygen);
      json.set("confidence", body.confidence);
      json.set("timestamp", time(nullptr));
      
      String readingsPath = "/users/" + userId + "/sessions/" + sessionId + "/readings";
      if (Firebase.pushJSON(firebaseData, readingsPath, json)) {
        Serial.println("Data sent to Firebase");
      } else {
        Serial.print("Failed to send data: ");
        Serial.println(firebaseData.errorReason());
      }
    } else if (body.status != 3) {
      Serial.println("Sensor is not ready or finger not detected");
    }
    
    // Delay between readings
    delay(1000);
  }
}

void checkWiFiConnection() {
  static unsigned long lastWiFiCheck = 0;
  unsigned long currentMillis = millis();
  
  // Check WiFi every 30 seconds
  if (currentMillis - lastWiFiCheck >= 30000) {
    lastWiFiCheck = currentMillis;
    
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("WiFi connection lost. Reconnecting...");
      WiFi.disconnect();
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
      
      // Wait up to 10 seconds for reconnection
      int attempts = 0;
      while (WiFi.status() != WL_CONNECTED && attempts < 20) {
        delay(500);
        Serial.print(".");
        attempts++;
      }
      
      if (WiFi.status() == WL_CONNECTED) {
        Serial.println("\nWiFi reconnected. IP: " + WiFi.localIP().toString());
      } else {
        Serial.println("\nFailed to reconnect to WiFi");
        
        // If recording, stop it to prevent data loss
        if (recording) {
          Serial.println("Stopping recording due to connection issues");
          recording = false;
        }
      }
    }
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("\n\n--- ESP32 Bio Sensor Hub Initializing ---");
  
  setupWiFi();
  setupDiscoveryService();
  server.begin();
  setupFirebase();
  setupBioSensor();
  setupTimeSync();
  
  Serial.println("System ready! Waiting for commands...");
}

void loop() {
  // Check WiFi connection
  checkWiFiConnection();
  
  // Handle discovery requests
  handleDiscoveryRequests();
  
  // Handle commands from app
  handleCommands();
  
  // Read and send sensor data if recording
  processAndSendSensorData();
}