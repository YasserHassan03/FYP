import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';

class LiveSensorData extends StatefulWidget {
  const LiveSensorData({Key? key}) : super(key: key);

  @override
  State<LiveSensorData> createState() => _LiveSensorDataState();
}

class _LiveSensorDataState extends State<LiveSensorData> {
  String espIp = "192.168.0.252"; // Replace with your ESP32 IP
  bool isRecording = false;
  String sessionId = "";
  Timer? pollingTimer;

  List<FlSpot> heartRateData = [];
  List<FlSpot> oxygenData = [];

  double averageHeartRate = 0;
  double averageOxygen = 0;
  int timeCounter = 0;

  DatabaseReference? databaseRef;

  Future<void> sendCommand(String command) async {
    try {
      final socket = await Socket.connect(espIp, 80, timeout: const Duration(seconds: 2));
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

  void toggleRecording() async {
    if (!isRecording) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in.')),
        );
        print("User not logged in");
        return;
      }

      final uid = user.uid;

      // Generate session ID using UTC time
      final now = DateTime.now().toUtc(); // Use UTC time
      sessionId = DateFormat('yyyyMMddHHmmss').format(now);

      print("Generated session ID: $sessionId");

      await sendCommand("START $uid");
      await Future.delayed(const Duration(seconds: 2));

      // Start polling the database
      startPolling(uid);
    } else {
      await sendCommand("STOP");

      // Stop polling the database
      pollingTimer?.cancel();
      pollingTimer = null;

      // Clear the graph data
      setState(() {
        heartRateData.clear();
        oxygenData.clear();
        timeCounter = 0;
        averageHeartRate = 0;
        averageOxygen = 0;
      });
    }

    setState(() {
      isRecording = !isRecording;
    });
  }

  void startPolling(String uid) {
    pollingTimer?.cancel(); // Cancel any existing timer
    pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        // Fetch the latest session data
        final sessionRef = FirebaseDatabase.instance.ref().child("users/$uid/sessions/$sessionId/readings");
        final snapshot = await sessionRef.get();

        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          List<double> heartRates = [];
          List<double> oxygenValues = [];

          for (var entry in data.entries) {
            final reading = entry.value as Map<dynamic, dynamic>;
            double hr = (reading["heartRate"] ?? 0).toDouble();
            double ox = (reading["oxygen"] ?? 0).toDouble();

            if (ox > 0) oxygenValues.add(ox); // Ignore oxygen values of 0
            heartRates.add(hr);

            setState(() {
              heartRateData.add(FlSpot(timeCounter.toDouble(), hr));
              oxygenData.add(FlSpot(timeCounter.toDouble(), ox));
              timeCounter++;

              // Limit the number of points to prevent memory issues
              if (heartRateData.length > 100) {
                heartRateData.removeAt(0);
              }
              if (oxygenData.length > 100) {
                oxygenData.removeAt(0);
              }
            });
          }

          // Calculate averages
          setState(() {
            averageHeartRate = heartRates.isNotEmpty
                ? heartRates.reduce((a, b) => a + b) / heartRates.length
                : 0;
            averageOxygen = oxygenValues.isNotEmpty
                ? oxygenValues.reduce((a, b) => a + b) / oxygenValues.length
                : 0;
          });
        } else {
          print("No data found for session $sessionId.");
        }
      } catch (e) {
        print("Error polling database: $e");
      }
    });
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
          Text(
            "❤️ Average Heart Rate: ${averageHeartRate.toStringAsFixed(1)} bpm",
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
          Text(
            "🫁 Average Oxygen: ${averageOxygen.toStringAsFixed(1)} %",
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget buildLiveChart(List<FlSpot> data, String title, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minY: 0,
              lineBarsData: [
                LineChartBarData(
                  spots: data.isNotEmpty
                      ? data
                      : [FlSpot(0, 0)], // Provide a default point if the list is empty
                  isCurved: true,
                  barWidth: 2,
                  color: color,
                  dotData: FlDotData(show: false),
                )
              ],
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(value.toInt().toString(), style: const TextStyle(fontSize: 12, color: Colors.white));
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(value.toInt().toString(), style: const TextStyle(fontSize: 12, color: Colors.white));
                    },
                  ),
                ),
              ),
              gridData: FlGridData(show: true),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF74EBD5),
              Color(0xFFACB6E5),
            ],
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
                  ElevatedButton(
                    onPressed: toggleRecording,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecording ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    ),
                    child: Text(
                      isRecording ? "Stop Recording" : "Start Recording",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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