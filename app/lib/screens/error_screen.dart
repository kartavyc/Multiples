/// Boot ERROR screen (audit L5): when the content asset fails to load/parse
/// at startup, main() mounts this instead of a blank crash. Terminal-styled
/// (docs/07): a red CRT panel with the cause, no juice. There is nothing to
/// retry on-device (the asset is bundled), so it states the fault plainly.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A standalone MaterialApp wrapping [ErrorScreen] — main() runs this when the
/// content load throws (no GameController could be built).
class BootErrorApp extends StatelessWidget {
  /// Builds the error app with the failure [message].
  const BootErrorApp({super.key, required this.message});

  /// The caught error's string form.
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MULTIPLES',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBezel,
          fontFamily: kFontBody,
        ),
        home: ErrorScreen(message: message),
      );
}

/// The terminal ERROR panel.
class ErrorScreen extends StatelessWidget {
  /// Builds the panel with the failure [message].
  const ErrorScreen({super.key, required this.message});

  /// The caught error's string form (shown verbatim, monospace).
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBezel,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: kBg,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    key: const Key('bootError'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'SYSTEM FAULT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: kFontLabel,
                          fontSize: 16,
                          letterSpacing: 6,
                          color: kLoss,
                          shadows: kGlowLoss,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'The machine could not load its content.',
                        textAlign: TextAlign.center,
                        style: bodyStyle(size: 13, color: kDim),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                        decoration: BoxDecoration(
                          color: kPanel,
                          border: Border.all(color: kLoss),
                        ),
                        child: Text(
                          message,
                          style: bodyStyle(size: 11, color: kLoss),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'REINSTALL TO RESTORE THE DEAL DECK',
                        textAlign: TextAlign.center,
                        style: labelStyle(size: 8, color: kFaint, tracking: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
