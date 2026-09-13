import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/saved_place.dart';
import '../services/saved_places_service.dart';
import 'location_picker_sheet.dart';

class SavedPlacesSheet extends StatefulWidget {
  const SavedPlacesSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const SavedPlacesSheet(),
    );
  }

  @override
  State<SavedPlacesSheet> createState() => _SavedPlacesSheetState();
}

class _SavedPlacesSheetState extends State<SavedPlacesSheet> {
  final SavedPlacesService _placesService = SavedPlacesService();

  Future<void> _addNewPlace() async {
    final result = await LocationPickerSheet.show(
      context,
      initialName: 'My Place',
      initialRadius: 50.0,
    );

    if (result != null) {
      final newPlace = SavedPlace(
        name: result.locationName,
        latitude: result.latitude,
        longitude: result.longitude,
        radiusMeters: result.radiusMeters,
      );
      await _placesService.savePlace(newPlace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "${result.locationName}" to your places! 📍', style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textTheme = GoogleFonts.outfit();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bookmark_added_rounded, color: Color(0xFF6366F1), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saved Places 🏢',
                        style: textTheme.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Your frequent locations for 1-tap reminders',
                        style: textTheme.copyWith(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
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
          const Divider(height: 1),

          // List of Saved Places
          Expanded(
            child: StreamBuilder<List<SavedPlace>>(
              stream: _placesService.getSavedPlacesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final places = snapshot.data ?? [];

                if (places.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.pin_drop_rounded, size: 36, color: Color(0xFF6366F1)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Saved Places Yet',
                            style: textTheme.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Save your PG, Office, or Home for easy 1-tap location reminders.',
                            textAlign: TextAlign.center,
                            style: textTheme.copyWith(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _addNewPlace,
                            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                            label: Text('Add Your First Place', style: textTheme.copyWith(fontWeight: FontWeight.bold)),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: places.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final place = places[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_getIconForName(place.iconName), color: const Color(0xFF6366F1), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  place.name,
                                  style: textTheme.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Radius: ${place.radiusMeters.round()}m  •  Lat: ${place.latitude.toStringAsFixed(4)}, Lng: ${place.longitude.toStringAsFixed(4)}',
                                  style: textTheme.copyWith(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('Delete "${place.name}"?', style: textTheme.copyWith(fontWeight: FontWeight.bold)),
                                  content: Text('Are you sure you want to remove this saved place?', style: textTheme),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text('Cancel', style: textTheme),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                      child: Text('Delete', style: textTheme.copyWith(fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && place.id != null) {
                                await _placesService.deletePlace(place.id!);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Bottom Action
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _addNewPlace,
                icon: const Icon(Icons.add_location_alt_rounded, size: 20),
                label: Text('Save New Place', style: textTheme.copyWith(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
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
