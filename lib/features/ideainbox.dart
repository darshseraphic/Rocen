import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';

class IdeaInboxScreen extends ConsumerStatefulWidget {
  const IdeaInboxScreen({super.key});

  @override
  ConsumerState<IdeaInboxScreen> createState() => _IdeaInboxScreenState();
}

class _IdeaInboxScreenState extends ConsumerState<IdeaInboxScreen> {

  // Helper to determine the number of days in each month for the current year
  List<int> _getDaysInMonths(int year) {
    bool isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    return [
      31, // Jan
      isLeapYear ? 29 : 28, // Feb
      31, // Mar
      30, // Apr
      31, // May
      30, // Jun
      31, // Jul
      31, // Aug
      30, // Sep
      31, // Oct
      30, // Nov
      31  // Dec
    ];
  }

  // Short labels for the matrix rows
  final List<String> _monthLabels = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);

    // Get current calendar data
    final now = DateTime.now();
    final currentYear = now.year;
    final daysInMonths = _getDaysInMonths(currentYear);

    // Styling configurations matching your system's brutalist vibe
    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    final ruleBorder = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final filledColor = isDark ? Colors.white : Colors.black;

    // Calculate absolute day of the year progress metrics
    int totalDaysInYear = daysInMonths.reduce((a, b) => a + b);

    int currentDayOfYear = 0;
    for (int i = 0; i < now.month - 1; i++) {
      currentDayOfYear += daysInMonths[i];
    }
    currentDayOfYear += now.day;

    double completionPercentage = (currentDayOfYear / totalDaysInYear) * 100;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // MATRIX HEADLINE METRICS
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'YEAR PROGRESSION',
                style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
              ),
              Text(
                '$currentDayOfYear / $totalDaysInYear DAYS (${completionPercentage.toStringAsFixed(1)}%)',
                style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.02),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // THE 365 GRID SYSTEM CONTAINER
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: ruleBorder, width: 0.8),
                ),
                child: Column(
                  children: List.generate(12, (monthIndex) {
                    final daysInThisMonth = daysInMonths[monthIndex];

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5.0),
                      child: Row(
                        children: [
                          // Fixed dimension Month Label code block
                          SizedBox(
                            width: 32,
                            child: Text(
                              _monthLabels[monthIndex],
                              style: TextStyle(
                                color: textSub,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.05,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Horizontal sequence mapping the specific days
                          Expanded(
                            child: Wrap(
                              spacing: 3.5,
                              runSpacing: 3.5,
                              children: List.generate(daysInThisMonth, (dayIndex) {
                                final targetDate = DateTime(currentYear, monthIndex + 1, dayIndex + 1);

                                // Determine if this iteration block represents a historical/current date
                                final bool isPastOrToday = targetDate.isBefore(now) ||
                                    (targetDate.year == now.year &&
                                        targetDate.month == now.month &&
                                        targetDate.day == now.day);

                                return Container(
                                  width: 7.5,
                                  height: 7.5,
                                  decoration: BoxDecoration(
                                    color: isPastOrToday ? filledColor : Colors.transparent,
                                    border: Border.all(
                                      color: isPastOrToday ? filledColor : ruleBorder,
                                      width: 0.7,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // GRID LEGEND SYSTEM FOOTER
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: filledColor,
                  border: Border.all(color: filledColor, width: 0.7),
                ),
              ),
              const SizedBox(width: 6),
              Text('ELAPSED', style: TextStyle(color: textSub, fontSize: 10, fontWeight: FontWeight.w500)),
              const SizedBox(width: 16),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: ruleBorder, width: 0.7),
                ),
              ),
              const SizedBox(width: 6),
              Text('REMAINING', style: TextStyle(color: textSub, fontSize: 10, fontWeight: FontWeight.w500)),
            ],
          )
        ],
      ),
    );
  }
}