import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'supabase_api.dart';

enum SyncState { localOnly, connecting, online, syncing, pending, offline }

class JudgingStore extends ChangeNotifier {
  JudgingStore(this.api);

  final SupabaseApi api;
  SharedPreferences? _prefs;

  List<EventSummary> events = [];
  EventSummary? selectedEvent;
  AppData? appData;
  String selectedJudge = '';
  String selectedRoutineId = '';
  SyncState syncState = SyncState.localOnly;
  String syncMessage = '';
  final Map<String, double> scores = {};
  final Map<String, String> feedback = {};
  final Set<String> pendingScoreKeys = {};
  final Set<String> pendingFeedbackKeys = {};

  int get pendingCount => pendingScoreKeys.length + pendingFeedbackKeys.length;
  List<Routine> get routines => appData?.routines ?? const [];
  List<DanceBlock> get blocks => appData?.blocks ?? const [];
  List<String> get judges => appData?.judges ?? const [];

  Routine? get selectedRoutine {
    if (routines.isEmpty) return null;
    return routines.firstWhere(
      (routine) => routine.id == selectedRoutineId,
      orElse: () => routines.first,
    );
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    selectedJudge = _prefs?.getString('selectedJudge') ?? '';
    selectedRoutineId = _prefs?.getString('selectedRoutineId') ?? '';
    scores.addAll(_decodeDoubleMap(_prefs?.getString('scores') ?? '{}'));
    feedback.addAll(_decodeStringMap(_prefs?.getString('feedback') ?? '{}'));
    pendingScoreKeys.addAll(_prefs?.getStringList('pendingScoreKeys') ?? const []);
    pendingFeedbackKeys.addAll(_prefs?.getStringList('pendingFeedbackKeys') ?? const []);

    if (!api.isConfigured) {
      syncState = SyncState.localOnly;
      syncMessage = 'Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY con --dart-define.';
      notifyListeners();
      return;
    }
    await refreshEvents();
  }

  Future<void> refreshEvents() async {
    syncState = SyncState.connecting;
    notifyListeners();
    try {
      events = await api.fetchEvents();
      selectedEvent = events.firstWhere(
        (event) => event.id == _prefs?.getString('selectedEventId'),
        orElse: () => events.firstWhere(
          (event) => event.isActive,
          orElse: () => events.isEmpty
              ? EventSummary(id: '', slug: '', name: '', sourceName: '', isActive: false)
              : events.first,
        ),
      );
      if (selectedEvent == null || selectedEvent!.id.isEmpty) {
        syncState = SyncState.offline;
        syncMessage = 'No hay eventos en Supabase.';
        notifyListeners();
        return;
      }
      await selectEvent(selectedEvent!);
    } catch (error) {
      syncState = pendingCount > 0 ? SyncState.pending : SyncState.offline;
      syncMessage = '$error';
      notifyListeners();
    }
  }

  Future<void> selectEvent(EventSummary event) async {
    selectedEvent = event;
    await _prefs?.setString('selectedEventId', event.id);
    syncState = SyncState.connecting;
    notifyListeners();
    try {
      final bundle = await api.fetchBundle(event);
      appData = bundle.appData;
      if (!judges.contains(selectedJudge)) {
        selectedJudge = judges.isEmpty ? '' : judges.first;
      }
      if (!routines.any((routine) => routine.id == selectedRoutineId)) {
        selectedRoutineId = routines.isEmpty ? '' : routines.first.id;
      }
      final judgeById = {for (final judge in judges) stableRemoteId(judge): judge};
      for (final remoteScore in bundle.scores) {
        final judge = judgeById[remoteScore.judgeId];
        if (judge == null) continue;
        final key = scoreKey(remoteScore.routineId, judge, remoteScore.criterionId);
        if (!pendingScoreKeys.contains(key)) {
          scores[key] = remoteScore.value;
        }
      }
      for (final remoteFeedback in bundle.feedback) {
        final judge = judgeById[remoteFeedback.judgeId];
        if (judge == null) continue;
        final key = feedbackKey(remoteFeedback.routineId, judge);
        if (!pendingFeedbackKeys.contains(key)) {
          feedback[key] = remoteFeedback.body;
        }
      }
      await _persistAll();
      await syncPending();
    } catch (error) {
      syncState = pendingCount > 0 ? SyncState.pending : SyncState.offline;
      syncMessage = '$error';
      notifyListeners();
    }
  }

  JudgingTemplate templateFor(Routine routine) {
    final templates = appData?.templates ?? const <JudgingTemplate>[];
    return templates.firstWhere(
      (template) => normalizedKey(template.genre) == normalizedKey(routine.genre),
      orElse: () => templates.isEmpty
          ? JudgingTemplate(templateId: 'general', genre: 'General', title: 'Hoja de jueceo', maxScore: 0, criteria: const [])
          : templates.first,
    );
  }

  String scoreKey(String routineId, String judge, int criterionId) {
    return '$routineId::${normalizedKey(judge)}::$criterionId';
  }

  String feedbackKey(String routineId, String judge) {
    return '$routineId::${normalizedKey(judge)}';
  }

  double scoreFor(Routine routine, String judge, Criterion criterion) {
    return scores[scoreKey(routine.id, judge, criterion.id)] ?? 0;
  }

  void selectJudge(String judge) {
    selectedJudge = judge;
    _prefs?.setString('selectedJudge', judge);
    notifyListeners();
  }

  void selectRoutine(String routineId) {
    selectedRoutineId = routineId;
    _prefs?.setString('selectedRoutineId', routineId);
    notifyListeners();
  }

  Future<void> submitScores(Routine routine, Map<int, double> values) async {
    for (final entry in values.entries) {
      final key = scoreKey(routine.id, selectedJudge, entry.key);
      scores[key] = entry.value.clamp(0, 10).toDouble();
      pendingScoreKeys.add(key);
    }
    await _persistAll();
    syncState = SyncState.pending;
    notifyListeners();
    await syncPending();
  }

  Future<void> setFeedback(Routine routine, String body) async {
    final key = feedbackKey(routine.id, selectedJudge);
    feedback[key] = body;
    pendingFeedbackKeys.add(key);
    await _persistAll();
    syncState = SyncState.pending;
    notifyListeners();
    await syncPending();
  }

  Future<void> syncPending() async {
    if (!api.isConfigured || selectedEvent == null) {
      syncState = api.isConfigured ? SyncState.pending : SyncState.localOnly;
      notifyListeners();
      return;
    }
    if (pendingCount == 0) {
      syncState = SyncState.online;
      syncMessage = 'Datos sincronizados.';
      notifyListeners();
      return;
    }
    syncState = SyncState.syncing;
    notifyListeners();
    try {
      final eventID = selectedEvent!.id;
      final scoreRows = pendingScoreKeys.map((key) {
        final parts = key.split('::');
        return {
          'event_id': eventID,
          'routine_id': parts[0],
          'judge_id': stableRemoteId(parts[1]),
          'criterion_id': int.parse(parts[2]),
          'value': scores[key] ?? 0,
          'device_id': 'android-tablet',
        };
      }).toList();
      await api.upsertScores(eventID, scoreRows);
      pendingScoreKeys.clear();

      final feedbackRows = pendingFeedbackKeys.map((key) {
        final parts = key.split('::');
        return {
          'event_id': eventID,
          'routine_id': parts[0],
          'judge_id': stableRemoteId(parts[1]),
          'body': feedback[key] ?? '',
          'device_id': 'android-tablet',
        };
      }).toList();
      await api.upsertFeedback(eventID, feedbackRows);
      pendingFeedbackKeys.clear();
      await _persistAll();
      syncState = SyncState.online;
      syncMessage = 'Datos sincronizados.';
    } catch (error) {
      syncState = SyncState.pending;
      syncMessage = '$error';
    }
    notifyListeners();
  }

  List<RoutineResult> get rankings {
    final results = routines.map(resultFor).toList();
    results.sort((left, right) {
      final totalCompare = right.total.compareTo(left.total);
      if (totalCompare != 0) return totalCompare;
      return (int.tryParse(left.routine.id) ?? 0).compareTo(int.tryParse(right.routine.id) ?? 0);
    });
    return results;
  }

  RoutineResult resultFor(Routine routine) {
    final template = templateFor(routine);
    final totals = <String, double>{};
    for (final judge in judges) {
      totals[judge] = template.criteria.fold<double>(
        0,
        (sum, criterion) => sum + scoreFor(routine, judge, criterion),
      );
    }
    final submitted = totals.values.where((value) => value > 0).toList();
    final total = submitted.isEmpty ? 0.0 : submitted.reduce((a, b) => a + b) / submitted.length;
    return RoutineResult(
      routine: routine,
      judgeTotals: totals,
      total: total,
      maxScore: template.criteria.length * 10,
    );
  }

  Future<void> _persistAll() async {
    await _prefs?.setString('scores', jsonEncode(scores));
    await _prefs?.setString('feedback', jsonEncode(feedback));
    await _prefs?.setStringList('pendingScoreKeys', pendingScoreKeys.toList()..sort());
    await _prefs?.setStringList('pendingFeedbackKeys', pendingFeedbackKeys.toList()..sort());
  }

  Map<String, double> _decodeDoubleMap(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, (value as num).toDouble()));
  }

  Map<String, String> _decodeStringMap(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }
}
