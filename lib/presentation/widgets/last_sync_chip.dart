import 'package:flutter/material.dart';

class LastSyncChip extends StatelessWidget {
  final DateTime? time;
  const LastSyncChip({super.key, this.time});

  @override
  Widget build(BuildContext context) {
    final label = (time == null)
        ? 'Nunca'
        : '${time!.year}-${time!.month.toString().padLeft(2,'0')}-${time!.day.toString().padLeft(2,'0')} '
        '${time!.hour.toString().padLeft(2,'0')}:${time!.minute.toString().padLeft(2,'0')}';
    return Chip(
      avatar: const Icon(Icons.sync, size: 18),
      label: Text('Última sync: $label'),
    );
  }
}
