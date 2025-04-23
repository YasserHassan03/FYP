import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LiveSensorData extends StatefulWidget {
  const LiveSensorData({Key? key}) : super(key: key);

  @override
  State<LiveSensorData> createState() => _LiveSensorDataState();
}

class _LiveSensorDataState extends State<LiveSensorData> {
  String? espIp;
  bool isRecording = false;
  String sessionId = "";
  Timer? pollingTimer;
  Timer? discoveryTimer;

  List<String> discoveredDevices = [];
  bool isScanning = false;
  bool isPaired = false;

  List<FlSpot> heartRateData = [];
  List<FlSpot> oxygenData = [];

  double averageHeartRate = 0;
  double averageOxygen = 0;
  int timeCounter = 0;
  String? lastProcessedKey;
  bool isLookingForSession = false;

  DatabaseReference? databaseRef;

  @override
  void initState() {
    super.initState();
    loadSavedDevice();
  }

  Future<void> loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('esp_ip');

    if (savedIp != null) {
      setState(() {
        espIp = savedIp;
        isPaired = true;
      });
    }
  }

  Future<void> saveDevice(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', ip);
  }

  Future<void> sendCommand(String command) async {
    if (espIp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pair with an ESP32 device first')),
      );
      return;
    }

    try {
      final socket = await Socket.connect(
        espIp,
        80,
        timeout: const Duration(seconds: 2),
      );
      socket.write('$command\n');
      await socket.flush();
      socket.destroy();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting to ESP32: $e')),
        );
      }
      print('Error sending command: $e');
    }
  }

  Future<void> startDeviceDiscovery() async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
      discoveredDevices = [];
    });

    try {
      // Create UDP socket for broadcasting
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Listen for responses
      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final message = String.fromCharCodes(datagram.data);
            if (message.startsWith('ESP32_DEVICE:')) {
              final deviceIp = datagram.address.address;
              if (!discoveredDevices.contains(deviceIp)) {
                setState(() {
                  discoveredDevices.add(deviceIp);
                });
              }
            }
          }
        }
      });

      // Send discovery broadcast
      final broadcastAddr = InternetAddress('255.255.255.255');
      final data = utf8.encode('DISCOVER_ESP32');

      // Send discovery request multiple times
      discoveryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        socket.send(data, broadcastAddr, 8266); // Using port 8266 for discovery

        // Stop after 5 seconds
        if (timer.tick >= 5) {
          timer.cancel();
          socket.close();
          if (mounted) {
            setState(() {
              isScanning = false;
            });
          }
        }
      });
    } catch (e) {
      print('Error during device discovery: $e');
      setState(() {
        isScanning = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error scanning for devices: $e')));
    }
  }

  void pairWithDevice(String ip) async {
    try {
      // Test connection before pairing
      final socket = await Socket.connect(
        ip,
        80,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();

      // Save the device IP
      await saveDevice(ip);

      setState(() {
        espIp = ip;
        isPaired = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully paired with device at $ip')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect to device at $ip: $e')),
      );
    }
  }

  void unpairDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('esp_ip');

    setState(() {
      espIp = null;
      isPaired = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Device unpaired')));
  }

  void toggleRecording() async {
    if (!isPaired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pair with an ESP32 device first')),
      );
      return;
    }

    if (!isRecording) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User not logged in.')));
        print("User not logged in");
        return;
      }

      final uid = user.uid;

      // Generate session ID using UTC time
      final now = DateTime.now().toUtc(); // Use UTC time
      sessionId = DateFormat('yyyyMMddHHmmss').format(now);

      print("App generated session ID: $sessionId");

      await sendCommand("START $uid");
      await Future.delayed(const Duration(seconds: 2));

      // Reset data
      setState(() {
        heartRateData.clear();
        oxygenData.clear();
        timeCounter = 0;
        averageHeartRate = 0;
        averageOxygen = 0;
        lastProcessedKey = null;
        isLookingForSession = true;
      });

      // Start polling the database with session lookup
      startPollingWithSessionLookup(uid);

      setState(() {
        isRecording = true;
      });
    } else {
      await sendCommand("STOP");

      // Stop polling the database
      pollingTimer?.cancel();
      pollingTimer = null;

      setState(() {
        isLookingForSession = false;
        isRecording = false;
      });

      // Show questionnaire after stopping recording
      _showPostSessionQuestionnaire();
    }
  }

  void _showPostSessionQuestionnaire() {
    // Values to store user responses
    int stressLevel = 5;
    bool hadCoffee = false;
    TimeOfDay coffeeTime =
        TimeOfDay.now(); // Using TimeOfDay instead of hours count
    int sleepQuality = 3; // 1-5 scale
    int daysPreComp = 1; // 1-10 scale
    bool tookMedication = false;
    String medications = '';

    showDialog(
      context: context,
      barrierDismissible: false, // User must respond to the dialog
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Post-Session Questionnaire',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    // Stress level question
                    const Text('How stressed do you feel right now?'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('1', style: TextStyle(fontSize: 12)),
                        Text('10', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Slider(
                      value: stressLevel.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9, // Makes the slider discrete (1-10)
                      label: stressLevel.toString(),
                      onChanged: (double value) {
                        setState(() {
                          stressLevel = value.round();
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Coffee question
                    const Text('Have you had any coffee today?'),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('Yes'),
                            value: true,
                            groupValue: hadCoffee,
                            onChanged: (bool? value) {
                              setState(() {
                                hadCoffee = value ?? false;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('No'),
                            value: false,
                            groupValue: hadCoffee,
                            onChanged: (bool? value) {
                              setState(() {
                                hadCoffee = value ?? false;
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    // Follow-up coffee time question (only if hadCoffee is true)
                    if (hadCoffee) ...[
                      const Text('What time did you have coffee today?'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final TimeOfDay? pickedTime = await showTimePicker(
                            context: context,
                            initialTime: coffeeTime,
                          );
                          if (pickedTime != null) {
                            setState(() {
                              coffeeTime = pickedTime;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Time: ${coffeeTime.format(context)}',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const Icon(Icons.access_time),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Sleep quality question
                    const Text('How well did you sleep last night?'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Very poorly (1)', style: TextStyle(fontSize: 12)),
                        Text('Very well (5)', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Slider(
                      value: sleepQuality.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4, // Makes the slider discrete (1-5)
                      label: sleepQuality.toString(),
                      onChanged: (double value) {
                        setState(() {
                          sleepQuality = value.round();
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Days pre-comp question
                    const Text('How many days pre-competition are you?'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('1 day', style: TextStyle(fontSize: 12)),
                        Text('10 days', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Slider(
                      value: daysPreComp.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9, // Makes the slider discrete (1-10)
                      label:
                          '$daysPreComp ${daysPreComp == 1 ? 'day' : 'days'}',
                      onChanged: (double value) {
                        setState(() {
                          daysPreComp = value.round();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              actions: <Widget>[
                ElevatedButton(
                  child: const Text('Submit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: Size(double.infinity, 45), // Full width button
                  ),
                  onPressed: () {
                    // Convert TimeOfDay to a storable format (hours and minutes since midnight)
                    final coffeeTimeMinutes =
                        coffeeTime.hour * 60 + coffeeTime.minute;
                    final now = TimeOfDay.now();
                    final nowMinutes = now.hour * 60 + now.minute;

                    // Calculate minutes between coffee time and now
                    int minutesSinceCoffee = 0;
                    if (coffeeTimeMinutes <= nowMinutes) {
                      minutesSinceCoffee = nowMinutes - coffeeTimeMinutes;
                    } else {
                      // If coffee time was "yesterday" (after midnight but before now)
                      minutesSinceCoffee =
                          (24 * 60 - coffeeTimeMinutes) + nowMinutes;
                    }

                    // Save with coffee time information
                    _saveQuestionnaireData({
                      'stressLevel': stressLevel,
                      'hadCoffee': hadCoffee,
                      'coffeeTime':
                          hadCoffee ? coffeeTime.format(context) : null,
                      'minutesSinceCoffee':
                          hadCoffee ? minutesSinceCoffee : null,
                      'sleepQuality': sleepQuality,
                      'daysPreCompetition': daysPreComp,
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Update the saveQuestionnaireData method to handle the new question format
  void _saveQuestionnaireData(Map<String, dynamic> questionnaireData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || sessionId.isEmpty) {
        print("Cannot save questionnaire: User not logged in or no session ID");
        return;
      }

      // Add session summary data (averages)
      questionnaireData['averageHeartRate'] = averageHeartRate;
      questionnaireData['averageOxygen'] = averageOxygen;
      questionnaireData['timestamp'] = ServerValue.timestamp;

      // Save to Firebase
      final databaseRef = FirebaseDatabase.instance.ref().child(
        "users/${user.uid}/sessions/$sessionId/questionnaire",
      );

      await databaseRef.set(questionnaireData);

      // Show success message
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Text('Success'),
                ],
              ),
              content: const Text(
                'Your session data has been saved successfully.',
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      print("Error saving questionnaire data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save session data: $e')),
        );
      }
    }
  }

  void startPollingWithSessionLookup(String uid) {
    pollingTimer?.cancel(); // Cancel any existing timer

    // Keep track of session discovery attempts
    int sessionSearchAttempts = 0;
    String? actualSessionId;

    pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        if (isLookingForSession) {
          sessionSearchAttempts++;

          // Generate a list of potential session IDs (current +/- 5 seconds)
          final baseTime = DateTime.now().toUtc().subtract(
            Duration(seconds: sessionSearchAttempts * 2),
          );
          List<String> potentialSessionIds = [];

          // Check IDs within a 10-second window around our base time
          for (int i = -5; i <= 15; i++) {
            final adjustedTime = baseTime.add(Duration(seconds: i));
            potentialSessionIds.add(
              DateFormat('yyyyMMddHHmmss').format(adjustedTime),
            );
          }

          // Query the database for sessions
          final sessionsRef = FirebaseDatabase.instance.ref().child(
            "users/$uid/sessions",
          );
          final snapshot = await sessionsRef.get();

          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            final availableSessions =
                data.keys.map((e) => e.toString()).toList();

            // Find a matching session from our potential IDs
            for (String potentialId in potentialSessionIds) {
              if (availableSessions.contains(potentialId)) {
                print(
                  "Found matching session ID: $potentialId (originally generated: $sessionId)",
                );
                actualSessionId = potentialId;
                // Fix the nullable assignment error here:
                sessionId =
                    actualSessionId!; // Use null assertion since we know it's not null at this point
                setState(() {
                  isLookingForSession = false;
                });
                break;
              }
            }

            // If no session found and we've tried enough times, give up
            if (isLookingForSession && sessionSearchAttempts >= 15) {
              print(
                "Failed to find a matching session after $sessionSearchAttempts attempts.",
              );
              setState(() {
                isLookingForSession = false;
              });

              // Show error to user
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not find session data. Please try recording again.',
                    ),
                  ),
                );
              }
            }
          }
        }

        // Continue with normal polling using the found or original session ID
        if (!isLookingForSession) {
          final sessionRef = FirebaseDatabase.instance.ref().child(
            "users/$uid/sessions/$sessionId/readings",
          );
          final snapshot = await sessionRef.get();

          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            List<double> heartRates = [];
            List<double> oxygenValues = [];

            // Sort entries by key to process them in order
            List<MapEntry<dynamic, dynamic>> sortedEntries =
                data.entries.toList()..sort(
                  (a, b) => a.key.toString().compareTo(b.key.toString()),
                );

            // Find where to start processing (after last processed key)
            int startIndex = 0;
            if (lastProcessedKey != null) {
              startIndex = sortedEntries.indexWhere(
                (entry) => entry.key == lastProcessedKey,
              );
              if (startIndex >= 0)
                startIndex++; // Start after the last processed
              else
                startIndex = 0; // If not found, process all
            }

            // Only process new entries
            bool hasNewData = false;
            for (int i = startIndex; i < sortedEntries.length; i++) {
              var entry = sortedEntries[i];
              lastProcessedKey = entry.key; // Update last processed key

              final reading = entry.value as Map<dynamic, dynamic>;
              double hr = (reading["heartRate"] ?? 0).toDouble();
              double ox = (reading["oxygen"] ?? 0).toDouble();

              if (hr > 0) heartRates.add(hr);
              if (ox > 0) oxygenValues.add(ox);

              setState(() {
                heartRateData.add(FlSpot(timeCounter.toDouble(), hr));
                if (ox > 0) {
                  // Only add oxygen if it's greater than zero
                  oxygenData.add(FlSpot(timeCounter.toDouble(), ox));
                }
                timeCounter++;

                // Limit the number of points to prevent memory issues
                if (heartRateData.length > 100) {
                  heartRateData.removeAt(0);
                }
                if (oxygenData.length > 100) {
                  oxygenData.removeAt(0);
                }
              });

              hasNewData = true;
            }

            // Only update averages if we have new data
            if (hasNewData) {
              // Calculate averages using all valid data
              setState(() {
                // Calculate heart rate average from all values
                if (heartRateData.isNotEmpty) {
                  double total = 0;
                  int count = 0;
                  for (var point in heartRateData) {
                    if (point.y > 0) {
                      total += point.y;
                      count++;
                    }
                  }
                  averageHeartRate = count > 0 ? total / count : 0;
                }

                // Calculate oxygen average only from non-zero values
                if (oxygenData.isNotEmpty) {
                  double total = 0;
                  int count = 0;
                  for (var point in oxygenData) {
                    if (point.y > 0) {
                      total += point.y;
                      count++;
                    }
                  }
                  averageOxygen = count > 0 ? total / count : 0;
                }
              });
            }
          } else if (!isLookingForSession) {
            print("No data found for session $sessionId.");
          }
        }
      } catch (e) {
        print("Error polling database: $e");
      }
    });
  }

  Widget buildPairingSection() {
    return Card(
      elevation: 4,
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "📱 Device Connection",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                if (isPaired)
                  IconButton(
                    icon: Icon(Icons.link_off, color: Colors.red),
                    onPressed: unpairDevice,
                    tooltip: 'Unpair device',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            isPaired
                ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Connected to ESP32 at $espIp",
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                )
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: isScanning ? null : startDeviceDiscovery,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        isScanning ? "Scanning..." : "Scan for ESP32 Devices",
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isScanning)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    if (discoveredDevices.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          "Available Devices:",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      ...discoveredDevices.map(
                        (ip) => ListTile(
                          leading: Icon(Icons.wifi, color: Colors.blue),
                          title: Text("ESP32 at $ip"),
                          onTap: () => pairWithDevice(ip),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                    if (!isScanning && discoveredDevices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          "No devices found. Make sure your ESP32 is powered on and connected to the same WiFi network.",
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  Widget buildScoreboard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8), // Semi-transparent white
        borderRadius: BorderRadius.circular(12), // Rounded corners
        boxShadow: [
          BoxShadow(
            color: Colors.black12, // Subtle shadow
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "📊 Average Metrics",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87, // Dark text for contrast
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.favorite, color: Colors.red),
              SizedBox(width: 8),
              Text(
                "Average Heart Rate: ${averageHeartRate.toStringAsFixed(1)} bpm",
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
          SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.air, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                "Average Oxygen: ${averageOxygen.toStringAsFixed(1)} %",
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
          if (isLookingForSession)
            Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: Row(
                children: [
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Looking for session data...",
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget buildLiveChart(List<FlSpot> data, String title, Color color) {
    // Filter out zero oxygen values if this is oxygen data
    List<FlSpot> filteredData =
        title.contains("Oxygen")
            ? data.where((spot) => spot.y > 0).toList()
            : data;

    // Set default values based on chart type
    double defaultMin = 0;
    double defaultMax = title.contains("Oxygen") ? 100 : 120;

    // Set sensible defaults for each chart type
    double centerValue = title.contains("Oxygen") ? 98 : 75;
    double rangeSize = title.contains("Oxygen") ? 10 : 40;

    // Get min and max values to help with proper scaling
    double maxY = defaultMax;
    double minY = defaultMin;

    if (filteredData.isNotEmpty) {
      // Find actual min/max from data
      maxY = filteredData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
      minY = filteredData.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);

      // Ensure we have a reasonable range
      if (maxY - minY < 10) {
        // Center around the actual data
        centerValue = (maxY + minY) / 2;
        // Expand range to minimum size
        minY = centerValue - rangeSize / 2;
        maxY = centerValue + rangeSize / 2;
      }
    } else {
      // No data, use defaults
      minY = centerValue - rangeSize / 2;
      maxY = centerValue + rangeSize / 2;
    }

    // Add padding
    double padding = (maxY - minY) * 0.2; // 20% padding
    if (padding < 5) padding = 5; // Minimum padding

    double minYAxis = max(0, minY - padding);
    double maxYAxis = maxY + padding;

    // Make sure horizontalInterval is not zero by ensuring a minimum range
    double range = maxYAxis - minYAxis;
    if (range < 20) {
      // Expand the range if it's too small
      maxYAxis = minYAxis + 20;
    }

    // Fixed safe value for horizontal interval
    double horizontalInterval = 10; // Use a safe fixed value

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minY: minYAxis,
              maxY: maxYAxis,
              lineBarsData: [
                LineChartBarData(
                  spots:
                      filteredData.isNotEmpty
                          ? filteredData
                          : [FlSpot(0, centerValue)], // Center point if empty
                  isCurved: true,
                  barWidth: 2,
                  color: color,
                  dotData: FlDotData(show: false),
                ),
              ],
              titlesData: FlTitlesData(
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: false, // Hide bottom titles to remove numbers
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: horizontalInterval, // Use fixed safe value
                verticalInterval: 20,
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    discoveryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF74EBD5), Color(0xFFACB6E5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),
                  buildPairingSection(),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: isPaired ? toggleRecording : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecording ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                      disabledBackgroundColor: Colors.grey,
                    ),
                    child: Text(
                      isRecording ? "Stop Recording" : "Start Recording",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  buildScoreboard(),
                  const SizedBox(height: 20),
                  buildLiveChart(heartRateData, "Heart Rate (BPM)", Colors.red),
                  const SizedBox(height: 20),
                  buildLiveChart(oxygenData, "Blood Oxygen (%)", Colors.blue),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
