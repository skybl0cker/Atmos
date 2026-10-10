import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/weather.dart';
import '../screens/search_screen.dart';
import '../state/app_state.dart';

/// Sidebar restyled for the illustrated UI: a scenic header banner,
/// rounded tiles, and purple accents throughout.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor:
          dark ? const Color(0xFF1B1440) : const Color(0xFFF7F4FF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Illustrated header.
            Container(
              height: 150,
              decoration: const BoxDecoration(
                borderRadius:
                    BorderRadius.only(bottomRight: Radius.circular(28)),
                image: DecorationImage(
                  image:
                      AssetImage('assets/backgrounds/bg_day.webp'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(28)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(90),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(20),
                alignment: Alignment.bottomLeft,
                child: const Text('Atmos',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
            _tile(
              context,
              icon: Icons.my_location,
              label: 'My location',
              onTap: () {
                Navigator.pop(context);
                s.useMyLocation();
              },
            ),
            _tile(
              context,
              icon: Icons.add_circle_outline,
              label: 'Add a place',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()));
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('SAVED PLACES',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white54 : Colors.black45)),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final p in s.saved)
                    _placeTile(context, s, p, dark),
                  if (s.saved.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                          'Save places from the weather screen to see them here.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            _switch(
              context,
              icon: Icons.thermostat,
              label: s.imperial ? '°F, mph' : '°C, km/h',
              value: s.imperial,
              onChanged: (_) => s.toggleUnits(),
            ),
            _switch(
              context,
              icon: Icons.vibration,
              label: 'Haptics for rain/storms',
              value: s.hapticsEnabled,
              onChanged: (_) => s.toggleHaptics(),
            ),
            _switch(
              context,
              icon: Icons.notifications_outlined,
              label: 'Alert notifications',
              value: s.notificationsEnabled,
              onChanged: (_) => s.toggleNotifications(),
            ),
            _tile(
              context,
              icon: Icons.brightness_6_outlined,
              label: 'Theme · ${s.themeLabel}',
              onTap: s.cycleTheme,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: const Color(0xFF7C4DFF)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: onTap,
      ),
    );
  }

  Widget _placeTile(
      BuildContext context, AppState s, Place p, bool dark) {
    final selected = p.key == s.selected?.key;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: selected
            ? const Color(0xFF7C4DFF).withAlpha(dark ? 50 : 26)
            : null,
        leading: Icon(Icons.star,
            color: selected
                ? const Color(0xFF7C4DFF)
                : Colors.amber),
        title: Text(p.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            p.subtitle.isEmpty ? null : Text(p.subtitle),
        onLongPress: () => _confirmRemove(context, s, p),
        onTap: () {
          Navigator.pop(context);
          s.selectPlace(p);
        },
      ),
    );
  }

  Widget _switch(BuildContext context,
      {required IconData icon,
      required String label,
      required bool value,
      required ValueChanged<bool> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SwitchListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        secondary: Icon(icon, color: const Color(0xFF7C4DFF)),
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  void _confirmRemove(BuildContext context, AppState s, Place p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
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
