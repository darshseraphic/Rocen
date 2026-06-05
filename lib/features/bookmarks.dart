import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../main.dart';

// --- 1. DATA MODEL ---
class TodoItem {
  final String id;
  final String text;
  final bool isCompleted;

  TodoItem({
    required this.id,
    required this.text,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'text': text,
    'isCompleted': isCompleted,
  };

  factory TodoItem.fromMap(Map<String, dynamic> map) => TodoItem(
    id: map['id'] ?? '',
    text: map['text'] ?? '',
    isCompleted: map['isCompleted'] ?? false,
  );

  TodoItem copyWith({String? id, String? text, bool? isCompleted}) {
    return TodoItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

// --- 2. STATE NOTIFIER ---
class TodoNotifier extends Notifier<List<TodoItem>> {
  static const String _boxName = 'rocen_todos_box';

  @override
  List<TodoItem> build() {
    _initAndLoad();
    return [];
  }

  Future<void> _initAndLoad() async {
    final box = await Hive.openBox(_boxName);
    final List<dynamic>? storedRaw = box.get('tasks');

    if (storedRaw != null && storedRaw.isNotEmpty) {
      state = storedRaw
          .map((item) => TodoItem.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    }
  }

  Future<void> addTask(String text) async {
    if (text.trim().isEmpty) return;

    final newItem = TodoItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text.trim(),
    );

    state = [newItem, ...state];
    await _saveToDisk();
  }

  Future<void> toggleTask(String id) async {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(isCompleted: !item.isCompleted);
      }
      return item;
    }).toList();
    await _saveToDisk();
  }

  Future<void> deleteTask(String id) async {
    state = state.where((item) => item.id != id).toList();
    await _saveToDisk();
  }

  Future<void> _saveToDisk() async {
    final box = Hive.box(_boxName);
    await box.put('tasks', state.map((e) => e.toMap()).toList());
  }
}

final todoProvider = NotifierProvider<TodoNotifier, List<TodoItem>>(TodoNotifier.new);

// --- 3. UI SCREEN ---
class BookmarksScreen extends ConsumerStatefulWidget {
  const BookmarksScreen({super.key});

  @override
  ConsumerState<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends ConsumerState<BookmarksScreen> {
  final TextEditingController _taskController = TextEditingController();

  void _submitTask() {
    ref.read(todoProvider.notifier).addTask(_taskController.text);
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
    final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final containerBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEEEEEE);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BOOKMARKS',
            style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
          ),
          const SizedBox(height: 16),

          // TASK INPUT BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: containerBg,
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskController,
                    style: TextStyle(color: textMain, fontSize: 13),
                    cursorColor: textMain,
                    decoration: InputDecoration(
                      hintText: 'ADD NEW TASK...',
                      hintStyle: TextStyle(color: textSub, fontSize: 12, letterSpacing: 0.05),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _submitTask(),
                  ),
                ),
                // INCREASED ADD BUTTON SIZE
                GestureDetector(
                  onTap: _submitTask,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(
                      '+',
                      style: TextStyle(
                        color: textMain,
                        fontSize: 22, // Size bumped up from 16 to be prominently noticed
                        fontWeight: FontWeight.w700, // Thicker geometry alignment
                        height: 1.0,
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),

          Divider(color: borderColor, height: 32, thickness: 0.8),

          // TASK LIST
          Expanded(
            child: tasks.isEmpty
                ? Center(
              child: Text(
                'NO PENDING TASKS',
                style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05),
              ),
            )
                : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final item = tasks[index];

                final boxBorderColor = isDark ? const Color(0xFFCCCCCC) : Colors.black;
                final boxFillColor = item.isCompleted
                    ? (isDark ? Colors.white : Colors.black)
                    : Colors.transparent;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 18.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // CUSTOM ANIMATED SQUARE TOGGLE (Slightly adjusted dimensions to look balanced alongside larger text)
                      GestureDetector(
                        onTap: () => ref.read(todoProvider.notifier).toggleTask(item.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: boxFillColor,
                            border: Border.all(color: boxBorderColor, width: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // TASK TITLE TEXT WITH ENHANCED FONT SIZING
                      Expanded(
                        child: GestureDetector(
                          onTap: () => ref.read(todoProvider.notifier).toggleTask(item.id),
                          child: IntrinsicWidth(
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    color: item.isCompleted ? textSub : textMain,
                                    fontSize: 14, // Matches 'BOOKMARKS' title text size exactly
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.01,
                                  ),
                                  child: Text(item.text),
                                ),
                                // Custom horizontal strike engine
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: AnimatedFractionallySizedBox(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeOutCubic,
                                      alignment: Alignment.centerLeft,
                                      widthFactor: item.isCompleted ? 1.0 : 0.0,
                                      child: Container(
                                        height: 1.5, // Thickened slightly to cut across larger characters seamlessly
                                        color: textSub,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ROW ITEM TERMINATOR
                      GestureDetector(
                        onTap: () => ref.read(todoProvider.notifier).deleteTask(item.id),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(Icons.close, color: textSub, size: 16),
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
    );
  }
}