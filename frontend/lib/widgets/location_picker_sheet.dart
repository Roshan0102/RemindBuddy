import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/saved_place.dart';
import '../services/saved_places_service.dart';

class PickedLocationResult {
  final String locationName;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String triggerCondition; // 'enter' or 'exit'
  final String? savedPlaceId;

  const PickedLocationResult({
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.triggerCondition,
    this.savedPlaceId,
  });
}

class LocationPickerSheet extends StatefulWidget {
  final String? initialName;
  final double? initialLat;
  final double? initialLng;
  final double initialRadius;
  final String initialTrigger;
  final String? initialSavedPlaceId;

  const LocationPickerSheet({
    super.key,
    this.initialName,
    this.initialLat,
    this.initialLng,
    this.initialRadius = 50.0,
    this.initialTrigger = 'enter',
    this.initialSavedPlaceId,
  });

  static Future<PickedLocationResult?> show(
    BuildContext context, {
    String? initialName,
    double? initialLat,
    double? initialLng,
    double initialRadius = 50.0,
    String initialTrigger = 'enter',
    String? initialSavedPlaceId,
  }) {
    return showModalBottomSheet<PickedLocationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LocationPickerSheet(
        initialName: initialName,
        initialLat: initialLat,
        initialLng: initialLng,
        initialRadius: initialRadius,
        initialTrigger: initialTrigger,
        initialSavedPlaceId: initialSavedPlaceId,
      ),
    );
  }

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final MapController _mapController = MapController();
  final SavedPlacesService _savedPlacesService = SavedPlacesService();
  final TextEditingController _nameController = TextEditingController();

  late double _selectedLat;
  late double _selectedLng;
  late double _radiusMeters;
  late String _triggerCondition;
  String? _selectedSavedPlaceId;

  bool _isFetchingGPS = false;
  bool _saveAsFavourite = false;
  final String _placeIcon = 'building';

  // Default fallback (Bangalore, India or center coordinate)
  static const double _fallbackLat = 12.9716;
  static const double _fallbackLng = 77.5946;

  @override
  void initState() {
    super.initState();
    _selectedLat = widget.initialLat ?? _fallbackLat;
    _selectedLng = widget.initialLng ?? _fallbackLng;
    _radiusMeters = widget.initialRadius;
    _triggerCondition = widget.initialTrigger;
    _selectedSavedPlaceId = widget.initialSavedPlaceId;
    _nameController.text = widget.initialName ?? 'My Location';

    if (widget.initialLat == null) {
      // Auto-fetch current position if no initial coordinate provided
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCurrentLocation());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isFetchingGPS = true);
    final pos = await _savedPlacesService.getCurrentPosition();
    if (mounted) {
      setState(() => _isFetchingGPS = false);
      if (pos != null) {
        setState(() {
          _selectedLat = pos.latitude;
          _selectedLng = pos.longitude;
          if (_nameController.text == 'My Location') {
            _nameController.text = 'Current Location';
          }
        });
        _mapController.move(LatLng(pos.latitude, pos.longitude), 16.5);
      }
    }
  }

  void _onSelectSavedPlace(SavedPlace place) {
    setState(() {
      _selectedSavedPlaceId = place.id;
      _selectedLat = place.latitude;
      _selectedLng = place.longitude;
      _radiusMeters = place.radiusMeters;
      _nameController.text = place.name;
    });
    _mapController.move(LatLng(place.latitude, place.longitude), 16.5);
  }

  Future<void> _confirmSelection() async {
    final locationName = _nameController.text.trim().isEmpty ? 'Selected Location' : _nameController.text.trim();

    String? savedId = _selectedSavedPlaceId;

    if (_saveAsFavourite && savedId == null) {
      final newPlace = SavedPlace(
        name: locationName,
        latitude: _selectedLat,
        longitude: _selectedLng,
        radiusMeters: _radiusMeters,
        iconName: _placeIcon,
      );
      savedId = await _savedPlacesService.savePlace(newPlace);
    }

    if (mounted) {
      Navigator.pop(
        context,
        PickedLocationResult(
          locationName: locationName,
          latitude: _selectedLat,
          longitude: _selectedLng,
          radiusMeters: _radiusMeters,
          triggerCondition: _triggerCondition,
          savedPlaceId: savedId,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textTheme = GoogleFonts.outfit();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on_rounded, color: Color(0xFF6366F1), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set Location Reminder 📍',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Tap on the map or pick a saved place',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          // Saved Places Chips
          SizedBox(
            height: 44,
            child: StreamBuilder<List<SavedPlace>>(
              stream: _savedPlacesService.getSavedPlacesStream(),
              builder: (context, snapshot) {
                final places = snapshot.data ?? [];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // GPS Button
                    ActionChip(
                      avatar: _isFetchingGPS
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded, size: 16, color: Color(0xFF6366F1)),
                      label: Text(
                        'Current Location',
                        style: textTheme.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      backgroundColor: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.2 : 0.1),
                      side: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                      onPressed: _isFetchingGPS ? null : _fetchCurrentLocation,
                    ),
                    const SizedBox(width: 8),

                    // User Saved Places Chips
                    ...places.map((place) {
                      final isSelected = _selectedSavedPlaceId == place.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(
                            _getIconForName(place.iconName),
                            size: 16,
                            color: isSelected ? Colors.white : const Color(0xFF6366F1),
                          ),
                          label: Text(
                            place.name,
                            style: textTheme.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFF6366F1),
                          backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                          onSelected: (_) => _onSelectSavedPlace(place),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Map View with live geofence circle
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(_selectedLat, _selectedLng),
                      initialZoom: 16.5,
                      onTap: (tapPosition, point) {
                        setState(() {
                          _selectedLat = point.latitude;
                          _selectedLng = point.longitude;
                          _selectedSavedPlaceId = null;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.remindbuddy.remindbuddy',
                      ),
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: LatLng(_selectedLat, _selectedLng),
                            radius: _radiusMeters,
                            useRadiusInMeter: true,
                            color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                            borderColor: const Color(0xFF6366F1),
                            borderStrokeWidth: 2.5,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(_selectedLat, _selectedLng),
                            width: 50,
                            height: 50,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_pin,
                              color: Color(0xFFEF4444),
                              size: 46,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Radius Badge Overlay
                Positioned(
                  top: 10,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.radar_rounded, size: 14, color: Color(0xFF818CF8)),
                        const SizedBox(width: 5),
                        Text(
                          'Zone: ${_radiusMeters.round()}m',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Controls & Customization Bottom Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Location Name Field
                TextField(
                  controller: _nameController,
                  style: textTheme.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    labelText: 'Location Name (e.g. My PG, Office)',
                    prefixIcon: const Icon(Icons.edit_location_alt_rounded, size: 20, color: Color(0xFF6366F1)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Trigger Condition (Arrive / Leave)
                Row(
                  children: [
                    Text('Trigger:', style: textTheme.copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'enter',
                            icon: Icon(Icons.login_rounded, size: 16),
                            label: Text('When I Arrive'),
                          ),
                          ButtonSegment<String>(
                            value: 'exit',
                            icon: Icon(Icons.logout_rounded, size: 16),
                            label: Text('When I Leave'),
                          ),
                        ],
                        selected: {_triggerCondition},
                        onSelectionChanged: (val) {
                          setState(() => _triggerCondition = val.first);
                        },
                        style: ButtonStyle(
                          textStyle: WidgetStateProperty.all(GoogleFonts.outfit(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Radius Selector Chips
                Row(
                  children: [
                    Text('Radius:', style: textTheme.copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        children: [50.0, 75.0, 100.0, 150.0, 200.0].map((r) {
                          final isSel = _radiusMeters == r;
                          return ChoiceChip(
                            label: Text('${r.round()}m${r == 50.0 ? " ⭐" : ""}'),
                            selected: isSel,
                            onSelected: (_) => setState(() => _radiusMeters = r),
                            labelStyle: textTheme.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSel ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            selectedColor: const Color(0xFF6366F1),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),

                // Save to Favourites Toggle (if not already a saved place)
                if (_selectedSavedPlaceId == null) ...[
                  Row(
                    children: [
                      Checkbox(
                        value: _saveAsFavourite,
                        activeColor: const Color(0xFF6366F1),
                        onChanged: (val) => setState(() => _saveAsFavourite = val ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'Save as favourite place for quick 1-tap reuse next time',
                          style: textTheme.copyWith(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('Cancel', style: textTheme.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _confirmSelection,
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text('Set Location Reminder', style: textTheme.copyWith(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForName(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
      case 'office':
        return Icons.work_rounded;
      case 'cart':
      case 'supermarket':
        return Icons.shopping_cart_rounded;
      case 'fitness':
      case 'gym':
        return Icons.fitness_center_rounded;
      case 'building':
      case 'pg':
      case 'hostel':
      default:
        return Icons.apartment_rounded;
    }
  }
}
