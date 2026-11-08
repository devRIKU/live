/// Form — a short, validated form.
///
/// Values are validated against the field schema *before* the action runs, so
/// a malformed value never reaches a tool call or the next chat turn
/// (SPEC 7.2.5). Values are mirrored into the OpenUI form store, which is
/// what the runtime attaches to the action event as `formState`.
library;

import 'package:flutter/material.dart' hide Form;
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import '../../../core/theme/lively_tokens.dart';
import '../actions.dart';
import '../nodes.dart';
import '../runtime.dart';
import '../schema.dart';

class FormWidget extends StatefulWidget {
  const FormWidget({super.key, required this.node});

  final FormNode node;

  @override
  State<FormWidget> createState() => _FormWidgetState();
}

class _FormWidgetState extends State<FormWidget> {
  final Map<String, String> _values = <String, String>{};
  final Map<String, String?> _errors = <String, String?>{};
  bool _submitted = false;

  String get _formName =>
      widget.node.statementId ?? 'form${identityHashCode(widget)}';

  void _update(String name, String value) {
    setState(() {
      _values[name] = value;
      _errors[name] = null;
    });
    final runtime = OpenUIRuntimeScope.of(context);
    final field = widget.node.fields
        .where((f) => f.name == name)
        .cast<FormFieldData?>()
        .firstOrNull;
    if (field == null) return;
    final parsed = switch (field.type) {
      FieldType.checkbox => value == 'true',
      FieldType.number => double.tryParse(value),
      _ => value,
    };
    runtime.formStore.setFieldValue(_formName, name, parsed);
  }

  void _handleSubmit() {
    final fields =
        widget.node.fields.take(Limits.maxFormFields).toList(growable: false);
    final nextErrors = <String, String?>{};
    for (final field in fields) {
      final value = field.type == FieldType.checkbox
          ? (_values[field.name] == 'true' ? true : false)
          : _values[field.name];
      final message = validateFieldValue(field, value);
      if (message != null) nextErrors[field.name] = message;
    }
    setState(() => _errors.addAll(nextErrors));
    if (nextErrors.isNotEmpty) return;

    _submitted = true;
    setState(() {});
    final action = widget.node.action;
    if (action != null) {
      final runtime = OpenUIRuntimeScope.of(context);
      runtime.triggerAction(
        widget.node.submitLabel ?? 'Submit',
        _formName,
        action,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    final fields = widget.node.fields
        .take(Limits.maxFormFields)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(b),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.node.title != null)
            Text(
              widget.node.title!,
              style: TextStyle(
                color: Lively.textPrimary(b),
                fontSize: Lively.tFootnote,
                fontWeight: FontWeight.w600,
              ),
            ),
          for (final field in fields)
            _Field(
              field: field,
              value: _values[field.name],
              error: _errors[field.name],
              onChanged: (v) => _update(field.name, v),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Lively.s3),
            child: Row(
              children: [
                fluent.Button(
                  onPressed:
                      OpenUIRuntimeScope.of(context).isStreaming ? null : _handleSubmit,
                  style: fluent.ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.disabled)
                            ? Lively.fill(b, 2)
                            : Lively.accent(b)),
                    foregroundColor:
                        WidgetStateProperty.all(const Color(0xFFFFFFFF)),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(
                          horizontal: Lively.s3, vertical: Lively.s1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(fluent.FluentIcons.check_mark,
                          size: 12, color: const Color(0xFFFFFFFF)),
                      const SizedBox(width: Lively.s1),
                      Text(
                        widget.node.submitLabel ?? 'Submit',
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: Lively.tFootnote,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_submitted && widget.node.action == null) ...[
                  const SizedBox(width: Lively.s2),
                  Text(
                    'Saved',
                    style: TextStyle(
                        color: Lively.appleGreen, fontSize: Lively.tMicro),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Brightness _bOf(BuildContext context) => fluent.FluentTheme.of(context).brightness;
}

class _Field extends StatefulWidget {
  final FormFieldData field;
  final String? value;
  final String? error;
  final ValueChanged<String> onChanged;

  const _Field({
    required this.field,
    required this.value,
    required this.error,
    required this.onChanged,
  });

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  TextEditingController? _controller;

  TextEditingController get _ctrl {
    // The controller is owned by the widget; the incoming `value` only seeds
    // it once (the form's own state map is the source of truth afterwards).
    _controller ??= TextEditingController(text: widget.value ?? '');
    return _controller!;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = fluent.FluentTheme.of(context).brightness;

    Widget control;
    switch (widget.field.type) {
      case FieldType.select:
        control = DropdownButtonFormField<String>(
          value: widget.value,
          items: [
            const DropdownMenuItem(value: '', child: Text('Select…')),
            for (final option in widget.field.options ?? const <String>[])
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (v) => widget.onChanged(v ?? ''),
          style: TextStyle(
              color: Lively.textPrimary(b), fontSize: Lively.tFootnote),
          dropdownColor: Lively.surfaceRaised(b),
          decoration: _decoration(b),
        );
      case FieldType.checkbox:
        control = Row(
          children: [
            Checkbox(
              value: widget.value == 'true' ? true : false,
              onChanged: (v) => widget.onChanged(v == true ? 'true' : 'false'),
              side: BorderSide(color: Lively.separator(b), width: Lively.bThin),
            ),
            const SizedBox(width: Lively.s2),
            Expanded(
              child: Text(
                widget.field.placeholder ?? 'Yes',
                style: TextStyle(
                    color: Lively.textPrimary(b), fontSize: Lively.tFootnote),
              ),
            ),
          ],
        );
      case FieldType.textarea:
        control = TextField(
          controller: _ctrl,
          maxLines: 3,
          keyboardType: TextInputType.multiline,
          onChanged: widget.onChanged,
          style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote),
          cursorColor: Lively.accent(b),
          decoration:
              _decoration(b, hint: widget.field.placeholder),
        );
      case FieldType.number:
        control = TextField(
          controller: _ctrl,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          onChanged: widget.onChanged,
          style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote),
          cursorColor: Lively.accent(b),
          decoration:
              _decoration(b, hint: widget.field.placeholder),
        );
      case FieldType.text:
        control = TextField(
          controller: _ctrl,
          onChanged: widget.onChanged,
          style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote),
          cursorColor: Lively.accent(b),
          decoration:
              _decoration(b, hint: widget.field.placeholder),
        );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Lively.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: widget.field.label,
              style: TextStyle(
                  color: Lively.textPrimary(b), fontSize: Lively.tFootnote),
              children: [
                if (widget.field.required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Lively.appleRed),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Lively.s1),
          control,
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.error!,
                style: TextStyle(
                    color: Lively.appleRed, fontSize: Lively.tMicro),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _decoration(Brightness b, {String? hint}) => InputDecoration(
        filled: true,
        fillColor: Lively.fill(b, 1),
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
            color: Lively.textTertiary(b), fontSize: Lively.tFootnote),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Lively.rMd),
          borderSide: BorderSide.none,
        ),
      );
}
