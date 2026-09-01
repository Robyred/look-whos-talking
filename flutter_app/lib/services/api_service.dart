import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/insights.dart';
import '../models/job_result.dart';

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  // Upload audio file, returns job_id.
  // [speakerCount] constrains the clustering to exactly that many speakers.
  // Pass null when the count is unknown.
  Future<String> submitJob(File audioFile, {int? speakerCount}) async {
    final uri = Uri.parse('$kApiBaseUrl/api/diarize');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));
    if (speakerCount != null) {
      request.fields['min_speakers'] = speakerCount.toString();
      request.fields['max_speakers'] = speakerCount.toString();
    }

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 202) {
      throw ApiException('Upload failed (${streamed.statusCode}): $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['job_id'] as String;
  }

  // Call the insights endpoint for a completed job.
  // [nameMap] is the speaker-name mapping the user approved — sent so the LLM
  // sees labelled dialogue rather than raw SPEAKER_00 IDs.
  Future<InsightsResult> fetchInsights(
    String jobId,
    Map<String, String> nameMap,
  ) async {
    final uri = Uri.parse('$kApiBaseUrl/api/jobs/$jobId/insights');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'speaker_names': nameMap}),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      throw ApiException(
          'Insights failed (${response.statusCode}): ${response.body}');
    }

    return InsightsResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // Send a chat message about a completed job. [messages] is the full history
  // so far — each entry is {'role': 'user'|'assistant', 'content': '...'}.
  Future<String> askQuestion(
    String jobId,
    List<Map<String, String>> messages,
    Map<String, String> nameMap,
  ) async {
    final uri = Uri.parse('$kApiBaseUrl/api/jobs/$jobId/ask');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'messages': messages, 'speaker_names': nameMap}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw ApiException(
          'Chat failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['answer'] as String;
  }

  // Poll a job until it completes or fails.
  Future<JobStatusResponse> pollJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/jobs/$jobId');
    final response =
        await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ApiException(
          'Poll failed (${response.statusCode}): ${response.body}');
    }

    return JobStatusResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }
}
