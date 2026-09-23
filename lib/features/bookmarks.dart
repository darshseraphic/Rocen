import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../main.dart';

class TodoItem {
  final String id;
  final String text;
  final bool isCompleted;

  TodoItem({
    required this.id,
    required this.text,
    this.isCompleted = false,
  });

  TodoItem copyWith({String? id, String? text, bool? isCompleted}) {
    return TodoItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class TodoNotifier extends Notifier<List<TodoItem>> {
  static const String protectedDataUnavailableMessage =
      'PROTECTED TODO PERSISTENCE IS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE EXISTS.';

  @override
  List<TodoItem> build() => <TodoItem>[];

  Future<bool> addTask(String text) async {
    if (!protectedApplicationPersistenceAvailable || text.trim().isEmpty) {
      return false;
    }
    return false;
  }

  Future<bool> toggleTask(String id) async {
    return false;
  }

  Future<bool> deleteTask(String id) async {
    return false;
  }
}

final todoProvider =
    NotifierProvider<TodoNotifier, List<TodoItem>>(TodoNotifier.new);

class BookmarksScreen extends ConsumerStatefulWidget {
  const BookmarksScreen({super.key});

  @override
  ConsumerState<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends ConsumerState<BookmarksScreen> {
  final TextEditingController _taskController = TextEditingController();

  Future<void> _submitTask() async {
    if (!protectedApplicationPersistenceAvailable) return;
    final bool saved =
        await ref.read(todoProvider.notifier).addTask(_taskController.text);
    if (!saved || !mounted) return;
    _taskController.clear();
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final tasks = ref.watch(todoProvider);

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final borderColor =
        isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final containerBg =
        isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: textMain.withValues(alpha: 0.2),
          selectionHandleColor: textMain,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TO-DO LIST',
              style: TextStyle(
                  color: textMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.02),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              decoration: BoxDecoration(
                color: containerBg,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taskController,
                      enabled: protectedApplicationPersistenceAvailable,
                      style: TextStyle(color: textMain, fontSize: 13),
                      cursorColor: textMain,
                      decoration: InputDecoration(
                        hintText: 'ADD NEW TASK...',
                        hintStyle: TextStyle(
                            color: textSub, fontSize: 12, letterSpacing: 0.05),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => _submitTask(),
                    ),
                  ),
                  GestureDetector(
                    onTap: protectedApplicationPersistenceAvailable ? _submitTask : null,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Text(
                        '+',
                        style: TextStyle(
                          color: textMain,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
            if (!protectedApplicationPersistenceAvailable)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  TodoNotifier.protectedDataUnavailableMessage,
                  style: TextStyle(color: textSub, fontSize: 10),
                ),
              ),
            Divider(color: borderColor, height: 32, thickness: 0.8),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                        'NO PENDING TASKS',
                        style: TextStyle(
                            color: textSub, fontSize: 11, letterSpacing: 0.05),
                      ),
                    )
                  : ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final item = tasks[index];

                        final boxBorderColor =
                            isDark ? const Color(0xFFCCCCCC) : Colors.black;
                        final boxFillColor = item.isCompleted
                            ? (isDark ? Colors.white : Colors.black)
                            : Colors.transparent;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: protectedApplicationPersistenceAvailable
                                      ? () => ref
                                          .read(todoProvider.notifier)
                                          .toggleTask(item.id)
                                      : null,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 350),
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: boxFillColor,
                                          border: Border.all(
                                              color: boxBorderColor,
                                              width: 1.4),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Stack(
                                          alignment: Alignment.centerLeft,
                                          children: [
                                            Text(
                                              item.text,
                                              style: TextStyle(
                                                color: textMain,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: -0.01,
                                              ),
                                            ),
                                            TweenAnimationBuilder<double>(
                                              tween: Tween<double>(
                                                  begin: 0.0,
                                                  end: item.isCompleted
                                                      ? 1.0
                                                      : 0.0),
                                              duration: const Duration(
                                                  milliseconds: 600),
                                              curve: Curves.easeOutQuart,
                                              builder: (context, value, child) {
                                                return ClipRect(
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    widthFactor: value,
                                                    child: Text(
                                                      item.text,
                                                      style: TextStyle(
                                                        color: textSub,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: -0.01,
                                                        decoration:
                                                            TextDecoration
                                                                .lineThrough,
                                                        decorationColor:
                                                            textSub,
                                                        decorationThickness:
                                                            1.5,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: protectedApplicationPersistenceAvailable
                                    ? () => ref
                                        .read(todoProvider.notifier)
                                        .deleteTask(item.id)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(Icons.close,
                                      color: textSub, size: 16),
                                ),
                              )
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
