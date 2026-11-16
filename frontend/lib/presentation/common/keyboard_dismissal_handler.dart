import 'package:flutter/material.dart';

class KeyboardDismissalHandler extends StatefulWidget {
  const KeyboardDismissalHandler({required this.child, super.key});

  final Widget child;

  @override
  State<KeyboardDismissalHandler> createState() =>
      _KeyboardDismissalHandlerState();
}

class _KeyboardDismissalHandlerState extends State<KeyboardDismissalHandler>
    with WidgetsBindingObserver {
  bool _hasKeyboardVisibility = false;
  bool _keyboardVisible = false;
  int _keyboardChangeGeneration = 0;
  DateTime? _lastTextInputTapAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateKeyboardVisibility(
        MediaQuery.viewInsetsOf(context).bottom > 0,
      );
    });
  }

  void _updateKeyboardVisibility(bool keyboardVisible) {
    final wasKeyboardVisible = _keyboardVisible;
    _keyboardVisible = keyboardVisible;
    _hasKeyboardVisibility = true;
    final generation = ++_keyboardChangeGeneration;
    if (!wasKeyboardVisible || keyboardVisible) return;

    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || generation != _keyboardChangeGeneration) return;
      if (MediaQuery.viewInsetsOf(context).bottom > 0) return;

      final lastTextInputTap = _lastTextInputTapAt;
      if (lastTextInputTap != null &&
          DateTime.now().difference(lastTextInputTap) <
              const Duration(milliseconds: 900)) {
        return;
      }

      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (!_hasKeyboardVisibility || _keyboardVisible != keyboardVisible) {
      _updateKeyboardVisibility(keyboardVisible);
    }
  }

  bool _isTapOnTextInput(Offset position) {
    for (final focusNode in FocusManager.instance.rootScope.descendants) {
      final nodeContext = focusNode.context;
      if (nodeContext == null || !nodeContext.mounted) continue;

      var isTextInput = false;
      nodeContext.visitAncestorElements((element) {
        if (element.widget is EditableText) {
          isTextInput = true;
          return false;
        }
        return true;
      });
      if (!isTextInput) continue;

      final renderObject = nodeContext.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        continue;
      }

      final localPosition = renderObject.globalToLocal(position);
      if (renderObject.paintBounds.contains(localPosition)) return true;
    }
    return false;
  }

  bool _isTapOnTextSelectionToolbar(Offset position) {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) return false;

    var tappedToolbar = false;
    void visit(Element element) {
      if (tappedToolbar) return;

      final widget = element.widget;
      if (widget is AdaptiveTextSelectionToolbar ||
          widget is TextSelectionToolbar ||
          widget is DesktopTextSelectionToolbar) {
        final renderObject = element.findRenderObject();
        if (renderObject is RenderBox &&
            renderObject.attached &&
            renderObject.hasSize &&
            MatrixUtils.transformRect(
              renderObject.getTransformTo(null),
              renderObject.paintBounds,
            ).contains(position)) {
          tappedToolbar = true;
          return;
        }
      }

      element.visitChildElements(visit);
    }

    visit(rootElement);
    return tappedToolbar;
  }

  void _handlePointerDown(PointerDownEvent event) {
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null || !focusNode.hasFocus) return;
    if (_isTapOnTextInput(event.position)) {
      _lastTextInputTapAt = DateTime.now();
      return;
    }
    if (_isTapOnTextSelectionToolbar(event.position)) {
      _lastTextInputTapAt = DateTime.now();
      return;
    }
    focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      child: widget.child,
    );
  }
}
