import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/database.dart';
import '../main.dart';

class IdeaInboxScreen extends ConsumerStatefulWidget {
  const IdeaInboxScreen({super.key});

  @override
  ConsumerState<IdeaInboxScreen> createState() => _IdeaInboxScreenState();
}

class _IdeaInboxScreenState extends ConsumerState<IdeaInboxScreen> {
  final TextEditingController _inboxController = TextEditingController();

  void _commitEntry() {
    final String text = _inboxController.text.trim();
    if (text.isEmpty) return;

    // Detect if the user input is a standalone web URL
    final Uri? parsedUri = Uri.tryParse(text);
    final bool isUrl = parsedUri != null && (parsedUri.isScheme('HTTP') || parsedUri.isScheme('HTTPS'));

    if (isUrl) {
      ref.read(localDatabaseProvider.notifier).insertMultipleItems([text], 'web_dump');
    } else {
      ref.read(localDatabaseProvider.notifier).insertMultipleItems([text], 'concept');
    }

    _inboxController.clear();
  }

  Future<void> _navigateToWebsite(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _inboxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final allItems = ref.watch(localDatabaseProvider);

    // Grabs both raw text concepts and website dumps for this vault
    final inboxItems = allItems.where((e) => e.type == 'concept' || e.type == 'web_dump').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    final ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final blockBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F5);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'IDEA INBOX',
            style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
          ),
          const SizedBox(height: 16),

          // INPUT ROW TERMINAL
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inboxController,
                  style: TextStyle(color: textMain, fontSize: 13),
                  cursorColor: textMain,
                  decoration: InputDecoration(
                    hintText: 'Paste website URL or dump raw text...',
                    hintStyle: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w400),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ruleBorder, width: 0.8)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: textMain, width: 1.0)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _commitEntry,
                icon: Icon(Icons.add, color: textMain, size: 22),
                splashRadius: 20,
              ),
            ],
          ),

          const SizedBox(height: 20),
          Divider(color: ruleBorder, height: 1, thickness: 0.8),
          const SizedBox(height: 16),

          // RENDER VAULT LIST
          Expanded(
            child: inboxItems.isEmpty
                ? Center(
              child: Text(
                'INBOX COMPLETELY VACANT',
                style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05),
              ),
            )
                : ListView.builder(
              itemCount: inboxItems.length,
              itemBuilder: (context, index) {
                final item = inboxItems[index];

                // 1. WEBSITE DUMP LAYOUT RENDERING
                if (item.type == 'web_dump') {
                  final String urlString = item.content;
                  final String displayDomain = Uri.tryParse(urlString)?.host.toUpperCase() ?? 'EXTERNAL LINK';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 16:9 Structural Aspect Ratio Card
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              color: blockBg,
                              border: Border.all(color: ruleBorder, width: 0.8),
                            ),
                            child: Stack(
                              children: [
                                // Showcase Metadata Center Text
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      displayDomain,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                                    ),
                                  ),
                                ),
                                // Bottom-Left Redirect Arrow Control
                                Positioned(
                                  left: 0,
                                  bottom: 0,
                                  child: InkWell(
                                    onTap: () => _navigateToWebsite(urlString),
                                    child: Container(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Icon(
                                        Icons.north_east_rounded,
                                        color: textMain,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                // Top-Right Contextual Trash Purge Action
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton(
                                    onPressed: () => ref.read(localDatabaseProvider.notifier).deleteItem(item.id),
                                    icon: Icon(Icons.delete_outline_rounded, color: textSub, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Clean Raw URL String printed underneath the card wrapper
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Text(
                            urlString,
                            style: TextStyle(color: textSub, fontSize: 11, letterSpacing: -0.01),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // 2. STANDARD TEXT CONCEPT VAULT RENDERING
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: blockBg,
                    border: Border.all(color: ruleBorder, width: 0.8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.content,
                          style: TextStyle(color: textMain, fontSize: 13, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => ref.read(localDatabaseProvider.notifier).deleteItem(item.id),
                        child: Icon(Icons.delete_outline_rounded, color: textSub, size: 20),
                      )
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}