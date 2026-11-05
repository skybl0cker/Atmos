import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/weather.dart';
import '../state/app_state.dart';
import '../widgets/scene.dart';
import '../widgets/scene_page.dart';

const _accent = Color(0xFF6C63FF);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Place> _results = [];
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      setState(() {
        _results = [];
        _err = null;
        _busy = false;
      });
      return;
    }
    setState(() {}); // refresh the clear button
    final state = context.read<AppState>();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _busy = true);
      try {
        final r = await state.search(query);
        if (!mounted) return;
        setState(() {
          _results = r;
          _err = null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _err = 'Search failed. Check your connection.');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  void _pick(Place p) {
    context.read<AppState>().selectPlace(p);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final searching = _ctrl.text.trim().length >= 2;

    return ScenePage(
      title: 'Places',
      subtitle: 'Search a city or pick a saved place',
      sceneHeight: 0.3,
      header: SceneSearchField(
        controller: _ctrl,
        hint: 'Search for a city…',
        autofocus: true,
        busy: _busy,
        onChanged: _onChanged,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey(searching),
          child: searching ? _resultsList() : _savedList(s),
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String text) {
    final pal = SheetPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      children: [
        Icon(icon, size: 44, color: pal.faint),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.soft, fontSize: 14)),
      ],
    );
  }

  Widget _resultsList() {
    if (_err != null) return _empty(Icons.cloud_off_rounded, _err!);
    if (_results.isEmpty && !_busy) {
      return _empty(Icons.travel_explore_rounded, 'No matching places');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
      children: [
        for (final p in _results)
          SheetRow(
            icon: Icons.location_on_rounded,
            iconColor: _accent,
            title: p.name,
            subtitle: p.subtitle,
            trailing: Icon(Icons.chevron_right_rounded,
                color: SheetPalette.of(context).faint),
            onTap: () => _pick(p),
          ),
      ],
    );
  }

  Widget _savedList(AppState s) {
    final pal = SheetPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
      children: [
        SheetRow(
          icon: Icons.my_location_rounded,
          iconColor: const Color(0xFF3F8CFF),
          title: 'Use my location',
          subtitle: 'Weather for wherever you are',
          onTap: () {
            s.useMyLocation();
            Navigator.pop(context);
          },
        ),
        const SheetLabel('Saved places'),
        for (final p in s.saved)
          Dismissible(
            key: ValueKey(p.key),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5A5F),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white),
            ),
            onDismissed: (_) => s.removePlace(p),
            child: SheetRow(
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFFFB524),
              title: p.name,
              subtitle: p.subtitle,
              highlighted: p.key == s.selected?.key,
              trailing: p.key == s.selected?.key
                  ? const Text('Showing',
                      style: TextStyle(
                          color: _accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600))
                  : null,
              onTap: () => _pick(p),
            ),
          ),
        if (s.saved.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
            child: Text(
              'Open a city and tap the star to keep it here. Swipe left on a saved place to remove it.',
              style: TextStyle(color: pal.soft, fontSize: 13, height: 1.4),
            ),
          ),
      ],
    );
  }
}
