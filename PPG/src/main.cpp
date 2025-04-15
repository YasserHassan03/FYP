#include <WiFi.h>
#include <FirebaseESP32.h>
#include <Wire.h>
#include <SparkFun_Bio_Sensor_Hub_Library.h>
#include "Secrets.h" // Include the secrets.h file with credentials
#include <time.h>

// Reset pin, MFIO pin
int resPin = 4;
int mfioPin = 5;

// Takes address, reset pin, and MFIO pin.
SparkFun_Bio_Sensor_Hub bioHub(resPin, mfioPin);

bioData body;

// Define Firebase Data object
FirebaseData firebaseData;
FirebaseConfig config;
FirebaseAuth auth;
FirebaseJson json;

// User ID - This would typically be set during device configuration
String userId = "user123"; // Replace with actual user ID or configuration method

// Unique session ID
String sessionId;

void setup()
{
  Serial.begin(115200);

  // Connect to Wi-Fi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED)
  {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nConnected to Wi-Fi");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  // Initialize Firebase with modern API
  config.database_url = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // Initialize I2C
  Wire.begin(21, 22); // SDA = GPIO 21, SCL = GPIO 22

  // Initialize Bio Sensor
  int result = bioHub.begin();
  if (result == 0)
    Serial.println("Sensor started!");
  else
    Serial.println("Could not communicate with the sensor!");

  Serial.println("Configuring Sensor....");
  int error = bioHub.configBpm(MODE_TWO); // Configuring just the BPM settings.
  if (error == 0)
  { // Zero errors
    Serial.println("Sensor configured.");
  }
  else
  {
    Serial.println("Error configuring sensor.");
    Serial.print("Error: ");
    Serial.println(error);
  }

  Serial.println("Loading up the buffer with data....");
  delay(4000);

  // Sync time via NTP
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  while (time(nullptr) < 100000)
  {
    delay(100);
  }

  time_t now = time(nullptr);
  char buffer[20];
  strftime(buffer, sizeof(buffer), "%Y%m%d%H%M%S", localtime(&now));
  sessionId = String(buffer); // Don't redeclare with 'String' again here

  // Create a new session entry
  String sessionPath = "/users/" + userId + "/sessions/" + sessionId;
  json.clear();
  json.set("startTime", "Session started");
  json.set("deviceId", WiFi.macAddress());
  Firebase.setJSON(firebaseData, sessionPath, json);
}

void loop()
{
  // Read data from the sensor
  body = bioHub.readBpm();

  // Check if a finger is detected
  if (body.status != 3)
  { // 3 indicates a finger is detected
    Serial.println("No finger detected. Please place your finger on the sensor.");
    delay(1000);
    return;
  }

  if (body.confidence < 75)
  {
    Serial.println("Low confidence in readings. Please adjust finger placement.");
    delay(1000);
    return;
  }

  // Print heart rate, blood oxygen, and confidence
  Serial.print("Heartrate (BPM): ");
  Serial.println(body.heartRate);
  Serial.print("Blood Oxygen (%): ");
  Serial.println(body.oxygen);
  Serial.print("Confidence (%): ");
  Serial.println(body.confidence);

  // Create a JSON object with the reading data
  json.clear();
  json.set("heartRate", body.heartRate);
  json.set("oxygen", body.oxygen);
  json.set("confidence", body.confidence);

  // Create paths that include the user ID and session ID
  String readingsPath = "/users/" + userId + "/sessions/" + sessionId + "/readings";

  // Push to Firebase under the user's own data path
  if (Firebase.pushJSON(firebaseData, readingsPath, json))
  {
    Serial.println("Data sent to Firebase successfully");
  }
  else
  {
    Serial.print("Failed to send data: ");
    Serial.println(firebaseData.errorReason());
  }

  delay(1000); // Adjust delay as needed
}