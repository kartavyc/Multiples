/// The inline engine-rejection line: maps apply()'s snake_case reason keys
/// to terminal copy. Rendered under the blotter, in the napkin, and in the
/// shop. Copy only — the reasons themselves come off ACTION_REJECTED
/// events; nothing here decides anything.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// One red rejection line for an engine [reason] key.
class RejectionLine extends StatelessWidget {
  /// Builds the line.
  const RejectionLine({super.key, required this.reason});

  /// The engine's snake_case rejection reason.
  final String reason;

  static String _text(String reason) {
    switch (reason) {
      case 'insufficient_cash':
        return 'NOT ENOUGH CASH';
      case 'no_plays_remaining':
        return 'NO PLAYS LEFT';
      case 'slots_full':
        return 'SLOTS FULL';
      case 'venture_not_found':
        return 'NO TARGET VENTURE';
      case 'plays_full':
        return 'HELD PLAYS FULL';
      case 'offer_not_buyable':
        return 'FINANCING EXERCISES IN ACT';
      case 'raise_blocked_negative_equity':
        return 'EQUITY UNDERWATER';
      case 'wrong_phase':
        return 'WRONG PHASE';
      default:
        return reason.replaceAll('_', ' ').toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        '! ${_text(reason)}',
        key: const Key('rejection'),
        textAlign: TextAlign.center,
        style: labelStyle(size: 9, color: kLoss, tracking: 1)
            .copyWith(shadows: kGlowLoss),
      ),
    );
  }
}
