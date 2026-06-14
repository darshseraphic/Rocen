import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../core/database.dart';

class IdeaInboxScreen extends ConsumerStatefulWidget {
  const IdeaInboxScreen({super.key});

  @override
  ConsumerState<IdeaInboxScreen> createState() => _IdeaInboxScreenState();
}

class _IdeaInboxScreenState extends ConsumerState<IdeaInboxScreen> {
  static const int _matrixColumns = 7;
  static const List<String> _monthNames = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
  ];
  static const List<String> _dayHeaders = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  int _getTotalDaysInYear(int year) {
    bool isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    return isLeapYear ? 366 : 365;
  }

  List<int> _getDaysInMonths(int year) {
    bool isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    return [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  }

  int _getDayOfYear(int monthIndex, int day, List<int> daysInMonths) {
    int dayOfYear = day;
    for (int i = 0; i < monthIndex; i++) {
      dayOfYear += daysInMonths[i];
    }
    return dayOfYear;
  }

  /// Opens the smooth bottom-to-top custom editor sheet connected directly to Hive
  void _openEventEditor(BuildContext context, String dateKey, String monthName, int day) {
    final localItems = ref.read(localDatabaseProvider);
    CaptureItem? existingItem;

    for (final item in localItems) {
      if (item.type == 'matrix_event:$dateKey') {
        existingItem = item;
        break;
      }
    }

    final titleController = TextEditingController(text: existingItem?.title ?? '');
    final descController = TextEditingController(text: existingItem?.content ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ref.read(themeProvider) ? const Color(0xFF000000) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final isDark = ref.watch(themeProvider);
        final textMain = isDark ? Colors.white : Colors.black;
        final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);

        // Input block set to black in dark theme with dynamic border to keep it visible
        final inputBg = isDark ? Colors.black : const Color(0xFFF5F5F5);
        final inputBorder = isDark ? const Color(0xFF2D2D2D) : Colors.transparent;
        final ruleBorder = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E5E5);

        // Commit button styling
        final btnBgColor = isDark ? Colors.white : Colors.black;
        final btnTextColor = isDark ? Colors.black : Colors.white;

        // Custom Text Selection Theme applied exclusively to the pop-up
        return Theme(
          data: Theme.of(context).copyWith(
            textSelectionTheme: TextSelectionThemeData(
              // Pure white with opacity for dark mode, pure black with opacity for light mode
              selectionColor: isDark
                  ? const Color(0xFFFFFFFF).withOpacity(0.4)
                  : const Color(0xFF000000).withOpacity(0.2),
              // Pure white for dark mode, pure black for light mode
              selectionHandleColor: isDark
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF000000),
              cursorColor: isDark
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF000000),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24.0,
              right: 24.0,
              top: 24.0,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$monthName $day — COMMIT BLOCK',
                        style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.04),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: textSub),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: ruleBorder, height: 1, thickness: 0.8),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleController,
                    style: TextStyle(color: textMain, fontSize: 14),
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: TextStyle(color: textSub, fontSize: 14),
                      filled: true,
                      fillColor: inputBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: isDark ? BorderSide(color: inputBorder, width: 1) : BorderSide.none
                      ),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: isDark ? BorderSide(color: inputBorder, width: 1) : BorderSide.none
                      ),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: isDark ? BorderSide(color: inputBorder, width: 1) : BorderSide.none
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    style: TextStyle(color: textMain, fontSize: 14),
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Description',
                      hintStyle: TextStyle(color: textSub, fontSize: 14),
                      filled: true,
                      fillColor: inputBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: isDark ? BorderSide(color: inputBorder, width: 1) : BorderSide.none
                      ),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: isDark ? BorderSide(color: inputBorder, width: 1) : BorderSide.none
                      ),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: isDark ? BorderSide(color: inputBorder, width: 1) : BorderSide.none
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: btnBgColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () async {
                        final title = titleController.text.trim();
                        final description = descController.text.trim();

                        if (title.isNotEmpty || description.isNotEmpty) {
                          if (existingItem != null) {
                            await ref.read(localDatabaseProvider.notifier).updateItem(
                              existingItem.id,
                              description,
                              title: title,
                            );
                          } else {
                            await ref.read(localDatabaseProvider.notifier).insertItem(
                              description,
                              'matrix_event:$dateKey',
                              title: title,
                            );
                          }
                        } else {
                          if (existingItem != null) {
                            await ref.read(localDatabaseProvider.notifier).deleteItem(existingItem.id);
                          }
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(
                        'COMMIT',
                        style: TextStyle(color: btnTextColor, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.04),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final localItems = ref.watch(localDatabaseProvider);

    final savedEventKeys = localItems
        .where((item) => item.type.startsWith('matrix_event:'))
        .map((item) => item.type.replaceFirst('matrix_event:', ''))
        .toSet();

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

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 14.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'MATRIX TIMELINE',
                    style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.04),
                  ),
                  Text(
                    '$currentDayOfYear / $totalDaysInYear DAYS (${completionPercentage.toStringAsFixed(1)}%)',
                    style: TextStyle(color: textSub, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.01),
                  ),
                ],
              ),
            ),

            Divider(color: ruleBorder, height: 1, thickness: 0.8),

            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                ),
                child: GridView.builder(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                  itemCount: 12,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 18.0,
                    mainAxisSpacing: 24.0,
                    childAspectRatio: 0.76,
                  ),
                  itemBuilder: (context, monthIndex) {
                    final String monthName = _monthNames[monthIndex];
                    final int totalDaysInMonth = daysInMonths[monthIndex];

                    final DateTime firstDayOfMonth = DateTime(currentYear, monthIndex + 1, 1);
                    final int startingWeekday = firstDayOfMonth.weekday;
                    final int leadingBlanks = startingWeekday - 1;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          monthName,
                          style: TextStyle(color: textMain, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.04),
                        ),
                        const SizedBox(height: 8),

                        Expanded(
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _matrixColumns,
                              crossAxisSpacing: 3.5,
                              mainAxisSpacing: 3.5,
                            ),
                            itemCount: _matrixColumns + leadingBlanks + totalDaysInMonth,
                            itemBuilder: (context, index) {
                              if (index < _matrixColumns) {
                                return Center(
                                  child: Text(
                                    _dayHeaders[index],
                                    style: TextStyle(color: textSub, fontSize: 7.5, fontWeight: FontWeight.bold),
                                  ),
                                );
                              }

                              final int gridIndex = index - _matrixColumns;

                              if (gridIndex < leadingBlanks) {
                                return const SizedBox.shrink();
                              }

                              final int day = gridIndex - leadingBlanks + 1;
                              final int dayOfYear = _getDayOfYear(monthIndex, day, daysInMonths);
                              final bool isPastOrToday = dayOfYear <= currentDayOfYear;

                              final String dateKey = '$currentYear-$monthIndex-$day';
                              final bool hasEvent = savedEventKeys.contains(dateKey);

                              Color boxColor;
                              Color borderColor;
                              Color textColor;

                              if (hasEvent) {
                                // Reverted matrix event boxes to dark red
                                boxColor = const Color(0xFF5F0E0D);
                                borderColor = const Color(0xFF5F0E0D);
                                textColor = Colors.white;
                              } else if (isPastOrToday) {
                                boxColor = filledColor;
                                borderColor = filledColor;
                                textColor = isDark ? Colors.black : Colors.white;
                              } else {
                                boxColor = Colors.transparent;
                                borderColor = ruleBorder;
                                textColor = textMain;
                              }

                              return GestureDetector(
                                onTap: () => _openEventEditor(context, dateKey, monthName, day),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: boxColor,
                                    border: Border.all(
                                      color: borderColor,
                                      width: 0.7,
                                    ),
                                    borderRadius: BorderRadius.circular(1.0),
                                  ),
                                  child: Text(
                                    '$day',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 6.8,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            Divider(color: ruleBorder, height: 1, thickness: 0.8),

            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 14.0, 20.0, 16.0),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: filledColor,
                      borderRadius: BorderRadius.circular(1.0),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('ELAPSED', style: TextStyle(color: textSub, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.02)),
                  const SizedBox(width: 16),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: ruleBorder, width: 0.7),
                      borderRadius: BorderRadius.circular(1.0),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('REMAINING', style: TextStyle(color: textSub, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.02)),
                  const SizedBox(width: 16),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5F0E0D), // Reverted the UPCOMING legend color to dark red
                      borderRadius: BorderRadius.circular(1.0),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('UPCOMING', style: TextStyle(color: textSub, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.02)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}