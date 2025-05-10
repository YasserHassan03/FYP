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
      DateTime dateTime;
      if (sessionId.length == 14) {
        String year = sessionId.substring(0, 4);
        String month = sessionId.substring(4, 6);
        String day = sessionId.substring(6, 8);
        String hour = sessionId.substring(8, 10);
        String minute = sessionId.substring(10, 12);
        String second = sessionId.substring(12, 14);

        dateTime = DateTime.parse('$year-$month-$day $hour:$minute:$second');
      } else {
        dateTime = DateTime.parse(sessionId);
      }
      return DateFormat('d MMMM yyyy, HH:mm:ss').format(dateTime);
    } catch (e) {
      if (sessionId.length >= 8) {
        try {
          String year = sessionId.substring(0, 4);
          String month = sessionId.substring(4, 6);
          String day = sessionId.substring(6, 8);
          return '$day/$month/$year ${sessionId.substring(8)}';
        } catch (e) {
          return sessionId;
        }
      }
      return sessionId;
    }
  }

  DateTime? parseSessionDateTime(String sessionId) {
    try {
      if (sessionId.length == 14) {
        String year = sessionId.substring(0, 4);
        String month = sessionId.substring(4, 6);
        String day = sessionId.substring(6, 8);
        String hour = sessionId.substring(8, 10);
        String minute = sessionId.substring(10, 12);
        String second = sessionId.substring(12, 14);

        return DateTime.parse('$year-$month-$day $hour:$minute:$second');
      } else {
        return DateTime.parse(sessionId);
      }
    } catch (e) {
      return null;
    }
  }

  bool sessionHasData(String sessionId) {
    final sessionData = historicalData[sessionId] as Map<String, dynamic>?;
    if (sessionData == null) return false;
    final readings = sessionData['readings'] as Map<dynamic, dynamic>?;
    return readings != null && readings.isNotEmpty;
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

  // --- Modern, visually appealing scoreboard ---
  Widget buildModernScoreboard({
    required double avgHeartRate,
    required double avgOxygen,
    required double avgSbp,
    required double avgDbp,
    required double sessionHRV,
  }) {
    final List<_ScoreMetric> metrics = [
      _ScoreMetric(
        icon: Icons.favorite,
        color: Colors.red,
        label: 'Heart Rate',
        value: avgHeartRate,
        unit: 'bpm',
        desc: getHeartRateInterpretation(avgHeartRate),
      ),
      _ScoreMetric(
        icon: Icons.bubble_chart,
        color: Colors.blue,
        label: 'SpO₂',
        value: avgOxygen,
        unit: '%',
        desc: getOxygenInterpretation(avgOxygen),
      ),
      _ScoreMetric(
        icon: Icons.trending_up,
        color: Colors.orange,
        label: 'SBP',
        value: avgSbp,
        unit: 'mmHg',
      ),
      _ScoreMetric(
        icon: Icons.trending_down,
        color: Colors.deepOrange,
        label: 'DBP',
        value: avgDbp,
        unit: 'mmHg',
      ),
      _ScoreMetric(
        icon: Icons.timeline,
        color: Colors.purple,
        label: 'HRV',
        value: sessionHRV,
        unit: 'ms',
      ),
    ];

    return Card(
      elevation: 10,
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      color: Colors.white.withOpacity(0.97),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double itemWidth = (constraints.maxWidth - 32) / 2;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: metrics.map((metric) {
                return Container(
                  width: itemWidth,
                  constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: metric.color.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(color: metric.color.withOpacity(0.18)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(metric.icon, color: metric.color, size: 26),
                      const SizedBox(height: 6),
                      Text(
                        metric.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: metric.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            metric.value.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: metric.color,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            metric.unit,
                            style: TextStyle(
                              fontSize: 13,
                              color: metric.color,
                            ),
                          ),
                        ],
                      ),
                      if (metric.desc != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            metric.desc!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  Widget buildGraph(String title, List<FlSpot> data, Color color) {
    final filteredData =
        title.contains('Oxygen')
            ? data.where((spot) => spot.y > 0).toList()
            : data;
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
                  spots:
                      filteredData.isNotEmpty ? filteredData : [FlSpot(0, 0)],
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

  Widget buildQuestionnaireCard(Map questionnaire) {
    return Card(
      elevation: 6,
      color: Colors.white.withOpacity(0.97),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.assignment_turned_in, color: Colors.blueGrey, size: 22),
                SizedBox(width: 8),
                Text(
                  'Questionnaire Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const Divider(height: 24, thickness: 1.2),
            if (questionnaire.containsKey('stressLevel')) ...[
              Row(
                children: [
                  const Icon(Icons.self_improvement, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Stress Level:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text('${questionnaire['stressLevel']} / 10'),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (questionnaire.containsKey('hadCoffee')) ...[
              Row(
                children: [
                  Icon(Icons.coffee, color: Colors.brown[400], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Had Coffee:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(questionnaire['hadCoffee'] ? 'Yes' : 'No'),
                ],
              ),
              if (questionnaire['hadCoffee'] == true &&
                  questionnaire.containsKey('coffeeTime')) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, color: Colors.brown[200], size: 18),
                      const SizedBox(width: 6),
                      Text('Time: ${questionnaire['coffeeTime']}'),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],
            if (questionnaire.containsKey('sleepQuality')) ...[
              Row(
                children: [
                  const Icon(Icons.bedtime, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Sleep Quality:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text('${questionnaire['sleepQuality']} / 5'),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (questionnaire.containsKey('daysPreCompetition')) ...[
              Row(
                children: [
                  const Icon(Icons.event, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Days Pre-Competition:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text('${questionnaire['daysPreCompetition']}'),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (questionnaire.containsKey('tookMedication')) ...[
              Row(
                children: [
                  Icon(Icons.medication, color: Colors.purple[400], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Took Medication:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(questionnaire['tookMedication'] ? 'Yes' : 'No'),
                ],
              ),
              if (questionnaire['tookMedication'] == true &&
                  questionnaire.containsKey('medications')) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.list, color: Colors.purple[200], size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('Medications: ${questionnaire['medications']}'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> sessionsWithData =
        historicalData.keys
            .where((sessionId) => sessionHasData(sessionId))
            .toList();
    sessionsWithData.sort((a, b) {
      DateTime? dateA = parseSessionDateTime(a);
      DateTime? dateB = parseSessionDateTime(b);
      if (dateA == null || dateB == null) return 0;
      return dateB.compareTo(dateA);
    });

    if (selectedSessionId != null &&
        !sessionsWithData.contains(selectedSessionId)) {
      selectedSessionId = null;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 32,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 32),
                            Column(
                              children: [
                                Text(
                                  '📊 Historical Sensor',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  'Data',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedSessionId,
                                  hint: const Text(
                                    'Select a Session',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  dropdownColor: Colors.blueGrey[800],
                                  borderRadius: BorderRadius.circular(16),
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    color: Colors.white,
                                  ),
                                  items: sessionsWithData.map((sessionId) {
                                    return DropdownMenuItem<String>(
                                      value: sessionId,
                                      child: Text(
                                        formatSessionId(sessionId),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
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
                              ),
                            ),
                            const SizedBox(height: 28),
                            if (selectedSessionId != null)
                              Builder(
                                builder: (context) {
                                  final sessionData =
                                      historicalData[selectedSessionId!]
                                          as Map<String, dynamic>;
                                  final readings =
                                      sessionData['readings']
                                          as Map<dynamic, dynamic>?;
                                  final questionnaire =
                                      sessionData['questionnaire']
                                          as Map<dynamic, dynamic>?;

                                  List<FlSpot> heartRateData = [];
                                  List<FlSpot> oxygenData = [];
                                  List<FlSpot> sbpData = [];
                                  List<FlSpot> dbpData = [];
                                  int timeCounter = 0;

                                  double totalHeartRate = 0,
                                      totalOxygen = 0,
                                      totalSbp = 0,
                                      totalDbp = 0;
                                  int validHeartRateReadings = 0,
                                      validOxygenReadings = 0,
                                      validSbpReadings = 0,
                                      validDbpReadings = 0;

                                  if (readings != null) {
                                    var sortedReadings =
                                        readings.entries.toList()
                                          ..sort(
                                            (a, b) => a.key
                                                .toString()
                                                .compareTo(
                                                    b.key.toString()),
                                          );

                                    for (var entry in sortedReadings) {
                                      if (entry.value is Map<dynamic, dynamic>) {
                                        final reading =
                                            entry.value as Map<dynamic, dynamic>;
                                        double hr =
                                            (reading['heartRate'] ?? 0)
                                                .toDouble();
                                        double ox =
                                            (reading['oxygen'] ?? 0)
                                                .toDouble();
                                        double sbp =
                                            (reading['sbp'] ?? 0).toDouble();
                                        double dbp =
                                            (reading['dbp'] ?? 0).toDouble();

                                        if (hr > 0) {
                                          heartRateData.add(
                                            FlSpot(timeCounter.toDouble(), hr),
                                          );
                                          totalHeartRate += hr;
                                          validHeartRateReadings++;
                                        } else {
                                          heartRateData.add(
                                            FlSpot(timeCounter.toDouble(), 0),
                                          );
                                        }
                                        if (ox > 0) {
                                          oxygenData.add(
                                            FlSpot(timeCounter.toDouble(), ox),
                                          );
                                          totalOxygen += ox;
                                          validOxygenReadings++;
                                        }
                                        if (sbp > 0) {
                                          sbpData.add(
                                            FlSpot(timeCounter.toDouble(), sbp),
                                          );
                                          totalSbp += sbp;
                                          validSbpReadings++;
                                        } else {
                                          sbpData.add(
                                            FlSpot(timeCounter.toDouble(), 0),
                                          );
                                        }
                                        if (dbp > 0) {
                                          dbpData.add(
                                            FlSpot(timeCounter.toDouble(), dbp),
                                          );
                                          totalDbp += dbp;
                                          validDbpReadings++;
                                        } else {
                                          dbpData.add(
                                            FlSpot(timeCounter.toDouble(), 0),
                                          );
                                        }
                                        timeCounter++;
                                      }
                                    }
                                  }

                                  double avgHeartRate =
                                      validHeartRateReadings > 0
                                          ? totalHeartRate /
                                              validHeartRateReadings
                                          : 0;
                                  double avgOxygen =
                                      validOxygenReadings > 0
                                          ? totalOxygen /
                                              validOxygenReadings
                                          : 0;
                                  double avgSbp =
                                      validSbpReadings > 0
                                          ? totalSbp / validSbpReadings
                                          : 0;
                                  double avgDbp =
                                      validDbpReadings > 0
                                          ? totalDbp / validDbpReadings
                                          : 0;
                                  double sessionHRV = 0;
                                  if (questionnaire != null &&
                                      questionnaire['hrv'] != null) {
                                    sessionHRV =
                                        (questionnaire['hrv'] as num)
                                            .toDouble();
                                  }

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      const SizedBox(height: 18),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          'Session Summary',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white.withOpacity(0.95),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      buildModernScoreboard(
                                        avgHeartRate: avgHeartRate,
                                        avgOxygen: avgOxygen,
                                        avgSbp: avgSbp,
                                        avgDbp: avgDbp,
                                        sessionHRV: sessionHRV,
                                      ),
                                      const SizedBox(height: 24),
                                      buildGraph(
                                        'Heart Rate (BPM)',
                                        heartRateData,
                                        Colors.red,
                                      ),
                                      const SizedBox(height: 24),
                                      buildGraph(
                                        'Blood Oxygen (%)',
                                        oxygenData,
                                        Colors.blue,
                                      ),
                                      const SizedBox(height: 24),
                                      buildGraph(
                                        'Systolic BP (mmHg)',
                                        sbpData,
                                        Colors.orange,
                                      ),
                                      const SizedBox(height: 24),
                                      buildGraph(
                                        'Diastolic BP (mmHg)',
                                        dbpData,
                                        Colors.deepOrange,
                                      ),
                                      if (questionnaire != null) ...[
                                        const SizedBox(height: 32),
                                        buildQuestionnaireCard(questionnaire),
                                      ],
                                    ],
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}

// Helper class for scoreboard metrics
class _ScoreMetric {
  final IconData icon;
  final Color color;
  final String label;
  final double value;
  final String unit;
  final String? desc;

  _ScoreMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
    this.desc,
  });
}