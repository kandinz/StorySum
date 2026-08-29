import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/player_state_provider.dart';
import '../../models/saved_audio_item.dart';
import '../../core/theme/app_theme.dart';

class StorySearchModal extends StatefulWidget {
  final bool asPage;
  final VoidCallback? onStoryOpened;

  const StorySearchModal({
    Key? key,
    this.asPage = false,
    this.onStoryOpened,
  }) : super(key: key);

  const StorySearchModal.page({
    Key? key,
    this.onStoryOpened,
  })  : asPage = true,
        super(key: key);

  static void show(BuildContext context, {VoidCallback? onStoryOpened}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StorySearchModal(onStoryOpened: onStoryOpened),
    );
  }

  @override
  State<StorySearchModal> createState() => _StorySearchModalState();
}

class _StorySearchModalState extends State<StorySearchModal> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isUrl(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('www.')) {
      return true;
    }
    final domainRegex = RegExp(r'^(?:https?:\/\/)?(?:[a-zA-Z0-9-]+\.)+(?:vn|com|net|org|vip|cc|info|biz|top|me|xyz|site|app|io|mobi)(?:\/.*)?$');
    return domainRegex.hasMatch(lower);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
      final text = data.text!.trim();
      setState(() {
        _searchController.text = text;
        _query = text;
      });
    }
  }

  void _confirmClearAll(BuildContext context, AppStateProvider appState, AppThemeColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Text(
              'Xóa toàn bộ lịch sử?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary),
            ),
          ],
        ),
        content: Text(
          'Hành động này sẽ xóa toàn bộ danh sách chương truyện đã lưu và các file âm thanh tương ứng khỏi thiết bị.',
          style: TextStyle(fontSize: 13, color: colors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            child: Text('Hủy', style: TextStyle(color: colors.textMuted)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Xóa tất cả'),
            onPressed: () {
              Navigator.pop(ctx);
              appState.clearAllSaved();
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteStory(BuildContext context, AppStateProvider appState, String storyTitle, AppThemeColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Xóa truyện khỏi lịch sử?',
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: colors.textPrimary),
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa toàn bộ các chương đã lưu của "$storyTitle"?',
          style: TextStyle(fontSize: 13, color: colors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            child: Text('Hủy', style: TextStyle(color: colors.textMuted)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Xóa truyện'),
            onPressed: () {
              Navigator.pop(ctx);
              appState.deleteSavedStory(storyTitle);
            },
          ),
        ],
      ),
    );
  }

  SavedAudioItem _getReadingChapter(List<SavedAudioItem> chapters, AppStateProvider appState, String storyTitle) {
    if (chapters.isEmpty) {
      return SavedAudioItem(
        id: '',
        title: 'Chương 1',
        storyTitle: storyTitle,
        chapterNumber: 1,
        audioPath: '',
      );
    }
    // 1. Nếu truyện đang phát/tải hiện tại trong appState
    if (appState.currentChapter != null &&
        appState.currentChapter!.storyTitle.trim().toLowerCase() == storyTitle.trim().toLowerCase()) {
      final currentNum = appState.currentChapter!.chapterNumber;
      for (final c in chapters) {
        if (c.chapterNumber == currentNum) return c;
      }
    }
    // 2. Nếu khớp lastPlayed của appState
    if (appState.lastPlayedStoryTitle != null &&
        appState.lastPlayedStoryTitle!.trim().toLowerCase() == storyTitle.trim().toLowerCase() &&
        appState.lastPlayedChapterNumber != null) {
      final lastNum = appState.lastPlayedChapterNumber!;
      for (final c in chapters) {
        if (c.chapterNumber == lastNum) return c;
      }
    }
    // 3. Tìm chapter có lastPlayedAt gần đây nhất
    SavedAudioItem? latestPlayed;
    for (final c in chapters) {
      if (c.lastPlayedAt != null) {
        if (latestPlayed == null || c.lastPlayedAt!.isAfter(latestPlayed.lastPlayedAt!)) {
          latestPlayed = c;
        }
      }
    }
    if (latestPlayed != null) return latestPlayed;

    // 4. Tìm chapter có tiến độ câu > 0
    for (final c in chapters) {
      if (c.lastPlayedSentenceIndex > 0 || c.lastPlayedSummaryIndex > 0 || c.lastPlayedContentIndex > 0) {
        return c;
      }
    }

    // 5. Mặc định là chương đầu danh sách
    return chapters.first;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final settings = context.watch<SettingsProvider>();
    final player = context.watch<PlayerStateProvider>();
    final colors = AppTheme.getColors(settings.appThemeMode, context);

    final isUrlInput = _isUrl(_query);

    // Gom nhóm danh sách mục đã lưu theo tên truyện
    final Map<String, List<SavedAudioItem>> groupedMap = {};
    for (final item in appState.savedAudios) {
      final storyKey = item.storyTitle.trim().isNotEmpty
          ? item.storyTitle.trim()
          : 'Truyện chưa đặt tên';
      groupedMap.putIfAbsent(storyKey, () => []).add(item);
    }

    // Sắp xếp các chương trong mỗi truyện theo thứ tự số chương tăng dần
    for (final key in groupedMap.keys) {
      groupedMap[key]!.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    }

    // Lọc theo từ khóa tìm kiếm
    final filteredStories = <String, List<SavedAudioItem>>{};
    final queryTrimmed = _query.toLowerCase().trim();

    if (queryTrimmed.isEmpty || isUrlInput) {
      filteredStories.addAll(groupedMap);
    } else {
      for (final entry in groupedMap.entries) {
        final storyMatches = entry.key.toLowerCase().contains(queryTrimmed);
        if (storyMatches) {
          filteredStories[entry.key] = entry.value;
        } else {
          final matchingChapters = entry.value.where((c) {
            return c.displayChapterTitle.toLowerCase().contains(queryTrimmed) ||
                c.title.toLowerCase().contains(queryTrimmed) ||
                c.chapterNumber.toString().contains(queryTrimmed);
          }).toList();
          if (matchingChapters.isNotEmpty) {
            filteredStories[entry.key] = entry.value;
          }
        }
      }
    }

    final totalStories = filteredStories.length;
    final totalChapters = filteredStories.values.fold<int>(0, (sum, list) => sum + list.length);

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thanh kéo modal (chỉ hiển thị khi không ở chế độ page)
        if (!widget.asPage) ...[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Header Kho Truyện
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.library_books_rounded, color: colors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Kho Truyện',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                if (totalStories > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$totalStories truyện • $totalChapters chương',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                if (appState.savedAudios.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 17),
                    label: const Text('Xóa hết', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _confirmClearAll(context, appState, colors),
                  ),
                if (!widget.asPage)
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
              ],
            ),
          ],
        ),
        Divider(color: colors.border, height: 16),

        // Nút Nhập File TXT / EPUB
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          width: double.infinity,
          height: 42,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.primary,
              side: BorderSide(color: colors.primary.withValues(alpha: 0.6), width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              backgroundColor: colors.primary.withValues(alpha: 0.06),
            ),
            icon: const Icon(Icons.upload_file_rounded, size: 20),
            label: const Text(
              'Nhập truyện từ File (.TXT, .EPUB, ...)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            onPressed: appState.isProcessing
                ? null
                : () async {
                    final success = await appState.importStoryFromFile(
                      settings: settings,
                      player: player,
                    );
                    if (success) {
                      if (!widget.asPage) {
                        Navigator.pop(context);
                      }
                      widget.onStoryOpened?.call();
                    }
                  },
          ),
        ),

        // Ô nhập tìm kiếm / Dán Link
        Container(
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isUrlInput ? colors.primary : colors.border,
              width: isUrlInput ? 1.5 : 1.0,
            ),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Tìm kiếm truyện hoặc Dán link (https://...)...',
              hintStyle: TextStyle(color: colors.textMuted, fontSize: 12.5),
              prefixIcon: Icon(
                isUrlInput ? Icons.link_rounded : Icons.search_rounded,
                size: 20,
                color: isUrlInput ? colors.primary : colors.textMuted,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_query.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear_rounded, size: 18, color: colors.textMuted),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  else
                    TextButton.icon(
                      icon: Icon(Icons.paste_rounded, size: 16, color: colors.primary),
                      label: Text(
                        'Dán',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.primary),
                      ),
                      onPressed: _pasteFromClipboard,
                    ),
                ],
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (val) {
              setState(() => _query = val);
            },
            onSubmitted: (val) async {
              if (val.trim().isNotEmpty) {
                if (_isUrl(val)) {
                  if (!widget.asPage) Navigator.pop(context);
                  await appState.loadFromUrl(val.trim(), settings: settings, player: player);
                  widget.onStoryOpened?.call();
                }
              }
            },
          ),
        ),
        const SizedBox(height: 12),

        // Nếu là URL -> Hiển thị Card Tải Link Trực Tiếp
        if (isUrlInput) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.primary.withValues(alpha: 0.4), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.public_rounded, color: colors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Phát hiện liên kết truyện hợp lệ',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _query.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text(
                      'Tải & Đọc truyện từ liên kết này',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      if (!widget.asPage) Navigator.pop(context);
                      await appState.loadFromUrl(_query.trim(), settings: settings, player: player);
                      widget.onStoryOpened?.call();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Tiêu đề danh sách
        Text(
          _query.isEmpty
              ? 'Danh sách truyện đã lưu:'
              : (isUrlInput
                  ? 'Hoặc chọn từ danh sách:'
                  : 'Kết quả tìm kiếm ($totalStories truyện):'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 8),

        // Danh sách truyện trong Kho truyện (chỉ chọn truyện, không chọn chương)
        Expanded(
          child: filteredStories.isEmpty
              ? SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_query.isNotEmpty) ...[
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 40,
                                  color: colors.textMuted.withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Không tìm thấy truyện phù hợp trong kho truyện.',
                                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      _buildLinkGuideCard(colors),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: filteredStories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final storyTitle = filteredStories.keys.elementAt(index);
                    final chapters = filteredStories[storyTitle]!;

                    return _buildStoryItemCard(
                      context: context,
                      storyTitle: storyTitle,
                      chapters: chapters,
                      appState: appState,
                      settings: settings,
                      player: player,
                      colors: colors,
                    );
                  },
                ),
        ),
      ],
    );

    if (widget.asPage) {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: column,
        ),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: colors.border, width: 1.2),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: column,
    );
  }

  Widget _buildStoryItemCard({
    required BuildContext context,
    required String storyTitle,
    required List<SavedAudioItem> chapters,
    required AppStateProvider appState,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required AppThemeColors colors,
  }) {
    final isCurrentlyOpenStory = appState.hasActiveChapter &&
        appState.currentChapter != null &&
        appState.currentChapter!.storyTitle.trim().toLowerCase() == storyTitle.trim().toLowerCase();

    final readingChapter = _getReadingChapter(chapters, appState, storyTitle);

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentlyOpenStory
              ? colors.primary.withValues(alpha: 0.6)
              : colors.border,
          width: isCurrentlyOpenStory ? 1.3 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (!widget.asPage) Navigator.pop(context);
            await appState.selectStory(storyTitle, settings: settings, player: player);
            widget.onStoryOpened?.call();
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // Icon truyện
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCurrentlyOpenStory
                        ? colors.primary.withValues(alpha: 0.15)
                        : colors.elevatedBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrentlyOpenStory ? colors.primary.withValues(alpha: 0.4) : colors.border,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.auto_stories_rounded,
                      color: isCurrentlyOpenStory ? colors.primary : colors.textMuted,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Thông tin truyện
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storyTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '${chapters.length} chương',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '•',
                            style: TextStyle(fontSize: 11, color: colors.textMuted),
                          ),
                          const SizedBox(width: 6),
                          if (isCurrentlyOpenStory) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Đang đọc: Chương ${readingChapter.chapterNumber}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ] else ...[
                            Text(
                              'Đọc lần cuối: Chương ${readingChapter.chapterNumber}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Nút Xóa truyện
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                  tooltip: 'Xóa toàn bộ truyện này',
                  onPressed: () => _confirmDeleteStory(context, appState, storyTitle, colors),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLinkGuideCard(AppThemeColors colors) {
    final sampleUrls = [
      'https://truyendichmienphi.com/truyen/quy-bi-chi-chu/chuong/1',
      'https://webnovel.vn/van-co-than-de/chuong-1/',
      'https://xtruyen.vn/truyen/tu-tien-ta-that-khong-co-muon-lam-liem-cho/chuong-178',
      'https://truyenfull.live/quy-bi-chi-chu/chuong-1/',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Hướng dẫn dán link truyện hợp lệ',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Để tải và đọc truyện từ mạng, bạn có thể dán đường dẫn (URL) dẫn trực tiếp đến một chương cụ thể của truyện.',
            style: TextStyle(fontSize: 12.5, color: colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            'Cấu trúc link hợp lệ:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.elevatedBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• https://<tên-web>/<tên-truyện>/chuong-<số-chương>/',
                  style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: colors.primary),
                ),
                const SizedBox(height: 3),
                Text(
                  '• https://<tên-web>/truyen/<tên-truyện>/chuong/<số-chương>',
                  style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: colors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Ví dụ link hợp lệ (Chạm để dán thử ngay):',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          ...sampleUrls.map((url) => InkWell(
                onTap: () {
                  setState(() {
                    _searchController.text = url;
                    _query = url;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_right_rounded, color: colors.primary, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          url,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: colors.textSecondary,
                            decoration: TextDecoration.underline,
                            decorationColor: colors.border,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.touch_app_rounded, color: colors.primary, size: 14),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
