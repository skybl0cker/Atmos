import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/alert.dart';
import '../state/app_state.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AppState>().alerts;
    return Scaffold(
      appBar: AppBar(title: const Text('Active alerts')),
      body: alerts.isEmpty
          ? const Center(child: Text('No active alerts for this location'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _AlertCard(alerts[i]),
            ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final WeatherAlert a;
  const _AlertCard(this.a);

  @override
  Widget build(BuildContext context) {
    final color = a.isSevere ? const Color(0xFFD32F2F) : const Color(0xFFF57C00);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.warning_amber_rounded, color: color),
        title: Text(a.event, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          a.expires == null
              ? a.areas
              : 'Until ${DateFormat.MMMd().add_jm().format(a.expires!)} · ${a.areas}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (a.description.isNotEmpty) ...[
                      Text(a.description),
                      const SizedBox(height: 12),
                    ],
                    if (a.instruction.isNotEmpty) ...[
                      const Text('What to do',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(a.instruction),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
