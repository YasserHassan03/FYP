class FuzzyStress {
  double hrLowTrapezoid(double hr) {
    if (hr <= 45) return 1;
    if (hr > 45 && hr < 55) return (55 - hr) / (55 - 45);
    return 0;
  }

  double hrNormalTrapezoid(double hr) {
    if (hr <= 50) return 0;
    if (hr > 50 && hr < 60) return (hr - 50) / (60 - 50);
    if (hr >= 60 && hr <= 85) return 1;
    if (hr > 85 && hr < 95) return (95 - hr) / (95 - 85);
    if (hr >= 95) return 0;
    return 0;
  }

  double hrHighTrapezoid(double hr) {
    if (hr <= 90) return 0;
    if (hr > 90 && hr < 95) return (hr - 90) / (95 - 90);
    return 1;
  }

  double coffeeMembership(bool hadCoffee) => hadCoffee ? 1.0 : 0.0;

  double lowSleep(double sleepScore) {
    if (sleepScore <= 2) return 1;
    if (sleepScore > 2 && sleepScore < 3) return (3 - sleepScore) / (3 - 2);
    return 0;
  }

  double sleepAverage(double sleepScore) {
    if (sleepScore <= 2 || sleepScore >= 4) return 0;
    if (sleepScore > 2 && sleepScore < 3) return (sleepScore - 2) / (3 - 2);
    if (sleepScore == 3) return 1;
    if (sleepScore > 3 && sleepScore < 4) return (4 - sleepScore) / (4 - 3);
    return 0;
  }

  double highSleep(double sleepScore) {
    if (sleepScore <= 3) return 0;
    if (sleepScore > 3 && sleepScore < 4) return (sleepScore - 3) / (4 - 3);
    return 1;
  }

  double spo2Low(double spo2) {
    if (spo2 < 94) return 1;
    if (spo2 >= 94 && spo2 < 95) return (95 - spo2) / (95 - 94);
    return 0;
  }

  double spo2Normal(double spo2) {
    if (spo2 < 94) return 0;
    if (spo2 >= 94 && spo2 < 95) return (spo2 - 94) / (95 - 94);
    return 1;
  }

  double hrvLowTrapezoid(double hr) {
    if (hr <= 25) return 1;
    if (hr > 25 && hr < 45) return (45 - hr) / (45 - 25);
    return 0;
  }

  double hrvNormalTrapezoid(double hr) {
    if (hr <= 40) return 0;
    if (hr > 40 && hr < 55) return (hr - 40) / (55 - 40);
    if (hr >= 55 && hr <= 150) return 1;
    if (hr > 150 && hr < 165) return (165 - hr) / (165 - 150);
    if (hr >= 165) return 0;
    return 0;
  }

  double hrvHighTrapezoid(double hr) {
    if (hr <= 160) return 0;
    if (hr > 160 && hr < 200) return (hr - 160) / (200 - 160);
    return 1;
  }

  double sbpLowTrapezoid(double hr) {
    if (hr <= 115) return 1;
    if (hr > 115 && hr < 120) return (120 - hr) / (120 - 115);
    return 0;
  }

  double sbpNormalTrapezoid(double hr) {
    if (hr <= 120) return 0;
    if (hr > 120 && hr < 125) return (hr - 120) / (125 - 120);
    if (hr >= 125 && hr <= 135) return 1;
    if (hr > 135 && hr < 140) return (140 - hr) / (140 - 135);
    if (hr >= 140) return 0;
    return 0;
  }

  double sbpHighTrapezoid(double hr) {
    if (hr <= 140) return 0;
    if (hr > 140 && hr < 145) return (hr - 140) / (145 - 140);
    return 1;
  }

  double dbpLowTrapezoid(double hr) {
    if (hr <= 75) return 1;
    if (hr > 75 && hr < 80) return (80 - hr) / (80 - 75);
    return 0;
  }

  double dbpNormalTrapezoid(double hr) {
    if (hr <= 80) return 0;
    if (hr > 80 && hr < 85) return (hr - 80) / (85 - 80);
    if (hr >= 85 && hr <= 90) return 1;
    if (hr > 90 && hr < 95) return (95 - hr) / (95 - 90);
    if (hr >= 95) return 0;
    return 0;
  }

  double dbpHighTrapezoid(double hr) {
    if (hr <= 90) return 0;
    if (hr > 90 && hr < 95) return (hr - 90) / (95 - 90);
    return 1;
  }

  double _min(double a, double b) => a < b ? a : b;
  double _min3(double a, double b, double c) => _min(_min(a, b), c);
  double _max(double a, double b) => a > b ? a : b;
  double _max3(double a, double b, double c) => _max(_max(a, b), c);


  double computeStress({
    required double hr,
    required double sleepScore,
    required bool hadCoffee,
    required double spo2,
    required double hrv,
    required double sbp,
    required double dbp,
    
  }) {
    // fuxifying inputs
    final hrHigh = hrHighTrapezoid(hr);
    final hrNormal = hrNormalTrapezoid(hr);
    final hrLow = hrLowTrapezoid(hr);

    final sleepPoor = lowSleep(sleepScore);
    final sleepMid = sleepAverage(sleepScore);
    final sleepHigh = highSleep(sleepScore);

    final coffee = coffeeMembership(hadCoffee);

    final spo2LowVal = spo2Low(spo2);

    final hrvLow = hrvLowTrapezoid(hrv);
    final hrvNormal = hrvNormalTrapezoid(hrv);
    final hrvHigh = hrvHighTrapezoid(hrv);

    final sbpLow = sbpLowTrapezoid(sbp);
    final sbpNormal = sbpNormalTrapezoid(sbp);
    final sbpHigh = sbpHighTrapezoid(sbp);

    final dbpLow = dbpLowTrapezoid(dbp);
    final dbpNormal = dbpNormalTrapezoid(dbp);
    final dbpHigh = dbpHighTrapezoid(dbp);

    //Fuzzy rules

    final rule1 = spo2LowVal;
    final rule2 = hrvLow;
    final rule3 = _min3(sleepPoor, hrHigh, coffee);
    final rule4 = _min3(sleepPoor, hrHigh, 1-coffee);
    final rule5 = _min3(hrvNormal,hrHigh,1-coffee);
    final rule6 = _min3(sbpHigh,dbpHigh,1.0);
    final rule7 = _min3(hrHigh, hrvLow, coffee);

    final rule8 = _min3(hrHigh,sleepHigh,coffee);
    final rule9 = _min3(hrNormal, sleepHigh, 1-coffee);
    final rule10 = _min(hrLow, sleepHigh);
    final rule11 = _min(hrvHigh,sleepHigh);
    final rule12 = _min(hrLow,hrvHigh);
    final rule13 = _min3(sbpNormal,dbpNormal,hrNormal);
    final rule14 = _min3(sbpLow,dbpLow,1.0);

    final rule15 = _min3(hrHigh, coffee, sleepMid);

    final stressHigh = _max3(_max3(rule1, rule2, rule3), _max3(rule4, rule5, rule6), rule7);
    final stressLow = _max3(_max3(rule8, rule9, rule10), _max3(rule11, rule12, rule13), rule14);
    final stressMedium = rule15;

    // defuzzification

    final numerator = (stressLow * 2) + (stressMedium * 5) + (stressHigh * 8);
    final denominator = (stressLow + stressMedium + stressHigh);
    final stressScore = denominator == 0 ? 5.0 : numerator.toDouble() / denominator.toDouble();


    return stressScore;
  }
}
