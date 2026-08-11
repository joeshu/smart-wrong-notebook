import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';

/// Opens the single entry surface for every supported question-capture flow.
abstract final class CaptureEntryLauncher {
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const CaptureEntrySheet(),
      );
}
