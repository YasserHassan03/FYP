import 'dart:async';
import 'dart:convert';
import 'package:CalmPetitor/fuzzy/fuzzy_stress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:CalmPetitor/pages/video_player_screen.dart';

class StressScoreDialog extends StatelessWidget {
  final double stressScore;

  const StressScoreDialog({Key? key, required this.stressScore})
    : super(key: key);

  String get stressLevel {
    if (stressScore < 3.5) return "Low";
    if (stressScore < 6.5) return "Medium";
    return "High";
  }

  Color get stressColor {
    if (stressScore < 3.5) return Colors.green;
    if (stressScore < 6.5) return Colors.orange;
    return Colors.red;
  }

  List<Map<String, String>> getRecommendations() {
    switch (stressLevel) {
      case "Low":
        return [
          {"title": "Motivation to Work", "videoId": "jrIS_RQJmCU"},
          {
            "title": "5-Minute Meditation for Stress Relief",
            "videoId": "inpok4MKVLM",
          },
          {"title": "10-Minute Stress Relief Yoga", "videoId": "sTANio_2E0Q"},
        ];
      case "Medium":
        return [
          {
            "title": "Guided Meditation for Anxiety & Stress",
            "videoId": "O-6f5wQXSu8",
          },
          {"title": "Box Breathing Technique", "videoId": "tEmt1Znux58"},
          {"title": "Progressive Muscle Relaxation", "videoId": "86HUcX8ZtAk"},
        ];
      case "High":
        return [
          {"title": "Sleep Meditation for Anxiety", "videoId": "acLUWBuAvms"},
          {
            "title": "Guided Meditation for Anxiety & Stress",
            "videoId": "O-6f5wQXSu8",
          },
          {"title": "4-7-8 Breathing Exercise", "videoId": "PmBYdfv5RSk"},
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final recommendations = getRecommendations();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.self_improvement, color: stressColor, size: 32),
          const SizedBox(width: 12),
          Text('Your Stress Score', style: TextStyle(color: stressColor)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stressScore.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: stressColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Stress Level: $stressLevel',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: stressColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _getAdvice(stressLevel),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          if (recommendations.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Recommended videos for you:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                ...recommendations.map(
                  (rec) => ListTile(
                    leading: const Icon(
                      Icons.play_circle_fill,
                      color: Colors.red,
                      size: 32,
                    ),
                    title: Text(
                      rec['title'] ?? "",
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Colors.blueAccent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop(); // Close dialog
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (context) =>
                                  VideoPlayerScreen(videoId: rec['videoId']!),
                        ),
                      );
                    },
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          child: const Text('OK', style: TextStyle(fontSize: 18)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  String _getAdvice(String level) {
    switch (level) {
      case "Low":
        return "Great job! Keep maintaining your healthy habits.";
      case "Medium":
        return "You're doing okay, but consider some relaxation or mindfulness.";
      case "High":
        return "High stress detected. Take a break, breathe, and look after yourself.";
      default:
        return "";
    }
  }
}

class LiveSensorData extends StatefulWidget {
  const LiveSensorData({Key? key}) : super(key: key);

  @override
  State<LiveSensorData> createState() => _LiveSensorDataState();
}

class _LiveSensorDataState extends State<LiveSensorData> {
  FlutterBlue flutterBlue = FlutterBlue.instance;
  BluetoothDevice? espDevice;
  BluetoothCharacteristic? commandChar; // RX (write)
  BluetoothCharacteristic? notifyChar; // TX (notify)
  StreamSubscription<List<int>>? notifySub;
  StreamSubscription<BluetoothDeviceState>? deviceStateSub;
  bool isBleConnected = false;
  bool isRecording = false;
  String sessionId = "";

  List<Map<String, dynamic>> readings = [];
  List<FlSpot> heartRateData = [];
  List<FlSpot> oxygenData = [];
  List<FlSpot> sbpData = [];
  List<FlSpot> dbpData = [];
  int chartTime = 0;
  int readingsCount = 0;

  double averageHeartRate = 0;
  double averageOxygen = 0;
  double averageSBP = 0;
  double averageDBP = 0;
  double sessionHRV = 0;

  final String serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String rxCharUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  final String txCharUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  DateTime? sessionStartTime;

  @override
  void dispose() {
    notifySub?.cancel();
    deviceStateSub?.cancel();
    espDevice?.disconnect();
    super.dispose();
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    espDevice = device;
    await espDevice!.connect(autoConnect: false);
    setState(() {
      isBleConnected = true;
    });

    // Listen for disconnects
    deviceStateSub?.cancel();
    deviceStateSub = espDevice!.state.listen((state) {
      if (state == BluetoothDeviceState.disconnected) {
        setState(() {
          isBleConnected = false;
          espDevice = null;
          commandChar = null;
          notifyChar = null;
        });
      }
    });

    List<BluetoothService> services = await espDevice!.discoverServices();
    for (var service in services) {
      if (service.uuid.toString().toLowerCase() == serviceUuid) {
        for (var c in service.characteristics) {
          if (c.uuid.toString().toLowerCase() == rxCharUuid) {
            commandChar = c;
          }
          if (c.uuid.toString().toLowerCase() == txCharUuid) {
            notifyChar = c;
          }
        }
      }
    }
    if (notifyChar != null) {
      await notifyChar!.setNotifyValue(true);
      notifySub = notifyChar!.value.listen(onBleData);
    }
  }

  void onBleData(List<int> value) {
    try {
      // Ignore first 3 seconds of data after session start
      if (sessionStartTime != null &&
          DateTime.now().difference(sessionStartTime!).inSeconds < 3) {
        return;
      }
      final jsonStr = utf8.decode(value);
      final data = json.decode(jsonStr);
      readingsCount++;
      if (readingsCount <= 0) return;
      setState(() {
        readings.add(data);
        double hr = (data['heartRate'] ?? 0).toDouble();
        double sbp = (data['sbp'] ?? 0).toDouble();
        double dbp = (data['dbp'] ?? 0).toDouble();
        double spo2 = (data['oxygen'] ?? 0).toDouble();

        heartRateData.add(FlSpot(chartTime.toDouble(), hr));
        sbpData.add(FlSpot(chartTime.toDouble(), sbp));
        dbpData.add(FlSpot(chartTime.toDouble(), dbp));
        // Only add valid SpO2 readings
        if (spo2 >= 50) {
          oxygenData.add(FlSpot(chartTime.toDouble(), spo2));
        }
        chartTime++;
        if (heartRateData.length > 100) heartRateData.removeAt(0);
        if (sbpData.length > 100) sbpData.removeAt(0);
        if (dbpData.length > 100) dbpData.removeAt(0);
        if (oxygenData.length > 100) oxygenData.removeAt(0);

        averageHeartRate =
            heartRateData.isNotEmpty
                ? heartRateData.map((e) => e.y).reduce((a, b) => a + b) /
                    heartRateData.length
                : 0;
        averageSBP =
            sbpData.isNotEmpty
                ? sbpData.map((e) => e.y).reduce((a, b) => a + b) /
                    sbpData.length
                : 0;
        averageDBP =
            dbpData.isNotEmpty
                ? dbpData.map((e) => e.y).reduce((a, b) => a + b) /
                    dbpData.length
                : 0;
        averageOxygen =
            oxygenData.isNotEmpty
                ? oxygenData.map((e) => e.y).reduce((a, b) => a + b) /
                    oxygenData.length
                : 0;
        if (data.containsKey('hrv')) {
          sessionHRV = (data['hrv'] ?? 0).toDouble();
        }
      });
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && sessionId.isNotEmpty) {
        final db = FirebaseDatabase.instance.ref();
        final readingsPath = "users/${user.uid}/sessions/$sessionId/readings";
        if (!data.containsKey('hrv')) {
          db.child(readingsPath).push().set(data);
        }
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  Future<void> sendBleCommand(String command) async {
    if (espDevice == null || commandChar == null || !isBleConnected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ESP32 not connected!')));
      return;
    }
    await commandChar!.write(
      utf8.encode(command),
      withoutResponse: commandChar!.properties.writeWithoutResponse,
    );
  }

  void toggleRecording() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('User not logged in.')));
      return;
    }
    if (!isRecording) {
      final uid = user.uid;
      final now = DateTime.now().toUtc();
      sessionId = DateFormat('yyyyMMddHHmmss').format(now);
      setState(() {
        isRecording = true;
        sessionHRV = 0;
        readings.clear();
        heartRateData.clear();
        sbpData.clear();
        dbpData.clear();
        oxygenData.clear();
        chartTime = 0;
        readingsCount = 0;
        sessionStartTime = DateTime.now();
      });
      await sendBleCommand("START");
    } else {
      setState(() {
        isRecording = false;
      });
      await sendBleCommand("STOP");
      _showPostSessionQuestionnaire();
      uploadSessionToFirebase();
    }
  }

  Future<void> uploadSessionToFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || sessionId.isEmpty) return;
    final sessionPath = "users/${user.uid}/sessions/$sessionId";
    final questionnairePath = "$sessionPath/questionnaire";
    final db = FirebaseDatabase.instance.ref();

    // Upload summary
    await db.child(questionnairePath).update({
      'averageHeartRate': averageHeartRate,
      'averageSBP': averageSBP,
      'averageDBP': averageDBP,
      'averageOxygen': averageOxygen,
      'hrv': sessionHRV,
      'timestamp': ServerValue.timestamp,
    });
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
                    Slider(
                      value: daysPreComp.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label:
                          '$daysPreComp ${daysPreComp == 1 ? 'day' : 'days'}',
                      onChanged: (double value) {
                        setState(() {
                          daysPreComp = value.round();
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                ElevatedButton(
                  child: const Text('Submit'),
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null || sessionId.isEmpty) return;
                    final fuzzy = FuzzyStress();
                    final stressScore = fuzzy.computeStress(
                      hr: averageHeartRate,
                      sleepScore: sleepQuality.toDouble(),
                      hadCoffee: hadCoffee,
                      spo2: averageOxygen,
                      hrv: sessionHRV,
                      sbp: averageSBP,
                      dbp: averageDBP,
                    );
                    final questionnaireData = {
                      'stressLevel': stressLevel,
                      'hadCoffee': hadCoffee,
                      'coffeeTime':
                          hadCoffee ? coffeeTime.format(context) : null,
                      'sleepQuality': sleepQuality,
                      'daysPreCompetition': daysPreComp,
                      'averageHeartRate': averageHeartRate,
                      'averageSBP': averageSBP,
                      'averageDBP': averageDBP,
                      'averageOxygen': averageOxygen,
                      'hrv': sessionHRV,
                      'stressScore': stressScore,
                      'timestamp': ServerValue.timestamp,
                    };
                    final databaseRef = FirebaseDatabase.instance.ref().child(
                      "users/${user.uid}/sessions/$sessionId/questionnaire",
                    );
                    await databaseRef.set(questionnaireData);
                    await uploadSessionToFirebase();
                    Navigator.of(context).pop();
                    showDialog(
                      context: context,
                      builder:
                          (context) =>
                              StressScoreDialog(stressScore: stressScore),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget buildDeviceList() {
    return StreamBuilder<List<ScanResult>>(
      stream: flutterBlue.scanResults,
      initialData: const [],
      builder: (context, snapshot) {
        final results = snapshot.data ?? [];
        final espResults =
            results.where((r) => r.device.name == "ESP32-PPG").toList();
        if (espResults.isEmpty) {
          return const Text(
            "No ESP32-PPG found. Make sure your device is on and advertising.",
          );
        }
        return Column(
          children:
              espResults
                  .map(
                    (r) => ListTile(
                      title: Text(r.device.name),
                      subtitle: Text(r.device.id.toString()),
                      trailing: ElevatedButton(
                        child: const Text("Connect"),
                        onPressed: () async {
                          await connectToDevice(r.device);
                        },
                      ),
                    ),
                  )
                  .toList(),
        );
      },
    );
  }

  Widget buildConnectionBox() {
    return StreamBuilder<bool>(
      stream: flutterBlue.isScanning,
      initialData: false,
      builder: (context, snapshot) {
        final isScanning = snapshot.data ?? false;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          decoration: BoxDecoration(
            color:
                isBleConnected
                    ? Colors.green.withOpacity(0.2)
                    : isScanning
                    ? Colors.orange.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
            border: Border.all(
              color:
                  isBleConnected
                      ? Colors.green
                      : isScanning
                      ? Colors.orange
                      : Colors.red,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isBleConnected
                    ? Icons.bluetooth_connected
                    : isScanning
                    ? Icons.bluetooth_searching
                    : Icons.bluetooth_disabled,
                color:
                    isBleConnected
                        ? Colors.green
                        : isScanning
                        ? Colors.orange
                        : Colors.red,
              ),
              const SizedBox(width: 10),
              Text(
                isBleConnected
                    ? "ESP32 Connected"
                    : isScanning
                    ? "Scanning for ESP32-PPG..."
                    : "ESP32 Not Connected",
                style: TextStyle(
                  color:
                      isBleConnected
                          ? Colors.green
                          : isScanning
                          ? Colors.orange
                          : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!isBleConnected && !isScanning)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  color: Colors.blue,
                  tooltip: "Scan for ESP32",
                  onPressed:
                      () => flutterBlue.startScan(
                        timeout: const Duration(seconds: 4),
                      ),
                ),
              if (isScanning)
                IconButton(
                  icon: const Icon(Icons.stop),
                  color: Colors.red,
                  tooltip: "Stop Scan",
                  onPressed: () => flutterBlue.stopScan(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget buildScoreboard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
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
                "Avg HR: ${averageHeartRate.toStringAsFixed(1)} bpm",
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
          SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.bloodtype, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                "Avg SBP: ${averageSBP.toStringAsFixed(1)} mmHg",
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
          SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.bloodtype, color: Colors.deepOrange),
              SizedBox(width: 8),
              Text(
                "Avg DBP: ${averageDBP.toStringAsFixed(1)} mmHg",
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
          SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.air, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                "Avg SpO₂: ${averageOxygen.toStringAsFixed(1)} %",
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
          SizedBox(height: 5),
          if (!isRecording)
            Row(
              children: [
                Icon(Icons.timeline, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  "Session HRV: ${sessionHRV > 0 ? sessionHRV.toStringAsFixed(2) : '--'} ms",
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget buildLiveChart(List<FlSpot> data, String title, Color color) {
    double centerValue = data.isNotEmpty ? data.last.y : 0;
    double minY =
        data.isNotEmpty
            ? data.map((e) => e.y).reduce((a, b) => a < b ? a : b)
            : centerValue - 10;
    double maxY =
        data.isNotEmpty
            ? data.map((e) => e.y).reduce((a, b) => a > b ? a : b)
            : centerValue + 10;
    if (minY == maxY) {
      minY -= 5;
      maxY += 5;
    }
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
              minY: minY,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: data.isNotEmpty ? data : [FlSpot(0, centerValue)],
                  isCurved: true,
                  barWidth: 2,
                  color: color,
                  dotData: FlDotData(show: false),
                ),
              ],
              titlesData: FlTitlesData(
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
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: 10,
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  buildConnectionBox(),
                  if (!isBleConnected) buildDeviceList(),
                  if (isBleConnected) ...[
                    const SizedBox(height: 20),
                    buildScoreboard(),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: toggleRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isRecording ? Colors.red : Colors.green,
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
                    buildLiveChart(
                      heartRateData,
                      "Heart Rate (BPM)",
                      Colors.red,
                    ),
                    const SizedBox(height: 20),
                    buildLiveChart(
                      sbpData,
                      "Systolic BP (mmHg)",
                      Colors.orange,
                    ),
                    const SizedBox(height: 20),
                    buildLiveChart(
                      dbpData,
                      "Diastolic BP (mmHg)",
                      Colors.deepOrange,
                    ),
                    const SizedBox(height: 20),
                    buildLiveChart(oxygenData, "Blood Oxygen (%)", Colors.blue),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
