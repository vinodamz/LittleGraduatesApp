import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/module_registry.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'materials_api.dart';
import 'materials_controller_web.dart';

class MaterialsScreen extends StatelessWidget {
  const MaterialsScreen({super.key});

  Future<void> _action(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException
                  ? e.message
                  : 'Could not save this change. Try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _attach(
    BuildContext context,
    MaterialItem item,
    bool video,
  ) async {
    final controller = context.read<MaterialsController>();
    await _action(context, () async {
      final picker = ImagePicker();
      final file = video
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await controller.addMedia(
        item,
        await file.readAsBytes(),
        file.name,
        video,
      );
    });
  }

  Future<void> _notes(BuildContext context, MaterialItem item) async {
    final controller = context.read<MaterialsController>();
    final text = TextEditingController(text: controller.notesFor(item));
    final notes = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Notes · ${item.name}'),
        content: TextField(
          controller: text,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Condition notes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, text.text),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    // Dispose after dialog transition so the departing field can still animate.
    Future<void>.delayed(const Duration(seconds: 1), text.dispose);
    if (notes != null && context.mounted) {
      await _action(
        context,
        () => controller.setCondition(
          item.id,
          controller.conditionFor(item)!,
          notes,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MaterialsController>();
    final day = controller.day;
    final shelves = <String, List<MaterialItem>>{};
    for (final item in controller.visible) {
      shelves.putIfAbsent(item.location, () => []).add(item);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Materials'),
        actions: [
          if (day != null)
            PopupMenuButton<String>(
              tooltip: 'Materials tools',
              onSelected: (value) {
                final entries = {
                  'Audit history': day.links.history,
                  'Trends': day.links.trends,
                  'Monthly board': day.links.monthly,
                  'My duties': day.links.duties,
                  'Assign someone': day.links.assign,
                };
                openWebUrl(context, entries[value]!, value);
              },
              itemBuilder: (_) => [
                if (day.canMonthly) ...[
                  const PopupMenuItem(
                    value: 'Audit history',
                    child: Text('Audit history'),
                  ),
                  const PopupMenuItem(value: 'Trends', child: Text('Trends')),
                  const PopupMenuItem(
                    value: 'Monthly board',
                    child: Text('Monthly board'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'My duties',
                  child: Text('My duties'),
                ),
                if (day.isAdmin)
                  const PopupMenuItem(
                    value: 'Assign someone',
                    child: Text('Assign someone'),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'Refresh and retry saved checks',
            onPressed: controller.busy ? null : controller.kick,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.kick,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Daily shelf check',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Changes save in this browser and retry while this tab is open.',
              style: TextStyle(color: LgColors.muted),
            ),
            const SizedBox(height: 16),
            if (controller.error != null) ...[
              LgNotice(
                message: controller.error!,
                foreground: LgColors.warn,
                background: LgColors.warnBg,
                icon: Icons.wifi_off,
              ),
              const SizedBox(height: 12),
            ],
            if (controller.pendingCount > 0) ...[
              LgNotice(
                message:
                    '${controller.pendingCount} saved changes waiting to upload. Keep this tab open to sync.',
                foreground: LgColors.info,
                background: LgColors.infoBg,
                icon: Icons.cloud_upload_outlined,
              ),
              if (controller.failedCount > 0)
                TextButton(
                  onPressed: controller.busy ? null : controller.kick,
                  child: const Text('Retry uploads'),
                ),
              const SizedBox(height: 12),
            ],
            if (controller.loading) const LinearProgressIndicator(),
            if (day != null) ...[
              Text(
                '${day.summary.checked} of ${day.summary.total} synced checks · ${day.dateLabel}',
                style: const TextStyle(color: LgColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: controller.setQuery,
                decoration: const InputDecoration(
                  labelText: 'Search materials',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: controller.location,
                decoration: const InputDecoration(labelText: 'Shelf'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All shelves')),
                  for (final shelf in day.locations.where((s) => s.isNotEmpty))
                    DropdownMenuItem(value: shelf, child: Text(shelf)),
                ],
                onChanged: (value) => controller.setLocation(value ?? ''),
              ),
              const SizedBox(height: 16),
              if (shelves.isEmpty)
                const LgEmptyState(
                  icon: Icons.search_off,
                  title: 'No materials match',
                  message: 'Try another name or shelf.',
                ),
              for (final shelf in shelves.entries) ...[
                LgSectionTitle(
                  shelf.key.isEmpty ? 'Unassigned shelf' : shelf.key,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text(
                                  'Mark remaining materials good?',
                                ),
                                content: Text(
                                  'Only unchecked materials on ${shelf.key.isEmpty ? 'this shelf' : shelf.key} will be marked.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Mark good'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              await _action(
                                context,
                                () => controller.markRestGood(shelf.key),
                              );
                            }
                          },
                    icon: const Icon(Icons.done_all),
                    label: const Text('Rest are good'),
                  ),
                ),
                for (final item in shelf.value) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final condition in day.conditions)
                                ChoiceChip(
                                  label: Text(condition.label),
                                  selected:
                                      controller.conditionFor(item) ==
                                      condition.code,
                                  onSelected: controller.busy
                                      ? null
                                      : (_) => _action(
                                          context,
                                          () => controller.setCondition(
                                            item.id,
                                            condition.code,
                                            controller.notesFor(item),
                                          ),
                                        ),
                                ),
                            ],
                          ),
                          if (controller.notesFor(item).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(controller.notesFor(item)),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed:
                                    controller.conditionFor(item) == null ||
                                        controller.busy
                                    ? null
                                    : () => _notes(context, item),
                                icon: const Icon(Icons.edit_note),
                                label: const Text('Notes'),
                              ),
                              TextButton.icon(
                                onPressed:
                                    controller.conditionFor(item) == null ||
                                        controller.busy
                                    ? null
                                    : () => _attach(context, item, false),
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: const Text('Photo'),
                              ),
                              TextButton.icon(
                                onPressed:
                                    controller.conditionFor(item) == null ||
                                        controller.busy
                                    ? null
                                    : () => _attach(context, item, true),
                                icon: const Icon(Icons.video_library_outlined),
                                label: const Text('Video'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ] else if (!controller.loading)
              const LgEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Connect to load your shelves',
                message:
                    'Your saved checks stay in this browser until they upload.',
              ),
          ],
        ),
      ),
    );
  }
}
