/// S-SETTINGS — the R20 settings panel (terminal skin, docs/07). Toggles for
/// MUSIC / SOUND FX / MASTER MUTE (drive the R18 AudioController setters,
/// persisted), HAPTICS (gates the device vibration, persisted), a REPLAY
/// TUTORIAL key (clears the seen flag), a danger WIPE SAVE (confirm), and a
/// credits/version footer. Reachable from the TITLE (gear) and THE DESK.
///
/// PURE UI/PREFS: nothing economic. The audio toggles call
/// [AudioController]'s setters (which persist via the audio settings store);
/// HAPTICS + REPLAY drive the [AppSettingsController]. Changes apply LIVE
/// (the controllers are ChangeNotifiers this screen listens to) and persist
/// across launches. WIPE SAVE is handed up as a callback (the shell owns the
/// SaveStore).
library;

import 'package:flutter/material.dart';

import '../audio.dart';
import '../settings.dart';
import '../theme.dart';

/// The settings screen. [audio] drives the three sound toggles; [settings]
/// drives haptics + replay-tutorial; [onWipeSave] (when non-null) wipes the
/// on-device save after a confirm; [onBack] returns to the caller.
class SettingsScreen extends StatefulWidget {
  /// Builds the settings screen.
  const SettingsScreen({
    super.key,
    required this.audio,
    required this.settings,
    required this.onBack,
    this.onWipeSave,
    this.versionLabel = 'MULTIPLES MK·I · v1.0.0',
  });

  /// The R18 audio controller (its setters persist the sound flags).
  final AudioController audio;

  /// The app preference controller (haptics + tutorial-seen).
  final AppSettingsController settings;

  /// BACK key handler.
  final VoidCallback onBack;

  /// WIPE SAVE handler (after the in-screen confirm); null hides the row.
  final Future<void> Function()? onWipeSave;

  /// The footer build line.
  final String versionLabel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirmWipe = false;
  bool _wiped = false;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  AudioSettings get _a => widget.audio.settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBezel,
      body: SafeArea(
        child: Column(
          children: [
            // Bezel nameplate strip (matches the title/run frame).
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF2A2E33), Color(0xFF17191C)],
                  ),
                  border: Border.all(color: kBezel),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('SETTINGS',
                    style: labelStyle(
                        color: const Color(0xFF9AA4AD), tracking: 3)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: kBg,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          children: [
                            _sectionHead('AUDIO'),
                            _ToggleRow(
                              rowKey: const Key('toggleMaster'),
                              label: 'MASTER MUTE',
                              hint: 'silence everything',
                              value: _a.masterMuted,
                              onChanged: (v) =>
                                  widget.audio.setMasterMuted(v).then(_rebuild),
                            ),
                            _ToggleRow(
                              rowKey: const Key('toggleMusic'),
                              label: 'MUSIC',
                              hint: 'the loop',
                              value: _a.musicOn,
                              enabled: !_a.masterMuted,
                              onChanged: (v) =>
                                  widget.audio.setMusicOn(v).then(_rebuild),
                            ),
                            _ToggleRow(
                              rowKey: const Key('toggleSfx'),
                              label: 'SOUND FX',
                              hint: 'keys, stingers, the surge',
                              value: _a.sfxOn,
                              enabled: !_a.masterMuted,
                              onChanged: (v) =>
                                  widget.audio.setSfxOn(v).then(_rebuild),
                            ),
                            const SizedBox(height: 16),
                            _sectionHead('FEEL'),
                            _ToggleRow(
                              rowKey: const Key('toggleHaptics'),
                              label: 'HAPTICS',
                              hint: 'buzz on the big beats',
                              value: widget.settings.hapticsOn,
                              onChanged: (v) =>
                                  widget.settings.setHapticsOn(v),
                            ),
                            const SizedBox(height: 16),
                            _sectionHead('TUTORIAL'),
                            _ActionRow(
                              rowKey: const Key('replayTutorial'),
                              label: 'REPLAY TUTORIAL',
                              hint: widget.settings.tutorialSeen
                                  ? 'show it on the next NEW RUN'
                                  : 'armed — fires next NEW RUN',
                              keyLabel: 'REPLAY',
                              variant: ChunkyKeyVariant.normal,
                              onTap: () => widget.settings.replayTutorial(),
                            ),
                            const SizedBox(height: 16),
                            if (widget.onWipeSave != null) ...[
                              _sectionHead('DANGER'),
                              _buildWipe(),
                              const SizedBox(height: 16),
                            ],
                            _sectionHead('ABOUT'),
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 2),
                              child: Text(widget.versionLabel,
                                  key: const Key('versionLine'),
                                  style: bodyStyle(size: 11, color: kDim)),
                            ),
                            Text('NO ACCOUNT · OFFLINE · SAVED ON DEVICE',
                                style: labelStyle(
                                    size: 8, color: kFaint, tracking: 1.5)),
                            const SizedBox(height: 16),
                            ChunkyKey(
                              key: const Key('settingsBack'),
                              icon: '◂',
                              label: 'BACK',
                              variant: ChunkyKeyVariant.primary,
                              onTap: widget.onBack,
                            ),
                          ],
                        ),
                        const CrtOverlay(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _rebuild([void _]) {
    if (mounted) setState(() {});
  }

  Widget _buildWipe() {
    if (_wiped) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('SAVE WIPED.',
            key: const Key('wipeDone'),
            style: bodyStyle(size: 12, color: kLoss)),
      );
    }
    if (!_confirmWipe) {
      return _ActionRow(
        rowKey: const Key('wipeSave'),
        label: 'WIPE SAVE',
        hint: 'erase run + track record',
        keyLabel: 'WIPE',
        variant: ChunkyKeyVariant.normal,
        danger: true,
        onTap: () => setState(() => _confirmWipe = true),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        border: Border.all(color: kLoss, width: 2),
        borderRadius: BorderRadius.circular(4),
        color: const Color(0x14FF5566),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ERASE EVERYTHING?',
              style: labelStyle(size: 10, color: kLoss, tracking: 1.5)),
          const SizedBox(height: 4),
          Text('No undo. The run, the rep, all of it. Gone.',
              style: bodyStyle(size: 11, color: kDim)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChunkyKey(
                  key: const Key('wipeCancel'),
                  label: 'KEEP IT',
                  onTap: () => setState(() => _confirmWipe = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyKey(
                  key: const Key('wipeConfirm'),
                  label: 'WIPE FOR GOOD',
                  variant: ChunkyKeyVariant.exec,
                  onTap: _doWipe,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _doWipe() async {
    final wipe = widget.onWipeSave;
    if (wipe == null) return;
    await wipe();
    if (!mounted) return;
    setState(() {
      _confirmWipe = false;
      _wiped = true;
    });
  }

  Widget _sectionHead(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.only(bottom: 4),
          decoration:
              const BoxDecoration(border: Border(bottom: BorderSide(color: kLine))),
          child: Text(text,
              style: labelStyle(size: 9, color: kDim, tracking: 2)),
        ),
      );
}

/// A label + hint + chunky ON/OFF pill. Tapping the pill flips the value.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.rowKey,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final Key rowKey;
  final String label;
  final String hint;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final on = value && enabled;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: bodyStyle(
                        size: 13, color: enabled ? kFg : kFaint)),
                const SizedBox(height: 2),
                Text(hint, style: labelStyle(size: 8, color: kFaint)),
              ],
            ),
          ),
          GestureDetector(
            key: rowKey,
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => onChanged(!value) : null,
            child: Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: on ? const Color(0x1A4DFF8A) : kPanel,
                border: Border.all(color: on ? kGain : kFaint, width: 2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: Text(
                  on ? 'ON' : 'OFF',
                  style: labelStyle(
                    size: 10,
                    color: on ? kGain : kDim,
                    tracking: 1.5,
                  ).copyWith(shadows: on ? kGlowGain : const []),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label + hint + a single chunky action key (REPLAY / WIPE).
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.rowKey,
    required this.label,
    required this.hint,
    required this.keyLabel,
    required this.onTap,
    this.variant = ChunkyKeyVariant.normal,
    this.danger = false,
  });

  final Key rowKey;
  final String label;
  final String hint;
  final String keyLabel;
  final VoidCallback onTap;
  final ChunkyKeyVariant variant;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: bodyStyle(
                        size: 13, color: danger ? kLoss : kFg)),
                const SizedBox(height: 2),
                Text(hint, style: labelStyle(size: 8, color: kFaint)),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: ChunkyKey(
              key: rowKey,
              label: keyLabel,
              variant: variant,
              dense: true,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}
