/// Research overlay (M8) — deep research as a full surface, not a pane.
///
/// The pipeline is bounded and sequential: Search → Extract → Map → Reduce.
/// Citations that do not resolve to a retrieved source are never shown.
/// Port of `src/surfaces/ResearchOverlay.tsx`.
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/adapters/research_adapter.dart';
import '../../core/theme/lively_tokens.dart';
import '../../shared/markdown_view.dart';
import 'overlay_surface.dart';

const List<String> _stages = ['search', 'extract', 'map', 'reduce'];

const Map<String, String> _stageLabels = {
  'search': 'Search',
  'extract': 'Extract',
  'map': 'Map',
  'reduce': 'Reduce',
  'done': 'Done',
};

const Map<String, String> _stateLabels = {
  'connecting': 'Connecting',
  'running': 'Running',
  'completed': 'Complete',
  'partial': 'Partial',
  'failed': 'Failed',
  'timed_out': 'Timed out',
  'interrupted': 'Interrupted',
};

/// Only real web links are rendered as links; anything else stays plain text.
bool _isSafeHttpUrl(String url) {
  final parsed = Uri.tryParse(url);
  return parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https');
}

class ResearchOverlay extends StatefulWidget {
  final String query;
  final VoidCallback onClose;

  const ResearchOverlay({super.key, required this.query, required this.onClose});

  @override
  State<ResearchOverlay> createState() => _ResearchOverlayState();
}

class _ResearchOverlayState extends State<ResearchOverlay> {
  ResearchJobStatus? _status;
  bool _wakingUp = true;
  String? _error;
  Timer? _timer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void didUpdateWidget(ResearchOverlay old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _timer?.cancel();
      _status = null;
      _error = null;
      _wakingUp = true;
      _begin();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    final query = widget.query;
    final provider = getResearchProvider();
    try {
      final healthy = await provider.checkHealth();
      if (_disposed || query != widget.query) return;
      if (!healthy) {
        throw Exception(
            'Research service is unavailable. Check that it is running and try again.');
      }
      setState(() => _wakingUp = false);
      final started = await provider.startResearch(query);
      if (_disposed || query != widget.query) return;
      _poll(provider, started.jobId, query);
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _wakingUp = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// Deterministic 2 s polling that stops once the job leaves `running`.
  void _poll(ResearchProvider provider, String jobId, String query) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await provider.getStatus(jobId);
        if (_disposed || query != widget.query) {
          timer.cancel();
          return;
        }
        setState(() => _status = status);
        if (status.state != ResearchState.running) timer.cancel();
      } catch (e) {
        if (_disposed) return;
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    final status = _status;
    final provider = getResearchProvider();

    final currentStage = status?.currentStage ?? 'search';
    // No job yet means no stage is running; an error before the first poll
    // is a connection failure, not a job stuck on "Search".
    final stageIndex = status != null ? _stages.indexOf(currentStage) : -1;
    final done = status?.state == ResearchState.completed ||
        status?.state == ResearchState.partial;
    final connectionFailed = _error != null && status == null;
    final failed = connectionFailed ||
        status?.state == ResearchState.failed ||
        status?.state == ResearchState.timedOut ||
        status?.state == ResearchState.interrupted;
    final surfacedError = _error ?? status?.error;
    final demo = provider.mode == 'demo';
    final jobState = status?.state.wire ??
        (connectionFailed ? 'failed' : (_wakingUp ? 'connecting' : 'running'));
    final stateColor = jobState == 'completed'
        ? Lively.appleGreen
        : (failed ? Lively.appleRed : Lively.orange500);

    final report = status?.finalReport ?? '';
    final hasReport = report.isNotEmpty;

    return OverlaySurface(
      title: 'Deep Research Report',
      onClose: widget.onClose,
      maxHeight: 520,
      badge: Row(mainAxisSize: MainAxisSize.min, children: [
        if (demo) ...[
          OverlayBadge(label: 'Demo data', color: Lively.orange500),
          const SizedBox(width: Lively.s1),
        ],
        OverlayBadge(label: _stateLabels[jobState] ?? jobState, color: stateColor),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (demo)
            SurfaceCallout(
              tone: 'warn',
              icon: f.FluentIcons.warning,
              children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(
                      text: 'Simulated report. ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const TextSpan(
                      text: 'No research service is connected, so the sources and '
                          'findings below are demo data.'),
                ], style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote))),
              ],
            ),
          if (_wakingUp)
            SurfaceCallout(
              tone: 'info',
              icon: f.FluentIcons.info,
              children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(
                      text: 'Connecting to the research node… ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const TextSpan(text: 'This can take a moment if the service was idle.'),
                ], style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote))),
              ],
            ),
          if (surfacedError != null)
            SurfaceCallout(
              tone: failed ? 'bad' : 'warn',
              icon: f.FluentIcons.warning,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: failed ? 'Research failed. ' : 'Research error. ',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: surfacedError),
                ], style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote))),
              ],
            ),
          for (var i = 0; i < _stages.length; i++)
            _StageRow(
              label: _stageLabels[_stages[i]]!,
              state: done || (stageIndex >= 0 && i < stageIndex)
                  ? _StageState.done
                  : (i == stageIndex ? _StageState.active : _StageState.pending),
              progress: status?.progress ?? 0,
            ),
          if (status != null && status.sources.isNotEmpty) ...[
            const SizedBox(height: Lively.s3),
            for (final source in status.sources)
              _SourceRow(id: source.id, title: source.title, url: source.url),
          ],
          if (hasReport) ...[
            const SizedBox(height: Lively.s3),
            MarkdownView(content: report),
          ],
          if (!hasReport &&
              status != null &&
              status.partialSummaries.isNotEmpty) ...[
            const SizedBox(height: Lively.s3),
            for (final partial in status.partialSummaries)
              _SourceRow(id: partial.sourceId, title: partial.summary),
          ],
        ],
      ),
    );
  }
}

enum _StageState { pending, active, done }

class _StageRow extends StatelessWidget {
  final String label;
  final _StageState state;
  final int progress;
  const _StageRow({required this.label, required this.state, required this.progress});

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    final done = state == _StageState.done;
    final active = state == _StageState.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: Lively.s2),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: done
                  ? Lively.accent(b)
                  : (active ? Lively.accentMuted(b) : Lively.fill(b, 1)),
              shape: BoxShape.circle,
              border: active ? Border.all(color: Lively.accent(b), width: 2) : null,
            ),
            child: done
                ? const Icon(f.FluentIcons.check_mark, size: 11, color: Colors.white)
                : null,
          ),
          const SizedBox(width: Lively.s2),
          Text(
            label,
            style: TextStyle(
              color: Lively.textPrimary(b),
              fontSize: Lively.tFootnote,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(width: Lively.s2),
          Text(
            done ? 'done' : (active ? '$progress%' : ''),
            style: TextStyle(color: Lively.textTertiary(b), fontSize: Lively.tMicro),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final String id;
  final String title;
  final String? url;
  const _SourceRow({required this.id, required this.title, this.url});

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    final link = url != null && _isSafeHttpUrl(url!);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Lively.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            id,
            style: TextStyle(
              color: Lively.textTertiary(b),
              fontSize: Lively.tMicro,
              fontFamily: 'Consolas',
            ),
          ),
          const SizedBox(width: Lively.s2),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: link ? Lively.accentText(b) : Lively.textPrimary(b),
                fontSize: Lively.tFootnote,
              ),
            ),
          ),
        ],
      ),
    );
    if (!link) return row;
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: row,
    );
  }
}
