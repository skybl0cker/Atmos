import 'package:flutter/material.dart';

import '../services/severe_event_service.dart';

/// The dynamic 4th tab: whatever major severe event is active nationwide —
/// hurricane, tornado outbreak, flash flood emergency, etc. Icon and label
/// in the bottom bar follow the event automatically.
class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  SevereEvent? _event;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _event = null;
      _failed = false;
    });
    try {
      final e = await SevereEventService.current();
      if (mounted) setState(() => _event = e);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Severe Weather'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: e == null
          ? Center(
              child: _failed
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Could not load alerts. Check your connection and tap refresh.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _EventHeader(event: e),
                  const SizedBox(height: 16),
                  if (e.instruction.isNotEmpty) _InstructionBox(event: e),
                  if (e.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Details',
                      child: Text(
                        e.description,
                        style: const TextStyle(height: 1.45),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Source: National Weather Service',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}

class _EventHeader extends StatelessWidget {
  final SevereEvent event;
  const _EventHeader({required this.event});

  @override
  Widget build(BuildContext context) {
    final quiet = event.kind == SevereKind.none;
    return Card(
      color: quiet ? null : event.color.withAlpha(28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: quiet
            ? BorderSide.none
            : BorderSide(color: event.color.withAlpha(120)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(event.tabIcon, size: 56, color: event.color),
            const SizedBox(height: 12),
            Text(
              event.title,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            if (event.headline.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                event.headline,
                style: const TextStyle(
                    fontSize: 13, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            _MetaRow(
                icon: Icons.place_outlined, text: event.areas),
            if (event.alertCount > 1)
              _MetaRow(
                icon: Icons.warning_amber_outlined,
                text:
                    '${event.alertCount} active ${event.title.toLowerCase()} alerts',
              ),
            if (event.expires != null)
              _MetaRow(
                icon: Icons.schedule_outlined,
                text: 'In effect until ${_fmtTime(event.expires!)}',
              ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ap = dt.hour < 12 ? 'AM' : 'PM';
      return '$h:${dt.minute.toString().padLeft(2, '0')} $ap';
    } catch (_) {
      return iso;
    }
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: Colors.white54),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style:
                  const TextStyle(fontSize: 13, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionBox extends StatelessWidget {
  final SevereEvent event;
  const _InstructionBox({required this.event});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: event.color.withAlpha(36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: event.color),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined,
                color: event.color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                event.instruction,
                style: const TextStyle(
                    fontSize: 14, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
