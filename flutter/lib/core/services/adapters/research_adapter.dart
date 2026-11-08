import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// ResearchProvider — client adapter for the OpenAll Deep Research
/// Microservice (port of `src/adapters/research.ts`).
///
/// Rules:
/// - Deterministic polling (every 2s) by the caller.
/// - Cold-start wake-up check: ping `/health`, show "Waking up research
///   node...".
/// - Fallback to mock adapter when no research-service URL is configured.
///
/// Tauri deviation: the TS build resolved `VITE_RESEARCH_URL` /
/// `VITE_RESEARCH_TOKEN` from Vite env vars or a runtime-injected window
/// global. The Dart port resolves, in priority order:
///   1. a runtime override set via [setResearchConfig] (desktop shell /
///      tests),
///   2. compile-time `--dart-define=VITE_RESEARCH_URL|VITE_RESEARCH_TOKEN`
///      (or the unprefixed `RESEARCH_URL` / `RESEARCH_TOKEN`),
///   3. the process environment,
///   4. nothing → fall back to the mock adapter so dev still works.

// ─── Wire types ─────────────────────────────────────────────────────────────

/// Job lifecycle state, as reported by the service.
enum ResearchState {
  running('running'),
  completed('completed'),
  partial('partial'),
  failed('failed'),
  timedOut('timed_out'),
  interrupted('interrupted');

  final String wire;
  const ResearchState(this.wire);

  static ResearchState fromWire(String? value) => ResearchState.values
      .firstWhere((s) => s.wire == value, orElse: () => ResearchState.running);
}

/// One cited source of a research job.
class ResearchSource {
  final String id;
  final String title;
  final String url;
  const ResearchSource({required this.id, required this.title, required this.url});

  factory ResearchSource.fromJson(Map<String, dynamic> j) => ResearchSource(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'url': url};
}

/// A partial summary produced before the job completes.
class ResearchPartialSummary {
  final String sourceId;
  final String title;
  final String summary;
  const ResearchPartialSummary({
    required this.sourceId,
    required this.title,
    required this.summary,
  });

  factory ResearchPartialSummary.fromJson(Map<String, dynamic> j) =>
      ResearchPartialSummary(
        sourceId: j['source_id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'source_id': sourceId, 'title': title, 'summary': summary};
}

/// Status payload of a research job (wire shape kept snake_case).
class ResearchJobStatus {
  String jobId;
  String query;
  ResearchState state;
  int progress;
  String currentStage;
  int elapsedSeconds;
  int sourcesCount;
  List<ResearchSource> sources;
  List<ResearchPartialSummary> partialSummaries;
  String? finalReport;
  String? error;

  /// Fields are mutable: the mock provider advances a stored job over time,
  /// mirroring the object mutation in the TS implementation.
  ResearchJobStatus({
    required this.jobId,
    required this.query,
    required this.state,
    required this.progress,
    required this.currentStage,
    required this.elapsedSeconds,
    required this.sourcesCount,
    required this.sources,
    required this.partialSummaries,
    this.finalReport,
    this.error,
  });

  factory ResearchJobStatus.fromJson(Map<String, dynamic> j) =>
      ResearchJobStatus(
        jobId: j['job_id'] as String? ?? '',
        query: j['query'] as String? ?? '',
        state: ResearchState.fromWire(j['state'] as String?),
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        currentStage: j['current_stage'] as String? ?? '',
        elapsedSeconds: (j['elapsed_seconds'] as num?)?.toInt() ?? 0,
        sourcesCount: (j['sources_count'] as num?)?.toInt() ?? 0,
        sources: (j['sources'] as List? ?? const [])
            .whereType<Map>()
            .map((s) => ResearchSource.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
        partialSummaries: (j['partial_summaries'] as List? ?? const [])
            .whereType<Map>()
            .map((s) =>
                ResearchPartialSummary.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
        finalReport: j['final_report'] as String?,
        error: j['error'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'job_id': jobId,
        'query': query,
        'state': state.wire,
        'progress': progress,
        'current_stage': currentStage,
        'elapsed_seconds': elapsedSeconds,
        'sources_count': sourcesCount,
        'sources': sources.map((s) => s.toJson()).toList(),
        'partial_summaries': partialSummaries.map((s) => s.toJson()).toList(),
        if (finalReport != null) 'final_report': finalReport,
        if (error != null) 'error': error,
      };
}

/// Handle returned when a job is submitted.
class ResearchStartResult {
  final String jobId;
  const ResearchStartResult({required this.jobId});

  factory ResearchStartResult.fromJson(Map<String, dynamic> j) =>
      ResearchStartResult(jobId: j['job_id'] as String? ?? '');

  Map<String, dynamic> toJson() => {'job_id': jobId};
}

// ─── Provider interface ─────────────────────────────────────────────────────

abstract class ResearchProvider {
  /// `live` talks to the service; `demo` is the simulated fallback.
  String get mode;

  bool isAvailable();

  Future<bool> checkHealth();

  Future<ResearchStartResult> startResearch(String query, {int maxSources});

  Future<ResearchJobStatus> getStatus(String jobId);
}

// ─── HTTP implementation ────────────────────────────────────────────────────

/// Talks to a live research-service deployment over HTTP.
class HttpResearchProvider implements ResearchProvider {
  HttpResearchProvider(this.baseUrl, [this.token]);

  final String baseUrl;
  final String? token;

  @override
  String get mode => 'live';

  @override
  bool isAvailable() => baseUrl.isNotEmpty;

  @override
  Future<bool> checkHealth() async {
    try {
      final res =
          await http.get(Uri.parse('$baseUrl/health')).timeout(
                const Duration(seconds: 5),
              );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ResearchStartResult> startResearch(String query,
      {int maxSources = 5}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final t = token;
    if (t != null && t.isNotEmpty) headers['X-Research-Token'] = t;

    final res = await http.post(
      Uri.parse('$baseUrl/research'),
      headers: headers,
      body: jsonEncode(<String, dynamic>{
        'query': query,
        'max_sources': maxSources,
      }),
    );

    if (res.statusCode == 429) {
      throw Exception(
          'Research node is currently busy with another active job. Please retry shortly.');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
          'Research submission failed (${res.statusCode}): ${res.body}');
    }

    return ResearchStartResult.fromJson(
        _decodeJsonObject(res.body));
  }

  @override
  Future<ResearchJobStatus> getStatus(String jobId) async {
    final headers = <String, String>{};
    final t = token;
    if (t != null && t.isNotEmpty) headers['X-Research-Token'] = t;

    final res = await http.get(Uri.parse('$baseUrl/research/$jobId'),
        headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to fetch research status (${res.statusCode})');
    }
    return ResearchJobStatus.fromJson(_decodeJsonObject(res.body));
  }
}

Map<String, dynamic> _decodeJsonObject(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  throw const FormatException('Expected a JSON object response');
}

// ─── Mock implementation ────────────────────────────────────────────────────

/// Provides realistic simulated research runs for local dev/testing.
class MockResearchProvider implements ResearchProvider {
  final Map<String, ResearchJobStatus> _jobs = <String, ResearchJobStatus>{};

  @override
  String get mode => 'demo';

  @override
  bool isAvailable() => true;

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<ResearchStartResult> startResearch(String query,
      {int maxSources = 5}) async {
    final jobId = 'mock-res-${DateTime.now().millisecondsSinceEpoch}';
    final initial = ResearchJobStatus(
      jobId: jobId,
      query: query,
      state: ResearchState.running,
      progress: 10,
      currentStage: 'search',
      elapsedSeconds: 0,
      sourcesCount: 0,
      sources: const [],
      partialSummaries: const [],
    );
    _jobs[jobId] = initial;

    // Simulate progress in background
    Timer(const Duration(seconds: 2), () {
      final j = _jobs[jobId];
      if (j == null) return;
      j.currentStage = 'extract';
      j.progress = 30;
      j.sourcesCount = 3;
      j.sources = const [
        ResearchSource(
            id: '[S1]',
            title: 'Autonomous Agents Overview',
            url: 'https://example.com/agents'),
        ResearchSource(
            id: '[S2]',
            title: 'Local-First Software Architecture',
            url: 'https://example.com/local-first'),
        ResearchSource(
            id: '[S3]',
            title: 'Deterministic Pipelines in AI',
            url: 'https://example.com/pipelines'),
      ];
    });

    Timer(const Duration(milliseconds: 4500), () {
      final j = _jobs[jobId];
      if (j == null) return;
      j.currentStage = 'map';
      j.progress = 60;
      j.partialSummaries = const [
        ResearchPartialSummary(
          sourceId: '[S1]',
          title: 'Autonomous Agents Overview',
          summary:
              'Outlines standard agent loop limits and single-agent constraints.',
        ),
        ResearchPartialSummary(
          sourceId: '[S2]',
          title: 'Local-First Software Architecture',
          summary: 'Discusses user-controlled storage and zero-cloud dependency.',
        ),
      ];
    });

    Timer(const Duration(seconds: 7), () {
      final j = _jobs[jobId];
      if (j == null) return;
      j.currentStage = 'done';
      j.progress = 100;
      j.state = ResearchState.completed;
      j.finalReport = '## Executive Summary\n' +
          'This report investigates $query based on 3 analyzed sources.\n\n' +
          '## Key Findings\n' +
          '- Local-first architectures guarantee data persistence without vendor lock-in [[S2: Local-First Software Architecture]](https://example.com/local-first).\n' +
          '- Deterministic pipelines avoid recursive agent planning failures [[S3: Deterministic Pipelines in AI]](https://example.com/pipelines).\n' +
          '- Strict memory caps allow containers to run efficiently on low-cost cloud nodes [[S1: Autonomous Agents Overview]](https://example.com/agents).\n\n' +
          '## Conclusion\n' +
          'The research demonstrates that bounded pipelines achieve high citation reliability while respecting 512 MB memory envelopes.';
    });

    return ResearchStartResult(jobId: jobId);
  }

  @override
  Future<ResearchJobStatus> getStatus(String jobId) async {
    final job = _jobs[jobId];
    if (job == null) throw Exception('Job not found');
    return job;
  }
}

// ─── Singleton resolution ───────────────────────────────────────────────────

ResearchProvider? _activeProvider;

/// Runtime override for the service URL, mimicking the TS build's
/// `window.__RESEARCH_URL__` injection point.
String? _runtimeUrl;
/// Runtime override for the service token (`window.__RESEARCH_TOKEN__`).
String? _runtimeToken;

/// Inject the research service URL/token at runtime (desktop shell, tests).
void setResearchConfig({String? url, String? token}) {
  if (url != null) _runtimeUrl = url;
  if (token != null) _runtimeToken = token;
  _activeProvider = null;
}

/// Reset the cached provider (tests).
void resetResearchProvider() {
  _activeProvider = null;
  _runtimeUrl = null;
  _runtimeToken = null;
}

const String _envResearchUrl =
    String.fromEnvironment('VITE_RESEARCH_URL') != ''
        ? String.fromEnvironment('VITE_RESEARCH_URL')
        : String.fromEnvironment('RESEARCH_URL');

const String _envResearchToken =
    String.fromEnvironment('VITE_RESEARCH_TOKEN') != ''
        ? String.fromEnvironment('VITE_RESEARCH_TOKEN')
        : String.fromEnvironment('RESEARCH_TOKEN');

/// Return the active provider, creating it on first use.
///
/// Resolution order: runtime override → compile-time dart-define → process
/// environment → mock fallback.
ResearchProvider getResearchProvider() {
  if (_activeProvider == null) {
    final env = Platform.environment;
    final url = _runtimeUrl ??
        (_envResearchUrl.isNotEmpty ? _envResearchUrl : null) ??
        env['VITE_RESEARCH_URL'] ??
        env['RESEARCH_URL'];
    final token = _runtimeToken ??
        (_envResearchToken.isNotEmpty ? _envResearchToken : null) ??
        env['VITE_RESEARCH_TOKEN'] ??
        env['RESEARCH_TOKEN'];

    if (url != null && url.isNotEmpty) {
      _activeProvider = HttpResearchProvider(url, token);
    } else {
      _activeProvider = MockResearchProvider();
    }
  }
  return _activeProvider!;
}
