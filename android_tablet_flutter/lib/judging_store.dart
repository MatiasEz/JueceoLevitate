import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'supabase_api.dart';

enum SyncState { localOnly, connecting, online, syncing, pending, offline }

const _legacyScoresKey = 'scores';
const _legacyFeedbackKey = 'feedback';
const _legacyPenaltiesKey = 'penalties';
const _scoresPendingKey = 'scores.pending.v2';
const _feedbackPendingKey = 'feedback.pending.v2';
const _penaltiesPendingKey = 'penalties.pending.v2';

void _loadLog(String message) {
  if (kDebugMode) {
    debugPrint('[LevitateLoad] $message');
  }
}

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
  final Map<String, double> penalties = {};
  final Set<String> pendingScoreKeys = {};
  final Set<String> pendingFeedbackKeys = {};
  final Set<String> pendingPenaltyKeys = {};

  int get pendingCount =>
      pendingScoreKeys.length +
      pendingFeedbackKeys.length +
      pendingPenaltyKeys.length;
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
    final watch = Stopwatch()..start();
    _prefs = await SharedPreferences.getInstance();
    selectedJudge = _prefs?.getString('selectedJudge') ?? '';
    selectedRoutineId = _prefs?.getString('selectedRoutineId') ?? '';
    pendingScoreKeys.addAll(
      _prefs?.getStringList('pendingScoreKeys') ?? const [],
    );
    pendingFeedbackKeys.addAll(
      _prefs?.getStringList('pendingFeedbackKeys') ?? const [],
    );
    pendingPenaltyKeys.addAll(
      _prefs?.getStringList('pendingPenaltyKeys') ?? const [],
    );
    if (api.isConfigured) {
      scores.addAll(
          _decodeDoubleMap(_prefs?.getString(_scoresPendingKey) ?? '{}'));
      feedback.addAll(
          _decodeStringMap(_prefs?.getString(_feedbackPendingKey) ?? '{}'));
      penalties.addAll(
          _decodeDoubleMap(_prefs?.getString(_penaltiesPendingKey) ?? '{}'));
      _recoverPendingValuesFromLegacyCacheIfNeeded();
      _retainPendingLocalCacheOnly();
      await _clearLegacyRemoteCache();
      await _persistAll();
    } else {
      scores.addAll(_decodeDoubleMap(_prefs?.getString(_scoresPendingKey) ??
          _prefs?.getString(_legacyScoresKey) ??
          '{}'));
      feedback.addAll(_decodeStringMap(_prefs?.getString(_feedbackPendingKey) ??
          _prefs?.getString(_legacyFeedbackKey) ??
          '{}'));
      penalties.addAll(_decodeDoubleMap(
          _prefs?.getString(_penaltiesPendingKey) ??
              _prefs?.getString(_legacyPenaltiesKey) ??
              '{}'));
    }
    _loadLog(
        'initialize localScores=${scores.length} localFeedback=${feedback.length} localPenalties=${penalties.length} pending=$pendingCount remoteConfigured=${api.isConfigured} elapsed=${watch.elapsedMilliseconds}ms');

    if (!api.isConfigured) {
      syncState = SyncState.localOnly;
      syncMessage =
          'Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY con --dart-define.';
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
              ? EventSummary(
                  id: '',
                  slug: '',
                  name: '',
                  sourceName: '',
                  isActive: false,
                )
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
    final watch = Stopwatch()..start();
    selectedEvent = event;
    await _prefs?.setString('selectedEventId', event.id);
    syncState = SyncState.connecting;
    notifyListeners();
    _loadLog('selectEvent started id=${event.id} name="${event.name}"');
    try {
      final bundle = await api.fetchBundle(event);
      _loadLog(
          'selectEvent fetched bundle scores=${bundle.scores.length} feedback=${bundle.feedback.length} penalties=${bundle.penalties.length} elapsed=${watch.elapsedMilliseconds}ms');
      appData = bundle.appData;
      if (!judges.contains(selectedJudge)) {
        selectedJudge = judges.isEmpty ? '' : judges.first;
      }
      if (!routines.any((routine) => routine.id == selectedRoutineId)) {
        selectedRoutineId = routines.isEmpty ? '' : routines.first.id;
      }
      final judgeById = {
        for (final judge in judges) stableRemoteId(judge): judge,
      };
      _pruneSyncedInMemoryCache();
      var appliedScores = 0;
      var skippedPendingScores = 0;
      for (final remoteScore in bundle.scores) {
        final judge = judgeById[remoteScore.judgeId];
        if (judge == null) continue;
        final key = scoreKey(
          remoteScore.routineId,
          judge,
          remoteScore.criterionId,
        );
        if (!pendingScoreKeys.contains(key)) {
          scores[key] = remoteScore.value;
          appliedScores += 1;
        } else {
          skippedPendingScores += 1;
        }
      }
      var appliedFeedback = 0;
      var skippedPendingFeedback = 0;
      for (final remoteFeedback in bundle.feedback) {
        final judge = judgeById[remoteFeedback.judgeId];
        if (judge == null) continue;
        final key = feedbackKey(remoteFeedback.routineId, judge);
        if (!pendingFeedbackKeys.contains(key)) {
          feedback[key] = remoteFeedback.body;
          appliedFeedback += 1;
        } else {
          skippedPendingFeedback += 1;
        }
      }
      var appliedPenalties = 0;
      var skippedPendingPenalties = 0;
      for (final remotePenalty in bundle.penalties) {
        final judge = judgeById[remotePenalty.judgeId];
        if (judge == null) continue;
        final key = penaltyKey(remotePenalty.routineId, judge);
        if (!pendingPenaltyKeys.contains(key)) {
          penalties[key] = remotePenalty.value.clamp(-100, 0).toDouble();
          appliedPenalties += 1;
        } else {
          skippedPendingPenalties += 1;
        }
      }
      await _persistAll();
      _loadLog(
          'selectEvent applied scores=$appliedScores skippedScores=$skippedPendingScores feedback=$appliedFeedback skippedFeedback=$skippedPendingFeedback penalties=$appliedPenalties skippedPenalties=$skippedPendingPenalties localScores=${scores.length} elapsed=${watch.elapsedMilliseconds}ms');
      await syncPending();
      _loadLog(
          'selectEvent finished pending=$pendingCount elapsed=${watch.elapsedMilliseconds}ms');
    } catch (error) {
      syncState = pendingCount > 0 ? SyncState.pending : SyncState.offline;
      syncMessage = '$error';
      _loadLog(
          'selectEvent failed elapsed=${watch.elapsedMilliseconds}ms error=$error');
      notifyListeners();
    }
  }

  JudgingTemplate templateFor(Routine routine) {
    final templates = appData?.templates ?? const <JudgingTemplate>[];
    return templates.firstWhere(
      (template) =>
          normalizedKey(template.genre) == normalizedKey(routine.genre),
      orElse: () => templates.isEmpty
          ? JudgingTemplate(
              templateId: 'general',
              genre: 'General',
              title: 'Hoja de jueceo',
              maxScore: 0,
              criteria: const [],
            )
          : templates.first,
    );
  }

  String scoreKey(String routineId, String judge, int criterionId) {
    return '$routineId::${normalizedKey(judge)}::$criterionId';
  }

  String feedbackKey(String routineId, String judge) {
    return '$routineId::${normalizedKey(judge)}';
  }

  String penaltyKey(String routineId, String judge) {
    return '$routineId::${normalizedKey(judge)}';
  }

  double scoreFor(Routine routine, String judge, Criterion criterion) {
    return scores[scoreKey(routine.id, judge, criterion.id)] ?? 0;
  }

  double penaltyFor(Routine routine, String judge) {
    return penalties[penaltyKey(routine.id, judge)] ?? 0;
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

  Future<void> deleteRoutine(Routine routine, String importSecret) async {
    final event = selectedEvent;
    final cleanSecret = importSecret.trim();
    if (!api.isConfigured || event == null || event.id.isEmpty) {
      throw StateError('Elegí un programa online antes de borrar.');
    }
    if (cleanSecret.isEmpty) {
      throw StateError('Ingresá la clave de importación.');
    }

    syncState = SyncState.syncing;
    syncMessage = 'Borrando #${routine.id} ${routine.name}...';
    notifyListeners();

    await api.deleteRoutine(
      eventID: event.id,
      routineID: routine.id,
      importSecret: cleanSecret,
    );
    await _purgeRoutineState(routine.id);
    await selectEvent(event);
    syncState = pendingCount > 0 ? SyncState.pending : SyncState.online;
    syncMessage = '#${routine.id} ${routine.name} borrada.';
    notifyListeners();
  }

  Future<void> submitScores(
    Routine routine,
    Map<int, double> values, {
    double? penalty,
  }) async {
    for (final entry in values.entries) {
      final key = scoreKey(routine.id, selectedJudge, entry.key);
      scores[key] = entry.value.clamp(0, 10).toDouble();
      pendingScoreKeys.add(key);
    }
    if (penalty != null) {
      final key = penaltyKey(routine.id, selectedJudge);
      penalties[key] = penalty.clamp(-100, 0).toDouble();
      pendingPenaltyKeys.add(key);
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

      final penaltyRows = pendingPenaltyKeys.map((key) {
        final parts = key.split('::');
        return {
          'event_id': eventID,
          'routine_id': parts[0],
          'judge_id': stableRemoteId(parts[1]),
          'value': penalties[key] ?? 0,
          'device_id': 'android-tablet',
        };
      }).toList();
      await api.upsertPenalties(eventID, penaltyRows);
      pendingPenaltyKeys.clear();
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
      return (int.tryParse(left.routine.id) ?? 0).compareTo(
        int.tryParse(right.routine.id) ?? 0,
      );
    });
    return results;
  }

  RoutineResult resultFor(Routine routine) {
    final template = templateFor(routine);
    final totals = <String, double>{};
    final penaltyValues = <String, double>{};
    var penaltyTotal = 0.0;
    var submittedCount = 0;
    var finalSum = 0.0;
    for (final judge in judges) {
      final subtotal = template.criteria.fold<double>(
        0,
        (sum, criterion) => sum + scoreFor(routine, judge, criterion),
      );
      final penalty = penaltyFor(routine, judge);
      final finalTotal = subtotal > 0
          ? (subtotal + penalty).clamp(0, double.infinity).toDouble()
          : 0.0;
      totals[judge] = finalTotal;
      penaltyValues[judge] = penalty;
      if (subtotal > 0) {
        submittedCount += 1;
        finalSum += finalTotal;
        penaltyTotal += penalty;
      }
    }
    final total = submittedCount == 0 ? 0.0 : finalSum / submittedCount;
    return RoutineResult(
      routine: routine,
      judgeTotals: totals,
      judgePenalties: penaltyValues,
      total: total,
      penalty: penaltyTotal,
      maxScore: template.criteria.length * 10,
    );
  }

  Future<void> _persistAll() async {
    await _setEncodedMap(_scoresPendingKey, _scoresForStorage());
    await _setEncodedMap(_feedbackPendingKey, _feedbackForStorage());
    await _setEncodedMap(_penaltiesPendingKey, _penaltiesForStorage());
    await _prefs?.setStringList(
      'pendingScoreKeys',
      pendingScoreKeys.toList()..sort(),
    );
    await _prefs?.setStringList(
      'pendingFeedbackKeys',
      pendingFeedbackKeys.toList()..sort(),
    );
    await _prefs?.setStringList(
      'pendingPenaltyKeys',
      pendingPenaltyKeys.toList()..sort(),
    );
  }

  Future<void> _setEncodedMap(String key, Map<String, Object?> value) async {
    if (value.isEmpty) {
      await _prefs?.remove(key);
      return;
    }
    await _prefs?.setString(key, jsonEncode(value));
  }

  Map<String, double> _scoresForStorage() {
    if (!api.isConfigured) return scores;
    return {
      for (final key in pendingScoreKeys)
        if (scores.containsKey(key)) key: scores[key]!,
    };
  }

  Map<String, String> _feedbackForStorage() {
    if (!api.isConfigured) return feedback;
    return {
      for (final key in pendingFeedbackKeys)
        if (feedback.containsKey(key)) key: feedback[key]!,
    };
  }

  Map<String, double> _penaltiesForStorage() {
    if (!api.isConfigured) return penalties;
    return {
      for (final key in pendingPenaltyKeys)
        if (penalties.containsKey(key)) key: penalties[key]!,
    };
  }

  void _pruneSyncedInMemoryCache() {
    scores.removeWhere((key, _) => !pendingScoreKeys.contains(key));
    feedback.removeWhere((key, _) => !pendingFeedbackKeys.contains(key));
    penalties.removeWhere((key, _) => !pendingPenaltyKeys.contains(key));
  }

  void _retainPendingLocalCacheOnly() {
    _pruneSyncedInMemoryCache();
  }

  void _recoverPendingValuesFromLegacyCacheIfNeeded() {
    if (pendingScoreKeys.isNotEmpty && scores.isEmpty) {
      _loadLog('recovering pending scores from legacy SharedPreferences');
      scores.addAll(
          _decodeDoubleMap(_prefs?.getString(_legacyScoresKey) ?? '{}'));
    }
    if (pendingFeedbackKeys.isNotEmpty && feedback.isEmpty) {
      _loadLog('recovering pending feedback from legacy SharedPreferences');
      feedback.addAll(
          _decodeStringMap(_prefs?.getString(_legacyFeedbackKey) ?? '{}'));
    }
    if (pendingPenaltyKeys.isNotEmpty && penalties.isEmpty) {
      _loadLog('recovering pending penalties from legacy SharedPreferences');
      penalties.addAll(
          _decodeDoubleMap(_prefs?.getString(_legacyPenaltiesKey) ?? '{}'));
    }
  }

  Future<void> _clearLegacyRemoteCache() async {
    await _prefs?.remove(_legacyScoresKey);
    await _prefs?.remove(_legacyFeedbackKey);
    await _prefs?.remove(_legacyPenaltiesKey);
  }

  Future<void> _purgeRoutineState(String routineId) async {
    appData?.routines.removeWhere((routine) => routine.id == routineId);
    for (final block in appData?.blocks ?? const <DanceBlock>[]) {
      block.routines.removeWhere((routine) => routine.id == routineId);
    }
    if (selectedRoutineId == routineId) {
      selectedRoutineId = routines.isEmpty ? '' : routines.first.id;
      await _prefs?.setString('selectedRoutineId', selectedRoutineId);
    }

    scores.removeWhere((key, _) => key.split('::').first == routineId);
    feedback.removeWhere((key, _) => key.split('::').first == routineId);
    penalties.removeWhere((key, _) => key.split('::').first == routineId);
    pendingScoreKeys.removeWhere((key) => key.split('::').first == routineId);
    pendingFeedbackKeys
        .removeWhere((key) => key.split('::').first == routineId);
    pendingPenaltyKeys.removeWhere((key) => key.split('::').first == routineId);
    await _persistAll();
  }

  Map<String, double> _decodeDoubleMap(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );
  }

  Map<String, String> _decodeStringMap(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }
}
