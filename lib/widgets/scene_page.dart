import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'pressable.dart';
import 'scene.dart';

/// Circular icon button. [solid] = white disc with dark glyph (over maps);
/// otherwise a soft translucent disc with a white glyph (over the scene).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool solid;
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    final enabled = onTap != null;
    final fg = solid ? pal.ink : Colors.white;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        semanticLabel: tooltip,
        onTap: onTap ?? () {},
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: solid ? pal.bg : Colors.white.withAlpha(46),
              border: solid
                  ? null
                  : Border.all(color: Colors.white.withAlpha(70)),
              boxShadow: solid
                  ? const [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 12,
                          offset: Offset(0, 4)),
                    ]
                  : null,
            ),
            child: Icon(icon, color: fg, size: 21),
          ),
        ),
      ),
    );
  }
}

/// Back button + title (and optional subtitle) + trailing actions, in the
/// home screen's type style.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool solidButtons;
  final Color color;
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.solidButtons = false,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0x33000000), blurRadius: 14)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          RoundIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            solid: solidButtons,
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                        shadows: solidButtons ? null : shadow)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color.withAlpha(215),
                          fontSize: 12,
                          shadows: solidButtons ? null : shadow)),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}

/// Secondary-screen frame matching home: the watercolor scene as a header
/// (with [header] content such as a search field over it), then a white
/// rounded sheet holding [body], and an optional pinned [bottomBar].
class ScenePage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? header;
  final Widget body;
  final Widget? bottomBar;
  final double sceneHeight;
  const ScenePage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.header,
    required this.body,
    this.bottomBar,
    this.sceneHeight = 0.34,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.watch<AppState>().data;
    final pal = SheetPalette.of(context);
    final h = MediaQuery.sizeOf(context).height;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: pal.bg,
        body: Stack(
          children: [
            SizedBox(height: h * sceneHeight + 40, child: Scene(data: d)),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  PageHeader(title: title, subtitle: subtitle, actions: actions),
                  if (header != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: header!,
                    ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: pal.bg,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(38)),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 30,
                              offset: Offset(0, -6)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(38)),
                        child: body,
                      ),
                    ),
                  ),
                  ?bottomBar,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded white pill text field that floats over the scene.
class SceneSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final bool busy;
  const SceneSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(Icons.search_rounded, color: pal.soft),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: pal.ink, fontSize: 15),
              cursorColor: const Color(0xFF6C63FF),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: pal.soft, fontSize: 15),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF6C63FF)),
              ),
            )
          else if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: Icon(Icons.close_rounded, color: pal.soft),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
        ],
      ),
    );
  }
}

/// Small caps section label used inside sheets.
class SheetLabel extends StatelessWidget {
  final String text;
  const SheetLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              color: pal.soft,
              fontSize: 11,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// A rounded list row: tinted icon disc, title, subtitle, trailing.
class SheetRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlighted;
  const SheetRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Material(
        color: highlighted ? iconColor.withAlpha(pal.dark ? 50 : 26) : pal.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap == null
              ? null
              : () {
                  tapHaptic(context);
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(pal.dark ? 55 : 30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: pal.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: pal.soft, fontSize: 12)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
