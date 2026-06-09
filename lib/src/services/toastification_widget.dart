import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

ToastificationItem? _currentToast;

void showToastificationWidget({
  required String message,
  required BuildContext context,
  ToastificationType notificationType = ToastificationType.error,
  int duration = 3,
}) {
  if (_currentToast != null) {
    toastification.dismiss(_currentToast!);
  }
  toastification.dismissAll(delayForAnimation: false);
  _currentToast = toastification.show(
    context: context,
    title: Text(
      textAlign: TextAlign.center,
      message,
      maxLines: 3,
    ),
    type: notificationType,
    style: ToastificationStyle.flat,
    alignment: Alignment.topCenter,
    direction: TextDirection.rtl,
    autoCloseDuration: Duration(seconds: duration),
  );
}
