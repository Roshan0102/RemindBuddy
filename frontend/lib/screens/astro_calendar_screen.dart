import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class AstroCalendarScreen extends StatefulWidget {
  const AstroCalendarScreen({super.key});

  @override
  State<AstroCalendarScreen> createState() => _AstroCalendarScreenState();
}

class _AstroCalendarScreenState extends State<AstroCalendarScreen> {
  // Sivaganga, Tamil Nadu coordinates
  double _latitude = 9.8504;
  double _longitude = 78.4809;
  String _locationName = 'Sivaganga, Tamil Nadu';

  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : const Color(0xFF475569);

    // Calculate sunrise / sunset for selected date
    final sunTimes = _calculateSunriseSunset(_selectedDate, _latitude, _longitude);
    final DateTime sunrise = sunTimes['sunrise']!;
    final DateTime sunset = sunTimes['sunset']!;

    // Compute timings (Rahu, Yama, Kuligai)
    final daylightMs = sunset.difference(sunrise).inMilliseconds;
    final double partMs = daylightMs / 8.0;

    final rahu = _getRahuKalam(sunrise, partMs, _selectedDate.weekday);
    final yama = _getYamagandam(sunrise, partMs, _selectedDate.weekday);
    final kuligai = _getKuligaiKalam(sunrise, partMs, _selectedDate.weekday);
    final nallaNeram = _getNallaNeram(_selectedDate.weekday);

    // Calculate next 3 Amavasai and Pournami
    final upcomingNewMoons = _getUpcomingLunarPhases(_selectedDate, true, 3);
    final upcomingFullMoons = _getUpcomingLunarPhases(_selectedDate, false, 3);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Astro Calendar',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.deepOrange, Colors.orangeAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _locationName,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Lat: ${_latitude.toStringAsFixed(4)}° N  |  Lng: ${_longitude.toStringAsFixed(4)}° E',
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Date Picker Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.withOpacity(0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      Text(
                        'Traditional Daily Timings',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: subtextColor,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Change'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.withOpacity(0.15),
                      foregroundColor: Colors.orange[800],
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Sunrise & Sunset Cards
            Row(
              children: [
                Expanded(
                  child: _buildTimeCard(
                    context,
                    'Sunrise',
                    DateFormat('h:mm a').format(sunrise),
                    Icons.wb_sunny_outlined,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTimeCard(
                    context,
                    'Sunset',
                    DateFormat('h:mm a').format(sunset),
                    Icons.wb_twilight,
                    Colors.deepPurple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Auspicious / Inauspicious Timings Card
            Text(
              'Daily Panchangam Hours',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                children: [
                  _buildTimingRow(
                    'Nalla Neram (Good Time)',
                    nallaNeram,
                    Icons.check_circle_outline,
                    const Color(0xFF0D9488),
                  ),
                  const Divider(),
                  _buildTimingRow(
                    'Rahu Kalam',
                    '${DateFormat('h:mm a').format(rahu['start']!)} - ${DateFormat('h:mm a').format(rahu['end']!)}',
                    Icons.error_outline,
                    const Color(0xFFDC2626),
                  ),
                  const Divider(),
                  _buildTimingRow(
                    'Yamagandam',
                    '${DateFormat('h:mm a').format(yama['start']!)} - ${DateFormat('h:mm a').format(yama['end']!)}',
                    Icons.warning_amber_outlined,
                    const Color(0xFFEA580C),
                  ),
                  const Divider(),
                  _buildTimingRow(
                    'Kuligai Kalam',
                    '${DateFormat('h:mm a').format(kuligai['start']!)} - ${DateFormat('h:mm a').format(kuligai['end']!)}',
                    Icons.hourglass_empty_outlined,
                    const Color(0xFF2563EB),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Lunar Phases Card (Upcoming Pournami & Amavasai)
            Text(
              'Upcoming Lunar Phases (Sivaganga View)',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Amavasai List
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.nightlight_outlined, size: 20, color: Colors.blueGrey),
                            const SizedBox(width: 8),
                            Text(
                              'Amavasai (New Moon)',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...upcomingNewMoons.map((dt) => _buildLunarDateRow(dt, subtextColor)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Pournami List
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.lens, size: 20, color: Colors.amber),
                            const SizedBox(width: 8),
                            Text(
                              'Pournami (Full Moon)',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...upcomingFullMoons.map((dt) => _buildLunarDateRow(dt, subtextColor)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeCard(BuildContext context, String label, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                ),
              ),
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimingRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLunarDateRow(DateTime date, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMM d, yyyy (EEE)').format(date),
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            DateFormat('h:mm a').format(date),
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: subtextColor,
            ),
          ),
        ],
      ),
    );
  }

  // --- MATHEMATICAL CALCULATIONS ---

  // Sunrise equation local implementation (approximate for India latitudes)
  Map<String, DateTime> _calculateSunriseSunset(DateTime date, double latitude, double longitude) {
    // Standard Sunrise Equation
    final double latRad = latitude * math.pi / 180.0;
    
    // Day of year
    final int dayOfYear = int.parse(DateFormat('D').format(date));
    
    // Calculate solar declination
    final double dec = 23.45 * math.sin(2 * math.pi * (284 + dayOfYear) / 365.0) * math.pi / 180.0;
    
    // Calculate Equation of Time (in minutes)
    final double b = 2 * math.pi * (dayOfYear - 81) / 364.0;
    final double eqTime = 9.87 * math.sin(2 * b) - 7.53 * math.cos(b) - 1.5 * math.sin(b);
    
    // Hour Angle (H)
    final double cosH = (math.sin(-0.83 * math.pi / 180.0) - math.sin(latRad) * math.sin(dec)) / (math.cos(latRad) * math.cos(dec));
    
    double hDegrees = 90.0; // Default approximation
    if (cosH >= -1.0 && cosH <= 1.0) {
      hDegrees = math.acos(cosH) * 180.0 / math.pi;
    }
    
    // Convert to local time (IST = UTC + 5.5)
    // Noon in UTC relative to longitude: 12 - longitude/15
    final double solarNoonUtc = 12.0 - (longitude / 15.0) - (eqTime / 60.0);
    
    final double sunriseUtc = solarNoonUtc - (hDegrees / 15.0);
    final double sunsetUtc = solarNoonUtc + (hDegrees / 15.0);
    
    final DateTime baseDate = DateTime(date.year, date.month, date.day);
    
    // Convert to Local Time (IST = +5.5 hours)
    final sunriseLocal = baseDate.add(Duration(minutes: ((sunriseUtc + 5.5) * 60).round()));
    final sunsetLocal = baseDate.add(Duration(minutes: ((sunsetUtc + 5.5) * 60).round()));
    
    return {
      'sunrise': sunriseLocal,
      'sunset': sunsetLocal,
    };
  }

  // Monday = 1, Tuesday = 2, ... Sunday = 7
  Map<String, DateTime> _getRahuKalam(DateTime sunrise, double partMs, int weekday) {
    final int partIndex = [
      1, // Monday = 2nd part (index 1)
      6, // Tuesday = 7th part (index 6)
      4, // Wednesday = 5th part (index 4)
      5, // Thursday = 6th part (index 5)
      3, // Friday = 4th part (index 3)
      2, // Saturday = 3rd part (index 2)
      7, // Sunday = 8th part (index 7)
    ][weekday - 1];

    final start = sunrise.add(Duration(milliseconds: (partMs * partIndex).toInt()));
    final end = sunrise.add(Duration(milliseconds: (partMs * (partIndex + 1)).toInt()));
    return {'start': start, 'end': end};
  }

  Map<String, DateTime> _getYamagandam(DateTime sunrise, double partMs, int weekday) {
    final int partIndex = [
      4, // Monday = 5th part (index 4)
      3, // Tuesday = 4th part (index 3)
      2, // Wednesday = 3rd part (index 2)
      1, // Thursday = 2nd part (index 1)
      7, // Friday = 8th part (index 7)
      6, // Saturday = 7th part (index 6)
      5, // Sunday = 6th part (index 5)
    ][weekday - 1];

    final start = sunrise.add(Duration(milliseconds: (partMs * partIndex).toInt()));
    final end = sunrise.add(Duration(milliseconds: (partMs * (partIndex + 1)).toInt()));
    return {'start': start, 'end': end};
  }

  Map<String, DateTime> _getKuligaiKalam(DateTime sunrise, double partMs, int weekday) {
    final int partIndex = [
      7, // Monday = 8th part (index 7)
      5, // Tuesday = 6th part (index 5)
      4, // Wednesday = 5th part (index 4)
      3, // Thursday = 4th part (index 3)
      2, // Friday = 3rd part (index 2)
      1, // Saturday = 2nd part (index 1)
      0, // Sunday = 1st part (index 0)
    ][weekday - 1];

    final start = sunrise.add(Duration(milliseconds: (partMs * partIndex).toInt()));
    final end = sunrise.add(Duration(milliseconds: (partMs * (partIndex + 1)).toInt()));
    return {'start': start, 'end': end};
  }

  String _getNallaNeram(int weekday) {
    // Auspicious times are traditionally weekday relative
    return [
      '6:00 AM - 7:30 AM | 4:30 PM - 6:00 PM', // Mon
      '7:30 AM - 9:00 AM | 4:30 PM - 6:00 PM', // Tue
      '9:00 AM - 10:30 AM | 4:30 PM - 6:00 PM', // Wed
      '9:00 AM - 10:30 AM | 4:30 PM - 6:00 PM', // Thu
      '9:00 AM - 10:30 AM | 4:30 PM - 6:00 PM', // Fri
      '7:30 AM - 9:00 AM | 4:30 PM - 6:00 PM', // Sat
      '7:30 AM - 9:00 AM | 4:30 PM - 6:00 PM', // Sun
    ][weekday - 1];
  }

  // Analytical Calculation of next N Lunar Phases
  List<DateTime> _getUpcomingLunarPhases(DateTime startDate, bool getNewMoon, int count) {
    final epoch = DateTime.utc(2000, 1, 6, 18, 14); // Known New Moon
    final cycle = 29.530588853; // Synodic month
    final startDiffDays = startDate.difference(epoch).inSeconds / 86400.0;
    
    final double startMonth = startDiffDays / cycle;
    List<DateTime> results = [];
    
    // Find next matching month segments
    int monthIndex = startMonth.floor();
    while (results.length < count) {
      double targetMonthFraction = getNewMoon ? 0.0 : 0.5;
      double targetDays = (monthIndex + targetMonthFraction) * cycle;
      
      final targetDate = epoch.add(Duration(minutes: (targetDays * 1440).round())).toLocal();
      if (targetDate.isAfter(startDate)) {
        results.add(targetDate);
      }
      monthIndex++;
    }
    
    return results;
  }
}
