import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/job_result.dart';
import '../services/api_service.dart';
import '../utils/name_detector.dart';

enum ProcessingPhase { configuring, running, complete, failed }

class ProcessingViewModel extends ChangeNotifier {
  final File audioFile;
  final ApiService _api;

  ProcessingViewModel({required this.audioFile, ApiService? api})
      : _api = api ?? ApiService();

  static const _pollIntervalSec = 3;
  static const _maxPolls = 200;

  ProcessingPhase phase = ProcessingPhase.configuring;
  int? speakerCount;
  String statusMessage = 'Uploading audio…';
  String? error;

  JobStatusResponse? completedStatus;
  NameDetectionResult? detectionResult;

  void setSpeakerCount(int? count) {
    speakerCount = count;
    notifyListeners();
  }

  void start() {
    phase = ProcessingPhase.running;
    notifyListeners();
    _runPipeline();
  }

  Future<void> _runPipeline() async {
    String jobId;
    try {
      jobId = await _api.submitJob(audioFile, speakerCount: speakerCount);
    } catch (e) {
      _fail('Upload failed: $e');
      return;
    }

    _setMessage('Processing audio — this can take a minute…');

    for (var i = 0; i < _maxPolls; i++) {
      await Future.delayed(const Duration(seconds: _pollIntervalSec));

      JobStatusResponse status;
      try {
        status = await _api.pollJob(jobId);
      } catch (e) {
        _fail('Connection error: $e');
        return;
      }

      switch (status.status) {
        case JobStatus.pending:
          _setMessage('Queued — waiting to start…');
        case JobStatus.processing:
          _setMessage('Diarizing speakers…');
        case JobStatus.complete:
          if (status.result == null) {
            _fail('Job complete but no result received');
            return;
          }
          detectionResult = detectNames(status.result!.transcript);
          completedStatus = status;
          phase = ProcessingPhase.complete;
          notifyListeners();
          return;
        case JobStatus.failed:
          _fail(status.error ?? 'Processing failed');
          return;
      }
    }

    _fail('Timed out — try a shorter recording');
  }

  void _setMessage(String msg) {
    statusMessage = msg;
    notifyListeners();
  }

  void _fail(String err) {
    error = err;
    phase = ProcessingPhase.failed;
    notifyListeners();
  }
}
