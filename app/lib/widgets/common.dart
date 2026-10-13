import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api.dart';
import '../theme/brand.dart';

/// Opens a page on top of the current one.
Future<T?> go<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

/// Back to the first page (after log in / log out the first page shows the right screen).
void toRoot(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

/// Short message at the bottom of the screen. [error] shows it in red text with a red border.
void toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(error
      ? SnackBar(
          content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Brand.red, fontWeight: FontWeight.w700)),
          backgroundColor: Brand.redLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Brand.red, width: 1.4)),
          duration: const Duration(seconds: 4),
        )
      : SnackBar(content: Text(msg, textAlign: TextAlign.center), duration: const Duration(seconds: 3)));
}

/// Card with the blue border.
class Box extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool filled;
  final bool tint;
  final EdgeInsets padding;
  const Box({super.key, required this.child, this.onTap, this.filled = false, this.tint = false, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final bg = filled ? Brand.blue : (tint ? Brand.light : Colors.white);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Brand.blue, width: 1.2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: DefaultTextStyle.merge(style: TextStyle(color: filled ? Colors.white : Brand.ink), child: child),
        ),
      ),
    );
  }
}

/// Small grey label above a group or a field.
class Label extends StatelessWidget {
  final String text;
  const Label(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Brand.muted, letterSpacing: 0.2));
}

/// Section title inside a page, with an optional item on the right.
class Section extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const Section(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Brand.ink))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Empty space of the same size both ways.
class Gap extends StatelessWidget {
  final double size;
  const Gap([this.size = 10, Key? key]) : super(key: key);

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

/// Status tag. Filled = strong (blue), otherwise outlined; [red] for declined / cancelled.
class Tag extends StatelessWidget {
  final String text;
  final bool filled;
  final bool red;
  const Tag(this.text, {super.key, this.filled = false, this.red = false});

  @override
  Widget build(BuildContext context) {
    final c = red ? Brand.red : Brand.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: filled ? c : Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: c)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: filled ? Colors.white : c)),
    );
  }
}

/// Full-width button. [busy] shows a spinner and blocks taps.
class Btn extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool outline;
  final IconData? icon;
  final bool small;
  final bool busy;
  const Btn(this.text, this.onTap, {super.key, this.outline = false, this.icon, this.small = false, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? const Size(0, 38) : const Size(0, 48);
    final Widget label = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: outline ? Brand.blue : Colors.white),
          )
        : Text(text, textAlign: TextAlign.center);
    final tap = busy ? () {} : onTap;
    final Widget b;
    if (outline) {
      b = icon == null || busy
          ? OutlinedButton(onPressed: tap, style: OutlinedButton.styleFrom(minimumSize: size), child: label)
          : OutlinedButton.icon(onPressed: tap, style: OutlinedButton.styleFrom(minimumSize: size), icon: Icon(icon, size: 18), label: label);
    } else {
      b = icon == null || busy
          ? FilledButton(onPressed: tap, style: FilledButton.styleFrom(minimumSize: size), child: label)
          : FilledButton.icon(onPressed: tap, style: FilledButton.styleFrom(minimumSize: size), icon: Icon(icon, size: 18), label: label);
    }
    return SizedBox(width: double.infinity, child: b);
  }
}

/// Underlined blue text that works like a button (Forgot password, Continue as guest).
class LinkText extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const LinkText(this.text, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            text,
            style: TextStyle(
              color: onTap == null ? Brand.muted : Brand.blue,
              fontWeight: FontWeight.w700,
              decoration: onTap == null ? null : TextDecoration.underline,
              decorationColor: Brand.blue,
            ),
          ),
        ),
      );
}

enum FieldKind { text, phone, email, password, number, money, name }

/// Text field with a grey label above it (wireframe style).
class Field extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final FieldKind kind;
  final int lines;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Red border: this field is missing or wrong.
  final bool error;
  const Field(
    this.label,
    this.controller, {
    super.key,
    this.hint,
    this.helper,
    this.kind = FieldKind.text,
    this.lines = 1,
    this.action,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.error = false,
  });

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    final password = k == FieldKind.password;
    TextInputType type = TextInputType.text;
    List<String>? autofill;
    List<TextInputFormatter>? formatters;
    switch (k) {
      case FieldKind.phone:
        type = TextInputType.phone;
        autofill = const [AutofillHints.telephoneNumber];
        formatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')), LengthLimitingTextInputFormatter(16)];
      case FieldKind.email:
        type = TextInputType.emailAddress;
        autofill = const [AutofillHints.email];
      case FieldKind.password:
        type = TextInputType.visiblePassword;
        autofill = const [AutofillHints.password];
      case FieldKind.number:
        type = TextInputType.number;
        formatters = [FilteringTextInputFormatter.digitsOnly];
      case FieldKind.money:
        type = const TextInputType.numberWithOptions(decimal: true);
        formatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), LengthLimitingTextInputFormatter(9)];
      case FieldKind.name:
        type = TextInputType.name;
        autofill = const [AutofillHints.name];
      case FieldKind.text:
        type = widget.lines > 1 ? TextInputType.multiline : TextInputType.text;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Label(widget.label),
        const SizedBox(height: 5),
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: password && _hidden,
          enableSuggestions: !password,
          autocorrect: !password && k != FieldKind.email,
          maxLines: password ? 1 : widget.lines,
          keyboardType: type,
          autofillHints: autofill,
          inputFormatters: formatters,
          textCapitalization: k == FieldKind.name ? TextCapitalization.words : TextCapitalization.none,
          textInputAction: widget.action,
          onSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixText: k == FieldKind.money ? '₱ ' : null,
            fillColor: widget.error ? Brand.redLight : (widget.enabled ? Colors.white : Brand.light),
            enabledBorder: widget.error
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Brand.red, width: 1.6))
                : null,
            focusedBorder: widget.error
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Brand.red, width: 2.2))
                : null,
            suffixIcon: password
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Brand.muted),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
        if (widget.helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(widget.helper!, style: const TextStyle(fontSize: 12, color: Brand.muted)),
          ),
      ]),
    );
  }
}

/// Two or more options side by side (Refill / Package, Paid / Unpaid, Pin on map / Type address).
class Seg extends StatelessWidget {
  final List<String> options;
  final int value;
  final ValueChanged<int> onChanged;
  const Seg(this.options, this.value, this.onChanged, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(8);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Brand.blue, width: 1.2)),
      child: Row(children: [
        for (var i = 0; i < options.length; i++)
          Expanded(
            child: Material(
              color: i == value ? Brand.blue : Colors.white,
              borderRadius: r,
              child: InkWell(
                borderRadius: r,
                onTap: () => onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    options[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: i == value ? Colors.white : Brand.ink),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Message box at the top of a form: a bold title and one line under it
/// (wireframe "Details wrong / Check your phone number and password").
/// Errors (the default) are red text with a red border on a light red fill.
/// [info] is for notices that are not errors (blue box with white text).
class MsgBanner extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? action;
  final bool info;
  const MsgBanner(this.title, {super.key, this.sub, this.action, this.info = false});

  @override
  Widget build(BuildContext context) {
    final text = info ? Colors.white : Brand.red;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: info ? Brand.blue : Brand.redLight,
          borderRadius: BorderRadius.circular(10),
          border: info ? null : Border.all(color: Brand.red, width: 1.4),
        ),
        child: Row(children: [
          if (!info) ...[const Icon(Icons.error_outline, color: Brand.red, size: 22), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: text, fontWeight: FontWeight.w800)),
              if (sub != null && sub!.isNotEmpty) Text(sub!, style: TextStyle(color: text, fontSize: 12.5)),
            ]),
          ),
          if (action != null) action!,
        ]),
      ),
    );
  }
}

/// Red border and light red fill around a field the server says is missing or wrong.
class ErrorWrap extends StatelessWidget {
  final bool on;
  final Widget child;
  const ErrorWrap(this.on, this.child, {super.key});

  @override
  Widget build(BuildContext context) => on
      ? Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          decoration: BoxDecoration(
            color: Brand.redLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Brand.red, width: 1.4),
          ),
          child: child,
        )
      : child;
}

/// Light note box (e.g. "Orders kept on this phone only").
class Note extends StatelessWidget {
  final String text;
  const Note(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Brand.light, borderRadius: BorderRadius.circular(10), border: Border.all(color: Brand.blue)),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

/// Grey centered text for empty lists.
class Empty extends StatelessWidget {
  final String text;
  const Empty(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted))),
      );
}

/// Key: value row inside a card.
class KV extends StatelessWidget {
  final String k;
  final String v;
  final bool last;
  final VoidCallback? onTap;
  const KV(this.k, this.v, {super.key, this.last = false, this.onTap});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Brand.soft))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(color: Brand.muted)),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(
                v,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: onTap != null ? Brand.blue : Brand.ink,
                  decoration: onTap != null ? TextDecoration.underline : null,
                  decorationColor: Brand.blue,
                ),
              ),
            ),
          ),
        ]),
      );
}

/// Row with a chevron (menus, lists).
class RowLink extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final IconData? icon;
  const RowLink(this.title, {super.key, this.sub, this.trailing, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Box(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, color: Brand.blue), const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub!, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                  ),
              ]),
            ),
            if (trailing != null) trailing!,
            if (onTap != null) const Icon(Icons.chevron_right, color: Brand.blue),
          ]),
        ),
      );
}

/// Round count (Needs Your Action, bell).
class CountBadge extends StatelessWidget {
  final int n;
  const CountBadge(this.n, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 26),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: n > 0 ? Brand.blue : Brand.light, borderRadius: BorderRadius.circular(20)),
        child: Text('$n',
            textAlign: TextAlign.center,
            style: TextStyle(color: n > 0 ? Colors.white : Brand.muted, fontWeight: FontWeight.w800, fontSize: 12.5)),
      );
}

/// Page body with the standard padding.
class Body extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const Body(this.children, {super.key, this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24)});

  @override
  Widget build(BuildContext context) => ListView(padding: padding, children: children);
}

/// Bottom area with buttons that stays above the keyboard.
class Bottom extends StatelessWidget {
  final List<Widget> children;
  const Bottom(this.children, {super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Brand.soft))),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}

/// Bottom sheet with a title (forms and popups).
Future<T?> sheet<T>(
  BuildContext context,
  String title,
  Widget Function(BuildContext, StateSetter) build, {
  String? sub,
  bool close = true,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.88),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title.isNotEmpty || close)
                Row(children: [
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                  if (close) IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
                ]),
              if (sub != null) Text(sub, style: const TextStyle(color: Brand.muted)),
              const SizedBox(height: 14),
              build(c, set),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// Yes / no popup. Returns true when the first button is tapped.
Future<bool> confirm(
  BuildContext context,
  String title, {
  String? sub,
  String ok = 'Confirm',
  String cancel = 'Cancel',
  Widget? extra,
}) async {
  final r = await sheet<bool>(
    context,
    title,
    sub: sub,
    close: false,
    (c, set) => Column(children: [
      if (extra != null) extra,
      const SizedBox(height: 22),
      Btn(ok, () => Navigator.pop(c, true)),
      const Gap(),
      Btn(cancel, () => Navigator.pop(c, false), outline: true),
    ]),
  );
  return r == true;
}

/// Pick one option from a list (reasons, views, riders).
Future<String?> choose(BuildContext context, String title, List<String> options, {String? current, String ok = 'Confirm'}) {
  var sel = current ?? '';
  return sheet<String>(context, title, (c, set) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Box(
            tint: sel == o,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () => set(() => sel = o),
            child: Row(children: [
              Icon(sel == o ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Brand.blue),
              const SizedBox(width: 10),
              Expanded(child: Text(o, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      const SizedBox(height: 10),
      Btn(ok, sel.isEmpty ? null : () => Navigator.pop(c, sel)),
    ]);
  });
}

/// The station logo.
class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 170});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'Mangao Water Refilling Station logo',
      );
}

/// Stand-in for a screen built in a later step of the tracker.
class ComingSoonCard extends StatelessWidget {
  final int step;
  final String what;
  const ComingSoonCard({super.key, required this.step, required this.what});

  @override
  Widget build(BuildContext context) => Box(
        tint: true,
        child: Row(children: [
          const Icon(Icons.construction_outlined, color: Brand.blue),
          const Gap(12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Coming in step $step', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(what, style: const TextStyle(color: Brand.muted, fontSize: 13)),
            ]),
          ),
        ]),
      );
}

/// Small outlined button inside a card header (Edit, Edit prices, Change).
class SmallBtn extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const SmallBtn(this.text, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(text),
      );
}

/// Bottom-sheet form (Edit form, Password form, Price form...): fields, a message box for
/// errors from the server, and a Save button. [onSave] returns the message shown after saving.
/// Returns true when saved.
Future<bool> formSheet(
  BuildContext context,
  String title, {
  required List<Widget> Function(StateSetter set) fields,
  required Future<String?> Function() onSave,
  String button = 'Save',
}) async {
  ApiException? err;
  var busy = false;
  String? done;
  final saved = await sheet<bool>(context, title, (c, set) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (err != null) MsgBanner(err!.title, sub: err!.message),
      ...fields(set),
      const SizedBox(height: 8),
      Btn(button, () async {
        FocusScope.of(c).unfocus();
        set(() {
          busy = true;
          err = null;
        });
        try {
          done = await onSave();
          if (c.mounted) Navigator.pop(c, true);
        } on ApiException catch (e) {
          if (c.mounted) {
            set(() {
              err = e;
              busy = false;
            });
          }
        }
      }, busy: busy),
    ]);
  });
  if (saved == true && done != null && context.mounted) toast(context, done!);
  return saved == true;
}

/// Shows a list or page that loads from the server: spinner, message with Try again, or the content.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  const Loader({super.key, required this.load, required this.builder});

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  T? _data;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return Body([
        MsgBanner(_error?.title ?? 'Something went wrong', sub: _error?.message),
        Btn('Try again', () {
          setState(() => _loading = true);
          reload();
        }, outline: true),
      ]);
    }
    return RefreshIndicator(onRefresh: reload, child: widget.builder(context, _data as T, reload));
  }
}

/// Quantity box with - and + (Log Walk-in, Log Delivery Order). 0 shows as empty ("Quantity missing").
class QtyStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int max;
  final bool highlight;
  const QtyStepper(this.value, this.onChanged, {super.key, this.max = 100, this.highlight = false});

  Widget _btn(IconData icon, VoidCallback? onTap, {bool filled = false}) => SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: filled ? Brand.blue : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Brand.blue, width: 1.2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Icon(icon, color: filled ? Colors.white : Brand.blue, size: 20),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: highlight ? Brand.redLight : Colors.white,
          border: Border.all(color: highlight ? Brand.red : Brand.blue, width: highlight ? 2 : 1.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          _btn(Icons.remove, value > 0 ? () => onChanged(value - 1) : null),
          Expanded(
            child: Text(value == 0 ? '' : '$value',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          _btn(Icons.add, value < max ? () => onChanged(value + 1) : null, filled: true),
        ]),
      );
}

/// Total box under a form: "Total  2 x P30.00 per gallon (walk-in)   P60.00".
class TotalBox extends StatelessWidget {
  final String detail;
  final String amount;
  const TotalBox(this.detail, this.amount, {super.key});

  @override
  Widget build(BuildContext context) => Box(
        tint: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
              Text(detail, style: const TextStyle(color: Brand.muted, fontSize: 12)),
            ]),
          ),
          Text(amount, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
        ]),
      );
}
