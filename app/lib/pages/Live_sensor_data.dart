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
  final String hardcodedIp = "172.26.238.8";
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
  int chartTime = 0;
  String? lastProcessedKey;
  bool isLookingForSession = false;

  // HR buffer for consecutive readings logic
  List<double> hrBuffer = [];

  DatabaseReference? databaseRef;

  @override
  void initState() {
    super.initState();
    useHardcodedIp();
  }

  void useHardcodedIp() async {
    try {
      await testConnection(hardcodedIp);
      setState(() {
        espIp = hardcodedIp;
        isPaired = true;
      });
      await saveDevice(hardcodedIp);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Using ESP32 at $hardcodedIp')),
      );
    } catch (e) {
      print('Error connecting to hardcoded IP: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not connect to ESP32 at $hardcodedIp: $e')),
      );
      loadSavedDevice();
    }
  }

  Future<void> testConnection(String ip) async {
    final socket = await Socket.connect(
      ip,
      80,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
  }

  Future<void> loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('esp_ip');
    if (savedIp != null) {
      try {
        await testConnection(savedIp);
        setState(() {
          espIp = savedIp;
          isPaired = true;
        });
      } catch (e) {
        print('Saved device at $savedIp is not reachable: $e');
        await prefs.remove('esp_ip');
      }
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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String inputIp = hardcodedIp;
        return AlertDialog(
          title: Text('Enter ESP32 IP Address'),
          content: TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: hardcodedIp,
              labelText: 'IP Address',
            ),
            onChanged: (value) {
              inputIp = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                pairWithDevice(inputIp);
              },
              child: Text('Connect'),
            ),
          ],
        );
      },
    );
    if (isScanning) return;
    setState(() {
      isScanning = true;
      discoveredDevices = [];
    });
    try {
      setState(() {
        if (!discoveredDevices.contains(hardcodedIp)) {
          discoveredDevices.add(hardcodedIp);
        }
      });
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
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
      final broadcastAddr = InternetAddress('255.255.255.255');
      final data = utf8.encode('DISCOVER_ESP32');
      discoveryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        socket.send(data, broadcastAddr, 8266);
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
      final socket = await Socket.connect(
        ip,
        80,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
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

  void reconnectToHardcodedIp() async {
    try {
      await testConnection(hardcodedIp);
      setState(() {
        espIp = hardcodedIp;
        isPaired = true;
      });
      await saveDevice(hardcodedIp);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reconnected to ESP32 at $hardcodedIp')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect to ESP32 at $hardcodedIp: $e')),
      );
    }
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
      final now = DateTime.now().toUtc();
      sessionId = DateFormat('yyyyMMddHHmmss').format(now);
      print("App generated session ID: $sessionId");
      await sendCommand("START $uid");
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        heartRateData.clear();
        oxygenData.clear();
        timeCounter = 0;
        chartTime = 0;
        averageHeartRate = 0;
        averageOxygen = 0;
        lastProcessedKey = null;
        isLookingForSession = true;
        hrBuffer.clear();
      });
      startPollingWithSessionLookup(uid);
      setState(() {
        isRecording = true;
      });
    } else {
      await sendCommand("STOP");
      pollingTimer?.cancel();
      pollingTimer = null;
      setState(() {
        isLookingForSession = false;
        isRecording = false;
      });
      _showPostSessionQuestionnaire();
    }
  }

  void _showPostSessionQuestionnaire() {
    int stressLevel = 5;
    bool hadCoffee = false;
    TimeOfDay coffeeTime = TimeOfDay.now();
    int sleepQuality = 3;
    int daysPreComp = 1;

    showDialog(
      context: context,
      barrierDismissible: false,
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
                      divisions: 9,
                      label: stressLevel.toString(),
                      onChanged: (double value) {
                        setState(() {
                          stressLevel = value.round();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
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
                      divisions: 4,
                      label: sleepQuality.toString(),
                      onChanged: (double value) {
                        setState(() {
                          sleepQuality = value.round();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
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
                      divisions: 9,
                      label: '$daysPreComp ${daysPreComp == 1 ? 'day' : 'days'}',
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
                    minimumSize: Size(double.infinity, 45),
                  ),
                  onPressed: () {
                    final coffeeTimeMinutes =
                        coffeeTime.hour * 60 + coffeeTime.minute;
                    final now = TimeOfDay.now();
                    final nowMinutes = now.hour * 60 + now.minute;
                    int minutesSinceCoffee = 0;
                    if (coffeeTimeMinutes <= nowMinutes) {
                      minutesSinceCoffee = nowMinutes - coffeeTimeMinutes;
                    } else {
                      minutesSinceCoffee =
                          (24 * 60 - coffeeTimeMinutes) + nowMinutes;
                    }
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

  void _saveQuestionnaireData(Map<String, dynamic> questionnaireData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || sessionId.isEmpty) {
        print("Cannot save questionnaire: User not logged in or no session ID");
        return;
      }
      questionnaireData['averageHeartRate'] = averageHeartRate;
      questionnaireData['averageOxygen'] = averageOxygen;
      questionnaireData['timestamp'] = ServerValue.timestamp;
      final databaseRef = FirebaseDatabase.instance.ref().child(
        "users/${user.uid}/sessions/$sessionId/questionnaire",
      );
      await databaseRef.set(questionnaireData);
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
    pollingTimer?.cancel();
    int sessionSearchAttempts = 0;
    String? actualSessionId;
    List<double> allHeartRates = [];
    List<double> allOxygenLevels = [];
    hrBuffer.clear();

    pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        if (isLookingForSession) {
          sessionSearchAttempts++;
          final baseTime = DateTime.now().toUtc().subtract(
            Duration(seconds: sessionSearchAttempts * 2),
          );
          List<String> potentialSessionIds = [];
          for (int i = -5; i <= 15; i++) {
            final adjustedTime = baseTime.add(Duration(seconds: i));
            potentialSessionIds.add(
              DateFormat('yyyyMMddHHmmss').format(adjustedTime),
            );
          }
          final sessionsRef = FirebaseDatabase.instance.ref().child(
            "users/$uid/sessions",
          );
          final snapshot = await sessionsRef.get();
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            final availableSessions =
                data.keys.map((e) => e.toString()).toList();
            for (String potentialId in potentialSessionIds) {
              if (availableSessions.contains(potentialId)) {
                actualSessionId = potentialId;
                sessionId = actualSessionId!;
                setState(() {
                  isLookingForSession = false;
                });
                break;
              }
            }
            if (isLookingForSession && sessionSearchAttempts >= 15) {
              setState(() {
                isLookingForSession = false;
              });
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
        if (!isLookingForSession) {
          final sessionRef = FirebaseDatabase.instance.ref().child(
            "users/$uid/sessions/$sessionId/readings",
          );
          final snapshot = await sessionRef.get();
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            List<MapEntry<dynamic, dynamic>> sortedEntries =
                data.entries.toList()..sort(
                  (a, b) => a.key.toString().compareTo(b.key.toString()),
                );
            int startIndex = 0;
            if (lastProcessedKey != null) {
              startIndex = sortedEntries.indexWhere(
                (entry) => entry.key == lastProcessedKey,
              );
              if (startIndex >= 0)
                startIndex++;
              else
                startIndex = 0;
            }
            bool hasNewData = false;
            for (int i = startIndex; i < sortedEntries.length; i++) {
              var entry = sortedEntries[i];
              lastProcessedKey = entry.key;
              final reading = entry.value as Map<dynamic, dynamic>;
              double hr = (reading["heartRate"] ?? 0).toDouble();
              double ox = (reading["oxygen"] ?? 0).toDouble();

              // --- HR logic with buffer ---
              if (hr > 0) {
                if (heartRateData.isEmpty) {
                  // Always add the first value
                  heartRateData.add(FlSpot(chartTime.toDouble(), hr));
                  chartTime++;
                  allHeartRates.add(hr);
                  hrBuffer.clear();
                } else {
                  double lastHr = heartRateData.last.y;
                  if ((hr - lastHr).abs() <= 5) {
                    // Normal case: within 5bpm, plot and clear buffer
                    heartRateData.add(FlSpot(chartTime.toDouble(), hr));
                    chartTime++;
                    allHeartRates.add(hr);
                    hrBuffer.clear();
                  } else {
                    // Outlier: buffer it
                    hrBuffer.add(hr);
                    if (hrBuffer.length > 5) {
                      hrBuffer.removeAt(0);
                    }
                    // If buffer has 5 consecutive readings within 5bpm of each other, plot the 5th
                    if (hrBuffer.length == 5) {
                      bool allWithin5 = true;
                      for (int j = 1; j < hrBuffer.length; j++) {
                        if ((hrBuffer[j] - hrBuffer[j - 1]).abs() > 5) {
                          allWithin5 = false;
                          break;
                        }
                      }
                      if (allWithin5) {
                        // Plot the 5th reading, even if it's >5bpm from lastHr
                        heartRateData.add(FlSpot(chartTime.toDouble(), hrBuffer.last));
                        chartTime++;
                        allHeartRates.add(hrBuffer.last);
                        hrBuffer.clear();
                      }
                    }
                  }
                }
              }
              // Only add SpO2 if >= 95
              if (ox >= 95) {
                oxygenData.add(FlSpot(oxygenData.length.toDouble(), ox));
                allOxygenLevels.add(ox);
              }
              hasNewData = true;
            }
            if (hasNewData) {
              setState(() {
                if (allHeartRates.isNotEmpty) {
                  averageHeartRate =
                      allHeartRates.reduce((a, b) => a + b) / allHeartRates.length;
                }
                if (allOxygenLevels.isNotEmpty) {
                  averageOxygen =
                      allOxygenLevels.reduce((a, b) => a + b) / allOxygenLevels.length;
                }
                if (heartRateData.length > 100) {
                  heartRateData = heartRateData.sublist(heartRateData.length - 100);
                }
                if (oxygenData.length > 100) {
                  oxygenData = oxygenData.sublist(oxygenData.length - 100);
                }
              });
            }
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
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
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
                      ),
                      ElevatedButton(
                        onPressed: reconnectToHardcodedIp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          "Connect to Hardcoded IP ($hardcodedIp)",
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: startDeviceDiscovery,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          "Enter Custom IP Address",
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: reconnectToHardcodedIp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          "Connect to Hardcoded IP ($hardcodedIp)",
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: startDeviceDiscovery,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          "Enter Custom IP Address",
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
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
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
              color: Colors.black87,
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
    List<FlSpot> filteredData =
        title.contains("Oxygen")
            ? data.where((spot) => spot.y >= 95).toList()
            : data;
    double defaultMin = 0;
    double defaultMax = title.contains("Oxygen") ? 100 : 120;
    double centerValue = title.contains("Oxygen") ? 98 : 75;
    double rangeSize = title.contains("Oxygen") ? 10 : 40;
    double maxY = defaultMax;
    double minY = defaultMin;
    if (filteredData.isNotEmpty) {
      maxY = filteredData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
      minY = filteredData.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);
      if (maxY - minY < 10) {
        centerValue = (maxY + minY) / 2;
        minY = centerValue - rangeSize / 2;
        maxY = centerValue + rangeSize / 2;
      }
    } else {
      minY = centerValue - rangeSize / 2;
      maxY = centerValue + rangeSize / 2;
    }
    double padding = (maxY - minY) * 0.2;
    if (padding < 5) padding = 5;
    double minYAxis = max(0, minY - padding);
    double maxYAxis = maxY + padding;
    double range = maxYAxis - minYAxis;
    if (range < 20) {
      maxYAxis = minYAxis + 20;
    }
    double horizontalInterval = 10;
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
                          : [FlSpot(0, centerValue)],
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
                    showTitles: false,
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: horizontalInterval,
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