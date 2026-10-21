import 'package:flutter/material.dart';

import '../controller.dart';
import '../core/format.dart';
import '../core/whitelist.dart';

class WhitelistPage extends StatelessWidget {
  const WhitelistPage({super.key, required this.controller});

  final NearbyController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entries = controller.whitelist.entries.reversed.toList();
        final inRange = {for (final device in controller.devices) device.address: device};
        return Scaffold(
          appBar: AppBar(title: Text('Whitelist · ${entries.length}')),
          body: entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nothing whitelisted yet. Press Learn on the main screen, '
                      'or tick devices in the list.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final device = inRange[entry.address];
                    final name = deviceLabel(
                      label: entry.label,
                      name: device?.name ?? entry.name,
                      manufacturer: device?.manufacturer,
                    );
                    return ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: device == null
                            ? Theme.of(context).colorScheme.outlineVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        [
                          entry.address,
                          if (device != null) 'in range, ≈ ${formatDistance(device.distance)}' else 'not in range',
                          'added ${_date(entry.added)}',
                        ].join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _rename(context, entry, name),
                          ),
                          IconButton(
                            tooltip: 'Remove from whitelist',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => controller.setWhitelisted(entry.address, false),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _rename(BuildContext context, WhitelistEntry entry, String current) async {
    final label = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: entry.label ?? '', hint: current),
    );
    if (label != null) controller.renameWhitelisted(entry.address, label);
  }
}

/// Owns its text controller, so the field can still use it while the dialog animates closed.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial, required this.hint});

  final String initial;
  final String hint;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: _field,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint, helperText: 'Leave empty to use the advertised name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_field.text), child: const Text('Save')),
      ],
    );
  }
}

String _date(DateTime at) {
  final local = at.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
