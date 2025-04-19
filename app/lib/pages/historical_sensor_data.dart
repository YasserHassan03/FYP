import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class HistoricalSensorData extends StatefulWidget {
  const HistoricalSensorData({Key? key}) : super(key: key);

  @override
  State<HistoricalSensorData> createState() => _HistoricalSensorDataState();
}

class _HistoricalSensorDataState extends State<HistoricalSensorData> {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  Map<String, dynamic> historicalData = {};
  bool isLoading = true;
  String? selectedSessionId;

  @override
  void initState() {
    super.initState();
    fetchHistoricalData();
  }

  Future<void> fetchHistoricalData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final snapshot =
          await _databaseRef.child('users/${user.uid}/sessions').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          historicalData = data.map(
            (key, value) => MapEntry(
              key.toString(),
              value != null ? Map<String, dynamic>.from(value as Map) : {},
            ),
          );
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching historical data: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  String formatSessionId(String sessionId) {
    try {
      // First try parsing the timestamp as is
      DateTime dateTime;
      if (sessionId.length == 14) {
        // Format: YYYYMMDDHHmmss
        String year = sessionId.substring(0, 4);
        String month = sessionId.substring(4, 6);
        String day = sessionId.substring(6, 8);
        String hour = sessionId.substring(8, 10);
        String minute = sessionId.substring(10, 12);
        String second = sessionId.substring(12, 14);

        dateTime = DateTime.parse('$year-$month-$day $hour:$minute:$second');
      } else {
        // Try standard parsing
        dateTime = DateTime.parse(sessionId);
      }
      return DateFormat('d MMMM yyyy, HH:mm:ss').format(dateTime);
    } catch (e) {
      // If parsing fails, try to make it more readable at least
      if (sessionId.length >= 8) {
        try {
          String year = sessionId.substring(0, 4);
          String month = sessionId.substring(4, 6);
          String day = sessionId.substring(6, 8);
          return '$day/$month/$year ${sessionId.substring(8)}';
        } catch (e) {
          return sessionId; // Return original if all parsing fails
        }
      }
      return sessionId;
    }
  }

  // Parse date time from session ID for sorting
  DateTime? parseSessionDateTime(String sessionId) {
    try {
      if (sessionId.length == 14) {
        // Format: YYYYMMDDHHmmss
        String year = sessionId.substring(0, 4);
        String month = sessionId.substring(4, 6);
        String day = sessionId.substring(6, 8);
        String hour = sessionId.substring(8, 10);
        String minute = sessionId.substring(10, 12);
        String second = sessionId.substring(12, 14);

        return DateTime.parse('$year-$month-$day $hour:$minute:$second');
      } else {
        // Try standard parsing
        return DateTime.parse(sessionId);
      }
    } catch (e) {
      return null; // Return null if parsing fails
    }
  }

  // Helper method to check if a session has valid data
  bool sessionHasData(String sessionId) {
    final sessionData = historicalData[sessionId] as Map<String, dynamic>?;
    if (sessionData == null) return false;
    
    final readings = sessionData['readings'] as Map<dynamic, dynamic>?;
    return readings != null && readings.isNotEmpty;
  }

  Widget buildScoreCard({
    required String title,
    required double value,
    required String unit,
    required Color color,
    String? interpretation,
  }) {
    return Card(
      elevation: 4,
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 14,
                    color: color,
                  ),
                ),
              ],
            ),
            if (interpretation != null) ...[
              const SizedBox(height: 4),
              Text(
                interpretation,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String getHeartRateInterpretation(double hr) {
    if (hr < 60) return 'Bradycardia (low)';
    if (hr > 100) return 'Tachycardia (high)';
    return 'Normal';
  }

  String getOxygenInterpretation(double ox) {
    if (ox < 90) return 'Low (seek medical help)';
    if (ox < 95) return 'Borderline low';
    return 'Normal';
  }

  Widget buildGraph(String title, List<FlSpot> data, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minY: 0,
              lineBarsData: [
                LineChartBarData(
                  spots: data.isNotEmpty ? data : [FlSpot(0, 0)],
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
  Widget build(BuildContext context) {
    // Filter sessions that have data
    List<String> sessionsWithData = historicalData.keys
        .where((sessionId) => sessionHasData(sessionId))
        .toList();
        
    // Sort sessions by date (newest first)
    sessionsWithData.sort((a, b) {
      DateTime? dateA = parseSessionDateTime(a);
      DateTime? dateB = parseSessionDateTime(b);
      
      // If parsing fails for either, maintain original order
      if (dateA == null || dateB == null) {
        return 0;
      }
      
      // Sort newest first (descending order)
      return dateB.compareTo(dateA);
    });

    // Reset selectedSessionId if it doesn't have data
    if (selectedSessionId != null && !sessionsWithData.contains(selectedSessionId)) {
      selectedSessionId = null;
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF74EBD5), Color(0xFFACB6E5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : historicalData.isEmpty || sessionsWithData.isEmpty
                ? const Center(
                    child: Text(
                      'No Historical Data Available',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40), // Increased height to shift content down more
                          const Text(
                            '📊 Historical Sensor Data',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),
                          DropdownButton<String>(
                            value: selectedSessionId,
                            hint: const Text(
                              'Select a Session',
                              style: TextStyle(color: Colors.white),
                            ),
                            dropdownColor: Colors.blueGrey,
                            items: sessionsWithData.map((sessionId) {
                              return DropdownMenuItem<String>(
                                value: sessionId,
                                child: Text(
                                  formatSessionId(
                                    sessionId,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedSessionId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          if (selectedSessionId != null)
                            Builder(
                              builder: (context) {
                                final sessionData = historicalData[selectedSessionId!]
                                    as Map<String, dynamic>;
                                final readings = sessionData['readings']
                                    as Map<dynamic, dynamic>?;

                                List<FlSpot> heartRateData = [];
                                List<FlSpot> oxygenData = [];
                                int timeCounter = 0;
                                
                                // For calculating averages
                                double totalHeartRate = 0;
                                double totalOxygen = 0;
                                int validReadings = 0;

                                if (readings != null) {
                                  readings.forEach((key, value) {
                                    if (value is Map<dynamic, dynamic>) {
                                      final reading = value;
                                      double hr =
                                          (reading['heartRate'] ?? 0).toDouble();
                                      double ox =
                                          (reading['oxygen'] ?? 0).toDouble();
                                          
                                      // Only count valid readings for average calculation
                                      if (hr > 0 && ox > 0) {
                                        totalHeartRate += hr;
                                        totalOxygen += ox;
                                        validReadings++;
                                      }

                                      heartRateData.add(
                                        FlSpot(timeCounter.toDouble(), hr),
                                      );
                                      oxygenData.add(
                                        FlSpot(timeCounter.toDouble(), ox),
                                      );
                                      timeCounter++;
                                    } else {
                                      print('Skipping invalid reading: $value');
                                    }
                                  });
                                }
                                
                                // Calculate averages
                                double avgHeartRate = validReadings > 0 ? totalHeartRate / validReadings : 0;
                                double avgOxygen = validReadings > 0 ? totalOxygen / validReadings : 0;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 20),
                                    Text(
                                      'Session: ${formatSessionId(selectedSessionId!)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    
                                    // Scoreboard with averages
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Text(
                                        'Session Summary',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: buildScoreCard(
                                            title: 'Average Heart Rate',
                                            value: avgHeartRate,
                                            unit: 'BPM',
                                            color: Colors.red,
                                            interpretation: getHeartRateInterpretation(avgHeartRate),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: buildScoreCard(
                                            title: 'Average Blood Oxygen',
                                            value: avgOxygen,
                                            unit: '%',
                                            color: Colors.blue,
                                            interpretation: getOxygenInterpretation(avgOxygen),
                                          ),
                                        ),
                                      ],
                                    ),
                                    
                                    const SizedBox(height: 20),
                                    buildGraph(
                                      'Heart Rate (BPM)',
                                      heartRateData,
                                      Colors.red,
                                    ),
                                    const SizedBox(height: 20),
                                    buildGraph(
                                      'Blood Oxygen (%)',
                                      oxygenData,
                                      Colors.blue,
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}