import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class SupabaseApi {
  SupabaseApi({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  Uri _endpoint(String path) {
    final cleanURL = url.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$cleanURL/rest/v1/$path');
  }

  Map<String, String> get _headers => {
    'apikey': anonKey,
    'Authorization': 'Bearer $anonKey',
    'Content-Type': 'application/json',
  };

  Future<List<EventSummary>> fetchEvents() async {
    final response = await http.get(
      _endpoint(
        'events?select=id,slug,name,source_name,is_active&order=is_active.desc,created_at.desc',
      ),
      headers: _headers,
    );
    _throwIfFailed(response);
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows
        .map((row) => EventSummary.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<RemoteBundle> fetchBundle(EventSummary event) async {
    final eventID = Uri.encodeQueryComponent(event.id);
    final responses = await Future.wait([
      http.get(
        _endpoint(
          'routines?select=*&event_id=eq.$eventID&order=sort_order.asc',
        ),
        headers: _headers,
      ),
      http.get(
        _endpoint('judges?select=*&event_id=eq.$eventID&order=sort_order.asc'),
        headers: _headers,
      ),
      http.get(
        _endpoint(
          'criteria_templates?select=*&event_id=eq.$eventID&order=sort_order.asc',
        ),
        headers: _headers,
      ),
      http.get(
        _endpoint(
          'criteria?select=*&event_id=eq.$eventID&order=sort_order.asc',
        ),
        headers: _headers,
      ),
      http.get(
        _endpoint('scores?select=*&event_id=eq.$eventID'),
        headers: _headers,
      ),
      http.get(
        _endpoint('feedback?select=*&event_id=eq.$eventID'),
        headers: _headers,
      ),
      http.get(
        _endpoint('penalties?select=*&event_id=eq.$eventID'),
        headers: _headers,
      ),
    ]);
    for (final response in responses) {
      _throwIfFailed(response);
    }

    final routineRows = jsonDecode(responses[0].body) as List<dynamic>;
    final judgeRows = jsonDecode(responses[1].body) as List<dynamic>;
    final templateRows = jsonDecode(responses[2].body) as List<dynamic>;
    final criterionRows = jsonDecode(responses[3].body) as List<dynamic>;
    final scoreRows = jsonDecode(responses[4].body) as List<dynamic>;
    final feedbackRows = jsonDecode(responses[5].body) as List<dynamic>;
    final penaltyRows = jsonDecode(responses[6].body) as List<dynamic>;

    final routines = routineRows
        .map((row) => Routine.fromJson(row as Map<String, dynamic>))
        .toList();
    final judges = judgeRows
        .map((row) => (row as Map<String, dynamic>)['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    final criteriaByTemplate = <String, List<Criterion>>{};
    for (final item in criterionRows.cast<Map<String, dynamic>>()) {
      final templateID = item['template_id'] as String? ?? '';
      criteriaByTemplate
          .putIfAbsent(templateID, () => [])
          .add(Criterion.fromJson(item));
    }

    final templates = templateRows.cast<Map<String, dynamic>>().map((row) {
      final templateID = row['template_id'] as String? ?? '';
      return JudgingTemplate(
        templateId: templateID,
        genre: row['genre'] as String? ?? '',
        title: row['title'] as String? ?? '',
        maxScore: (row['max_score'] as num? ?? 0).toDouble(),
        criteria: criteriaByTemplate[templateID] ?? const [],
      );
    }).toList();

    final blocks = <String, List<Routine>>{};
    final blockTitles = <String, String>{};
    for (final row in routineRows.cast<Map<String, dynamic>>()) {
      final routine = Routine.fromJson(row);
      blocks.putIfAbsent(routine.block, () => []).add(routine);
      blockTitles[routine.block] = row['block_title'] as String? ?? '';
    }

    final appData = AppData(
      sourceName: event.sourceName.isEmpty ? event.name : event.sourceName,
      routines: routines,
      judges: judges,
      templates: templates,
      blocks: blocks.entries
          .map(
            (entry) => DanceBlock(
              name: entry.key,
              title: blockTitles[entry.key] ?? '',
              routines: entry.value,
            ),
          )
          .toList(),
    );

    return RemoteBundle(
      event: event,
      appData: appData,
      scores: scoreRows
          .map((row) => RemoteScore.fromJson(row as Map<String, dynamic>))
          .toList(),
      feedback: feedbackRows
          .map((row) => RemoteFeedback.fromJson(row as Map<String, dynamic>))
          .toList(),
      penalties: penaltyRows
          .map((row) => RemotePenalty.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> upsertScores(
    String eventID,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final response = await http.post(
      _endpoint('scores?on_conflict=event_id,routine_id,judge_id,criterion_id'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );
    _throwIfFailed(response);
  }

  Future<void> upsertFeedback(
    String eventID,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final response = await http.post(
      _endpoint('feedback?on_conflict=event_id,routine_id,judge_id'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );
    _throwIfFailed(response);
  }

  Future<void> upsertPenalties(
    String eventID,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final response = await http.post(
      _endpoint('penalties?on_conflict=event_id,routine_id,judge_id'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );
    _throwIfFailed(response);
  }

  void _throwIfFailed(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseApiException(response.statusCode, response.body);
    }
  }
}

class RemoteBundle {
  RemoteBundle({
    required this.event,
    required this.appData,
    required this.scores,
    required this.feedback,
    required this.penalties,
  });

  final EventSummary event;
  final AppData appData;
  final List<RemoteScore> scores;
  final List<RemoteFeedback> feedback;
  final List<RemotePenalty> penalties;
}

class SupabaseApiException implements Exception {
  SupabaseApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'Supabase $statusCode: $body';
}
