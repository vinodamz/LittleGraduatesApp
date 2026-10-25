import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/module_registry.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'materials_api.dart';
import 'materials_controller.dart';
import 'materials_queue.dart';

class MaterialsScreen extends StatelessWidget {
  const MaterialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MaterialsController>();
    final day = controller.day;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Materials'),
        actions: [
          if (day != null)
            PopupMenuButton<String>(
              onSelected: (value) => _openLink(context, day, value),
              itemBuilder: (context) => [
                if (day.canMonthly) ...[
                  const PopupMenuItem(
                    value: 'history',
                    child: Text('Audit history'),
                  ),
                  const PopupMenuItem(value: 'trends', child: Text('Trends')),
                  const PopupMenuItem(
                    value: 'monthly',
                    child: Text('Monthly board'),
                  ),
                ],
                const PopupMenuItem(value: 'duties', child: Text('My duties')),
                if (day.isAdmin)
                  const PopupMenuItem(
                    value: 'assign',
                    child: Text('Assign someone'),
                  ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.kick,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              day?.dateLabel.isNotEmpty == true ? day!.dateLabel : 'Today',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              day == null
                  ? 'The shelf list loads from the school.'
                  : '${day.summary.checked} of ${day.summary.total} checked · a fresh check each day',
              style: const TextStyle(color: LgColors.muted),
            ),
            const SizedBox(height: 12),
            if (controller.pendingCount > 0) ...[
              LgNotice(
                message: controller.failedCount > 0
                    ? '${controller.pendingCount} saved on this phone. ${controller.failedCount} need a retry.'
                    : '${controller.pendingCount} saved on this phone — uploading in the background.',
                foreground: controller.failedCount > 0
                    ? LgColors.warn
                    : LgColors.info,
                background: controller.failedCount > 0
                    ? LgColors.warnBg
                    : LgColors.infoBg,
                icon: Icons.cloud_upload_rounded,
              ),
              const SizedBox(height: 12),
            ],
            if (controller.error != null && day == null) ...[
              LgNotice(
                message: controller.error!,
                foreground: LgColors.danger,
                background: LgColors.dangerBg,
                icon: Icons.error_outline_rounded,
              ),
              const SizedBox(height: 12),
            ],
            if (loadingWithoutList(controller))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (day == null)
              const LgEmptyState(
                icon: Icons.category_rounded,
                title: 'No shelf list yet',
                message:
                    'Connect once so today’s materials stay on this phone.',
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily shelf check',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: day.summary.total == 0
                            ? 0
                            : (day.summary.checked / day.summary.total).clamp(
                                0,
                                1,
                              ),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                        backgroundColor: LgColors.accentSoft,
                        semanticsLabel: 'Daily materials checked',
                        semanticsValue:
                            '${day.summary.total == 0 ? 0 : (100 * day.summary.checked / day.summary.total).round()}%',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${day.summary.pending} left to check · Changes save automatically.',
                        style: const TextStyle(color: LgColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search materials',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: controller.setQuery,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: controller.location,
                decoration: const InputDecoration(labelText: 'Shelf'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All shelves')),
                  for (final shelf in day.locations)
                    DropdownMenuItem(
                      value: shelf,
                      child: Text(shelf.isEmpty ? 'No shelf' : shelf),
                    ),
                ],
                onChanged: (value) => controller.setLocation(value ?? ''),
              ),
              const SizedBox(height: 16),
              if (controller.visible.isEmpty)
                const LgEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No materials match',
                  message: 'Clear the search or pick another shelf.',
                )
              else
                for (final entry in controller.shelves.entries) ...[
                  _ShelfCard(location: entry.key, items: entry.value),
                  const SizedBox(height: 12),
                ],
            ],
          ],
        ),
      ),
    );
  }

  bool loadingWithoutList(MaterialsController controller) =>
      controller.loading && controller.day == null;

  Future<void> _openLink(BuildContext context, MaterialsDay day, String key) {
    final links = day.links;
    final url = switch (key) {
      'history' => links.history,
      'trends' => links.trends,
      'monthly' => links.monthly,
      'assign' => links.assign,
      _ => links.duties,
    };
    final label = switch (key) {
      'history' => 'Audit history',
      'trends' => 'Trends',
      'monthly' => 'Monthly board',
      'assign' => 'Assign someone',
      _ => 'My duties',
    };
    return openWebUrl(context, url, label);
  }
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({required this.location, required this.items});

  final String location;
  final List<MaterialItem> items;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MaterialsController>();
    var checked = 0;
    for (final item in items) {
      if (controller.viewFor(item)?.checked == true) checked++;
    }
    final title = location.isEmpty ? 'No shelf' : location;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title · $checked/${items.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (checked < items.length)
                  TextButton(
                    onPressed: () => _confirmGood(context, title),
                    child: const Text('Rest are Good'),
                  ),
              ],
            ),
            for (final item in items) _MaterialTile(item: item),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmGood(BuildContext context, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark the rest Good?'),
        content: Text(
          'Every material on $title with no mark today becomes Good. Anything already marked stays as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark Good'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<MaterialsController>().markRestGood(location);
    }
  }
}

class _MaterialTile extends StatefulWidget {
  const _MaterialTile({required this.item});

  final MaterialItem item;

  @override
  State<_MaterialTile> createState() => _MaterialTileState();
}

class _MaterialTileState extends State<_MaterialTile> {
  late final TextEditingController _notes;
  late final FocusNode _focus;
  Timer? _debounce;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final view = context.read<MaterialsController>().viewFor(widget.item);
    _notes = TextEditingController(text: view?.notes ?? '');
    _focus = FocusNode()..addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _MaterialTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final view = context.read<MaterialsController>().viewFor(widget.item);
    final notes = view?.notes ?? '';
    if (!_focus.hasFocus && notes != _notes.text) _notes.text = notes;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _flushNotes();
  }

  void _flushNotes() {
    _debounce?.cancel();
    context.read<MaterialsController>().setNotes(widget.item.id, _notes.text);
  }

  Future<void> _capture(ImageSource source, {required bool video}) async {
    try {
      final file = video
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source);
      if (file == null || !mounted) return;
      await context.read<MaterialsController>().addMedia(
        widget.item.id,
        source: File(file.path),
        filename: file.name,
        mediaKind: video ? 'video' : 'photo',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the camera.')),
      );
    }
  }

  Future<void> _gallery() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: LgColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'video') {
      await _capture(ImageSource.gallery, video: true);
      return;
    }
    try {
      final files = await _picker.pickMultiImage();
      if (!mounted) return;
      final controller = context.read<MaterialsController>();
      for (final file in files) {
        await controller.addMedia(
          widget.item.id,
          source: File(file.path),
          filename: file.name,
          mediaKind: 'photo',
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the gallery.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MaterialsController>();
    final view = controller.viewFor(widget.item);
    if (view == null) return const SizedBox.shrink();
    final tone = _toneColors(view.tone);
    final token = context.read<ApiClient>().token;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(view: view, token: token),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      view.line,
                      style: TextStyle(
                        color: view.checked ? tone.foreground : LgColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (view.item.media.isNotEmpty || view.localMedia.isNotEmpty)
                LgStatusPill(
                  label: '${view.item.media.length + view.localMedia.length}',
                  foreground: LgColors.info,
                  background: LgColors.infoBg,
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: view.conditionCode ?? '',
            items: [
              const DropdownMenuItem(value: '', child: Text('Condition')),
              for (final condition
                  in controller.day?.conditions ?? const <MaterialCondition>[])
                DropdownMenuItem(
                  value: condition.code,
                  child: Text(condition.label),
                ),
            ],
            onChanged: (value) {
              if (value == null || value.isEmpty) return;
              controller.setCondition(widget.item.id, value, _notes.text);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            focusNode: _focus,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Comment (optional)',
              counterText: '',
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 1200),
                _flushNotes,
              );
            },
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Take a photo',
                onPressed: () => _capture(ImageSource.camera, video: false),
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              IconButton(
                tooltip: 'Record a video',
                onPressed: () => _capture(ImageSource.camera, video: true),
                icon: const Icon(Icons.videocam_outlined),
              ),
              IconButton(
                tooltip: 'Choose from gallery',
                onPressed: _gallery,
                icon: const Icon(Icons.photo_library_outlined),
              ),
            ],
          ),
          for (final media in view.localMedia) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    mediaStatusLabel(media),
                    style: const TextStyle(color: LgColors.muted, fontSize: 13),
                  ),
                ),
                if (media.status == OutboxStatus.failed && media.id != null)
                  TextButton(
                    onPressed: () => controller.retryItem(media.id!),
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ],
          if (view.mark?.status == OutboxStatus.failed && view.mark?.id != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => controller.retryItem(view.mark!.id!),
                child: const Text('Retry save'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.view, required this.token});

  final MaterialView view;
  final String? token;

  @override
  Widget build(BuildContext context) {
    final local = view.localMedia.where(
      (item) => item.mediaKind == 'photo' && item.originalPath != null,
    );
    if (local.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(local.first.originalPath!),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      );
    }
    final remote = view.item.media.where(
      (item) => item.kind == 'photo' && (item.thumbUrl ?? item.url).isNotEmpty,
    );
    if (remote.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          remote.first.thumbUrl ?? remote.first.url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          headers: {
            'User-Agent': ApiClient.userAgent,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          errorBuilder: (_, _, _) =>
              const _ThumbFallback(icon: Icons.image_outlined),
        ),
      );
    }
    if (view.item.media.any((item) => item.kind == 'video') ||
        view.localMedia.any((item) => item.mediaKind == 'video')) {
      return const _ThumbFallback(icon: Icons.videocam_outlined);
    }
    return const _ThumbFallback(icon: Icons.category_outlined);
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: LgColors.accentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: LgColors.accent, size: 22),
    );
  }
}

({Color foreground, Color background}) _toneColors(String tone) =>
    switch (tone) {
      'ok' => (foreground: LgColors.ok, background: LgColors.okBg),
      'warn' => (foreground: LgColors.warn, background: LgColors.warnBg),
      'bad' => (foreground: LgColors.danger, background: LgColors.dangerBg),
      _ => (foreground: LgColors.muted, background: LgColors.line),
    };
