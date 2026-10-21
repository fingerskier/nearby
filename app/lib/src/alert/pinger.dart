import 'dart:io';

typedef RunProcess = Future<ProcessResult> Function(String executable, List<String> arguments);

abstract interface class Pinger {
  /// Plays the alert sound; false if no player worked.
  Future<bool> ping();
}

/// Plays a freedesktop theme sound with whichever player the system has.
class SoundPinger implements Pinger {
  SoundPinger({RunProcess? run, this.sound = defaultSound}) : _run = run ?? Process.run;

  static const defaultSound = '/usr/share/sounds/freedesktop/stereo/device-added.oga';

  final RunProcess _run;
  final String sound;
  int? _working;

  /// PipeWire, then PulseAudio, then libcanberra, which finds the sound by its theme name.
  late final _players = [
    ['pw-play', sound],
    ['paplay', sound],
    ['canberra-gtk-play', '-i', 'device-added'],
  ];

  @override
  Future<bool> ping() async {
    final working = _working;
    final order = [
      ?working,
      for (var i = 0; i < _players.length; i++)
        if (i != working) i,
    ];
    for (final index in order) {
      final [executable, ...arguments] = _players[index];
      try {
        final result = await _run(executable, arguments);
        if (result.exitCode == 0) {
          _working = index;
          return true;
        }
      } on ProcessException {
        // Not installed; try the next player.
      }
    }
    _working = null;
    return false;
  }
}
