import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';

class IdeaInboxScreen extends ConsumerStatefulWidget {
  const IdeaInboxScreen({super.key});

  @override
  ConsumerState<IdeaInboxScreen> createState() => _IdeaInboxScreenState();
}

class _IdeaInboxScreenState extends ConsumerState<IdeaInboxScreen> {

  int _getTotalDaysInYear(int year) {
    bool isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    return isLeapYear ? 366 : 365;
  }

  List<int> _getDaysInMonths(int year) {
    bool isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    return [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final now = DateTime.now();
    final currentYear = now.year;

    final int totalDaysInYear = _getTotalDaysInYear(currentYear);
    final List<int> daysInMonths = _getDaysInMonths(currentYear);

    int currentDayOfYear = 0;
    for (int i = 0; i < now.month - 1; i++) {
      currentDayOfYear += daysInMonths[i];
    }
    currentDayOfYear += now.day;
    double completionPercentage = (currentDayOfYear / totalDaysInYear) * 100;

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    final ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final filledColor = isDark ? Colors.white : Colors.black;

    return Container(
      color: isDark ? Colors.black : Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // STATUS LINE HEADER BLOCK
            Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 14.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'MATRIX TIMELINE',
                    style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.02),
                  ),
                  Text(
                    '$currentDayOfYear / $totalDaysInYear DAYS (${completionPercentage.toStringAsFixed(1)}%)',
                    style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.01),
                  ),
                ],
              ),
            ),

            Divider(color: ruleBorder, height: 1, thickness: 0.8),

            // FREE-FLOWING 15-COLUMN MATRIX EXPANSION
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculates standard square spacing boundaries across 15 columns
                    final double totalSpacing = 5.0 * 14; // 14 gaps between 15 elements
                    final double boxWidth = (constraints.maxWidth - totalSpacing) / 15;

                    return GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: totalDaysInYear,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 15, // Adjusted to 15 squares per line
                        crossAxisSpacing: 5.0, // Tighter gap matrix spacing
                        mainAxisSpacing: 5.0,
                        childAspectRatio: 1.0,
                      ),
                      itemBuilder: (context, index) {
                        final int targetDayIndex = index + 1;
                        final bool isPastOrToday = targetDayIndex <= currentDayOfYear;

                        return Container(
                          width: boxWidth,
                          height: boxWidth,
                          decoration: BoxDecoration(
                            color: isPastOrToday ? filledColor : Colors.transparent,
                            border: Border.all(
                              color: isPastOrToday ? filledColor : ruleBorder,
                              width: 0.8,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            Divider(color: ruleBorder, height: 1, thickness: 0.8),

            // BASE INFRASTRUCTURE STATUS LEGEND
            Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 14.0, 24.0, 16.0),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: filledColor),
                  ),
                  const SizedBox(width: 6),
                  Text('ELAPSED', style: TextStyle(color: textSub, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.02)),
                  const SizedBox(width: 24),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: ruleBorder, width: 0.8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('REMAINING', style: TextStyle(color: textSub, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.02)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}