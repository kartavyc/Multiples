# MULTIPLES — Audio Manifest (assets + trigger map)

> 18 original chiptune assets in `app/assets/audio/*.ogg` (synthesized procedurally, ~673 KB total,
> no licensing). Vibe: chiptune instrumentation arranged with a "Dream Manhunt" build — driving
> minor-key urgency that pays off triumphant on the big moments. Mono OGG q3, seamless-loop BGM.
> Wired by the audio round via `audioplayers`. Respects the settings mute/volume toggles.

## BGM (looping, per screen mood — crossfade ~400ms on screen change)
| file | screen / mood | bpm/key |
|------|---------------|---------|
| `bgm_title.ogg` | S0 Title + S9 Desk — moody, driving, inviting | 96 / Em |
| `bgm_act.ogg` | S3 ACT + S2 digest + S5 shop — calm driving gameplay loop (the main track) | 112 / Am |
| `bgm_tension.ogg` | S7 deadline panel when BEHIND pace / final round — fast, building alarm | 132 / Am |
| `bgm_autopsy.ogg` | S8 Autopsy — somber dirge, no payoff | 70 / Am |
| `bgm_victory.ogg` | S10 Victory — triumphant fanfare loop | 120 / C |

Rule: BGM ducks to ~40% volume for ~700ms under the arbitrage flash, tier-clear, and bankruptcy stingers so the SFX lands.

## SFX (one-shots, hooked to engine GameEvents / UI taps)
| file | trigger |
|------|---------|
| `sfx_key.ogg` | any chunky-key press (END TURN, ADVANCE, CONTINUE, NEW RUN, etc.) — mechanical thunk |
| `sfx_select.ogg` | ticket / card / venture tap-select |
| `sfx_ticket.ogg` | new hand dealt (OPERATE → ACT) — shuffle |
| `sfx_napkin.ogg` | napkin overlay opens — dot-matrix chatter |
| `sfx_reroll.ogg` | REROLL (hand or shop) |
| `sfx_partner.ogg` | HirePartner committed |
| `sfx_raise.ogg` | RaiseEquity committed (downward dilution motif) |
| `sfx_nw_surge.ogg` | **the NET-WORTH SURGE** — rising arpeggio + cash-register bell (the signature) |
| `sfx_arbitrage.ogg` | **MULTIPLE_ARBITRAGE flash** — epic rising sweep + chord stab + sparkle |
| `sfx_exit_cash.ogg` | EXIT realized — paper→cash collapse (coin/sparkle) |
| `sfx_tier_clear.ogg` | TIER_CLEARED — triumphant fanfare stinger |
| `sfx_bankruptcy.ogg` | BANKRUPTCY death — descending drone + dial-tone cut (dread) |
| `sfx_error.ogg` | ACTION_REJECTED (insufficient cash / illegal) — buzzer |

## Wiring notes
- All game/meta logic stays in the engine; the AudioController is a pure UI-side listener that maps
  `GameEvent` types + screen/phase transitions to playback. No audio call computes anything economic.
- Settings (audio round): master mute, music on/off, sfx on/off, all persisted (meta/prefs). Default ON.
  Respect OS silent mode where the plugin exposes it.
- Source synth scripts live in the session outputs (`audio_src/{synth,bgm}.py`) — regenerate/tweak there,
  re-export OGG, drop into `app/assets/audio/`. Document any asset change here.
