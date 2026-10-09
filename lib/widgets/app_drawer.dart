import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/weather.dart';
import '../screens/search_screen.dart';
import '../state/app_state.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.wb_sunny_rounded, size: 28),
                  const SizedBox(width: 10),
                  Text('Atmos', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('My location'),
              onTap: () {
                Navigator.pop(context);
                s.useMyLocation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add a place'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SearchScreen()));
              },
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  for (final p in s.saved)
                    ListTile(
                      leading: Icon(Icons.star,
                          color: p.key == s.selected?.key
                              ? Theme.of(context).colorScheme.primary
                              : Colors.amber),
                      title: Text(p.name),
                      subtitle: p.subtitle.isEmpty ? null : Text(p.subtitle),
                      selected: p.key == s.selected?.key,
                      onLongPress: () => _confirmRemove(context, s, p),
                      onTap: () {
                        Navigator.pop(context);
                        s.selectPlace(p);
                      },
                    ),
                  if (s.saved.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Save places from the weather screen to see them here.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.thermostat),
              title: Text(s.imperial ? '°F, mph' : '°C, km/h'),
              value: s.imperial,
              onChanged: (_) => s.toggleUnits(),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: const Text('Haptics for rain/storms'),
              value: s.hapticsEnabled,
              onChanged: (_) => s.toggleHaptics(),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Alert notifications'),
              subtitle: const Text('Checked when the app refreshes', style: TextStyle(fontSize: 11)),
              value: s.notificationsEnabled,
              onChanged: (_) => s.toggleNotifications(),
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Theme'),
              trailing: Text(s.themeLabel),
              onTap: s.cycleTheme,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(BuildContext context, AppState s, Place p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              s.removePlace(p);
              Navigator.pop(context);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
