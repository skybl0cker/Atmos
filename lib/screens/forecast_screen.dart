import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/light_daily_list.dart';
import '../widgets/scene.dart';

/// 14-day outlook: the same watercolor scene up top, the list on a white
/// sheet below — matching the home screen.
class ForecastScreen extends StatelessWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final place = s.selected;
    final pal = SheetPalette.of(context);
    final h = MediaQuery.sizeOf(context).height;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: pal.bg,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('14-Day Forecast',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
              if (place != null)
                Text(place.name,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white70)),
            ],
          ),
        ),
        body: Stack(
          children: [
            SizedBox(
              height: h * 0.42,
              child: Scene(data: s.data),
            ),
            ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(top: h * 0.3),
              children: [
                Container(
                  constraints: BoxConstraints(minHeight: h * 0.7),
                  decoration: BoxDecoration(
                    color: pal.bg,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(38)),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 30,
                          offset: Offset(0, -6)),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 22, 14, 32),
                  child: s.data == null
                      ? const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : const LightDailyList(maxDays: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
