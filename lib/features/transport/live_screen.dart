import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'desk.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  late final DeskApi _api = DeskApi(context.read<ApiClient>());
  List<LiveCab>? _cabs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final desk = await _api.overview();
      if (!mounted) return;
      setState(() {
        _cabs = desk.live;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cabs = _cabs;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_error != null)
            LgNotice(message: _error!, foreground: LgColors.danger, background: LgColors.dangerBg, icon: Icons.error_outline_rounded),
          if (cabs == null && _error == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator())),
          if (cabs != null && cabs.isEmpty)
            const LgEmptyState(
              icon: Icons.map_rounded,
              title: 'No cab is on the road',
              message: 'Start a trip and the map fills in as the phone sends its position.',
            ),
          if (cabs != null)
            for (final cab in cabs) ...[
              Text(cab.routeName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(
                [cab.directionLabel, if (cab.driverName.isNotEmpty) cab.driverName, if (cab.vehicleNo.isNotEmpty) cab.vehicleNo].join(' · '),
                style: const TextStyle(color: LgColors.muted),
              ),
              const SizedBox(height: 8),
              _Approach(cab: cab),
              const SizedBox(height: 8),
              if (cab.hasFix || cab.stops.any((s) => s.hasPin))
                _CabMap(cab: cab)
              else
                const LgNotice(
                  message: 'Waiting for a fresh GPS fix from the driver’s phone.',
                  foreground: LgColors.warn,
                  background: LgColors.warnBg,
                  icon: Icons.gps_off_rounded,
                ),
              if (cab.stops.any((s) => !s.hasPin)) ...[
                const SizedBox(height: 8),
                LgNotice(
                  message: '${cab.stops.where((s) => !s.hasPin).length} pickup${cab.stops.where((s) => !s.hasPin).length == 1 ? '' : 's'} have no saved location, so they stay off the map.',
                  foreground: LgColors.warn,
                  background: LgColors.warnBg,
                  icon: Icons.location_off_rounded,
                ),
              ],
              const SizedBox(height: 4),
              for (final s in cab.stops)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: !s.hasPin
                        ? LgColors.muted.withValues(alpha: 0.15)
                        : s.status == 'pending'
                            ? LgColors.warnBg
                            : LgColors.okBg,
                    child: Text('${s.order}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  title: Text(s.name),
                  subtitle: Text(
                    !s.hasPin
                        ? 'No location saved'
                        : s.status == 'pending'
                            ? 'Waiting'
                            : s.status == 'absent'
                                ? 'Not riding'
                                : 'Done',
                  ),
                ),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _Approach extends StatelessWidget {
  const _Approach({required this.cab});

  final LiveCab cab;

  @override
  Widget build(BuildContext context) {
    final next = cab.stops.where((s) => s.status == 'pending' && s.hasPin).firstOrNull;
    if (!cab.hasFix || next == null) {
      return Text(
        cab.speedKmh != null ? '${cab.speedKmh} km/h' : 'Follow the stop list.',
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
    }
    final meters = metersBetween(cab.lat!, cab.lng!, next.lat!, next.lng!);
    final speed = cab.speedKmh != null ? ' · ${cab.speedKmh} km/h' : '';
    return Text('${approachPhrase(meters)} — ${next.name}$speed', style: const TextStyle(fontWeight: FontWeight.w700));
  }
}

class _CabMap extends StatelessWidget {
  const _CabMap({required this.cab});

  final LiveCab cab;

  @override
  Widget build(BuildContext context) {
    final pins = [for (final s in cab.stops) if (s.hasPin) s];
    final pinPoints = [for (final s in pins) LatLng(s.lat!, s.lng!)];
    final cabPoint = cab.hasFix ? LatLng(cab.lat!, cab.lng!) : null;
    final frame = [...pinPoints, ?cabPoint];
    final center = frame.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 320,
        child: FlutterMap(
          key: ValueKey('${cab.tripId}:${frame.map((p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}').join('|')}'),
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            initialCameraFit: frame.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(frame),
                    padding: const EdgeInsets.all(48),
                    maxZoom: 16,
                  )
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'in.thelittlegraduates.app',
            ),
            if (pinPoints.length > 1)
              PolylineLayer(polylines: [Polyline(points: pinPoints, color: LgColors.accent, strokeWidth: 4)]),
            MarkerLayer(
              markers: [
                for (final s in pins)
                  Marker(
                    point: LatLng(s.lat!, s.lng!),
                    width: 32,
                    height: 32,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: s.status == 'pending' ? LgColors.warn : LgColors.ok,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text('${s.order}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                if (cabPoint != null)
                  Marker(
                    point: cabPoint,
                    width: 36,
                    height: 36,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: LgColors.accent, shape: BoxShape.circle),
                      child: Icon(Icons.directions_bus_rounded, color: Colors.white, size: 20),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
