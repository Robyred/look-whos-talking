import 'package:flutter/foundation.dart';

import '../models/insights.dart';
import '../models/job_result.dart';
import '../services/api_service.dart';

enum InsightsPhase { idle, loading, loaded, failed }

class InsightsViewModel extends ChangeNotifier {
  final String jobId;
  final DiarizationResult result;
  final Map<String, String> nameMap;
  final ApiService _api;

  InsightsViewModel({
    required this.jobId,
    required this.result,
    required this.nameMap,
    ApiService? api,
  }) : _api = api ?? ApiService();

  InsightsPhase phase = InsightsPhase.idle;
  InsightsResult? insights;
  String? error;

  Future<void> generate() async {
    if (phase == InsightsPhase.loading || phase == InsightsPhase.loaded) return;
    phase = InsightsPhase.loading;
    notifyListeners();
    try {
      insights = await _api.fetchInsights(jobId, nameMap);
      phase = InsightsPhase.loaded;
    } catch (e) {
      error = e.toString();
      phase = InsightsPhase.failed;
    }
    notifyListeners();
  }
}
