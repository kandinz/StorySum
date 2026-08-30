import 'dart:async';
import 'package:flutter/material.dart';

/// Global Key cho Navigator & ScaffoldMessenger để có thể hiển thị Toast ở bất cứ đâu
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastType {
  success,
  error,
  warning,
  info,
}

class AppToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  /// Hiển thị Toast thông báo thành công (Màu xanh lá)
  static void showSuccess(
    BuildContext? context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    _show(
      context: context,
      message: message,
      title: title ?? 'Thành công',
      type: ToastType.success,
      duration: duration,
    );
  }

  /// Hiển thị Toast thông báo lỗi (Màu đỏ)
  static void showError(
    BuildContext? context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 4000),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context: context,
      message: message,
      title: title ?? 'Lỗi',
      type: ToastType.error,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Hiển thị Toast cảnh báo (Màu cam/vàng)
  static void showWarning(
    BuildContext? context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    _show(
      context: context,
      message: message,
      title: title ?? 'Cảnh báo',
      type: ToastType.warning,
      duration: duration,
    );
  }

  /// Hiển thị Toast thông tin (Màu xanh lam)
  static void showInfo(
    BuildContext? context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    _show(
      context: context,
      message: message,
      title: title ?? 'Thông tin',
      type: ToastType.info,
      duration: duration,
    );
  }

  static void _show({
    required BuildContext? context,
    required String message,
    required String title,
    required ToastType type,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // Tìm OverlayState thích hợp
    OverlayState? overlayState;
    if (context != null && context.mounted) {
      overlayState = Overlay.maybeOf(context);
    }
    overlayState ??= rootNavigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    // Hủy toast hiện tại nếu đang hiển thị
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    final GlobalKey<_TopToastWidgetState> toastKey = GlobalKey<_TopToastWidgetState>();

    entry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          top: MediaQuery.of(ctx).padding.top + 10,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: _TopToastWidget(
              key: toastKey,
              title: title,
              message: message,
              type: type,
              actionLabel: actionLabel,
              onAction: onAction,
              onDismiss: () {
                if (_currentEntry == entry) {
                  _currentEntry?.remove();
                  _currentEntry = null;
                }
              },
            ),
          ),
        );
      },
    );

    _currentEntry = entry;
    overlayState.insert(entry);

    _dismissTimer = Timer(duration, () {
      toastKey.currentState?.dismiss();
    });
  }
}

class _TopToastWidget extends StatefulWidget {
  final String title;
  final String message;
  final ToastType type;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    Key? key,
    required this.title,
    required this.message,
    required this.type,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 250),
    );

    // Animation chạy từ phải qua trái (Offset(1.0, 0.0) -> Offset.zero)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.05, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _controller.forward();
  }

  Future<void> dismiss() async {
    if (mounted) {
      await _controller.reverse();
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color accentColor;

    switch (widget.type) {
      case ToastType.success:
        accentColor = const Color(0xFF10B981); // Emerald Green
        break;
      case ToastType.error:
        accentColor = const Color(0xFFEF4444); // Crimson Red
        break;
      case ToastType.warning:
        accentColor = const Color(0xFFF59E0B); // Amber Orange
        break;
      case ToastType.info:
        accentColor = const Color(0xFF3B82F6); // Blue
        break;
    }

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dismissible(
          key: UniqueKey(),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => widget.onDismiss(),
          child: GestureDetector(
            onTap: dismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B), // Slate 800 cao cấp
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.title.isNotEmpty)
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        if (widget.title.isNotEmpty) const SizedBox(height: 2),
                        Text(
                          widget.message,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFF8FAFC), // Slate 50
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.actionLabel != null && widget.onAction != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        dismiss();
                        widget.onAction?.call();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        widget.actionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
