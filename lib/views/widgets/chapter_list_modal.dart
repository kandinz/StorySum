import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/saved_audio_item.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/player_state_provider.dart';
import '../../providers/settings_provider.dart';

class ChapterListModal extends StatefulWidget {
  const ChapterListModal({Key? key}) : super(key: key);

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ChapterListModal(),
    );
  }

  @override
  State<ChapterListModal> createState() => _ChapterListModalState();
}

class _ChapterListModalState extends State<ChapterListModal> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<int> _expandedGroups = {};
  bool _hasInitializedExpansion = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Tính toán nhóm 100 chương (0: 1-100, 1: 101-200, 2: 201-300,...)
  int _getGroupIndex(int chapterNumber) {
    if (chapterNumber <= 0) return 0;
    return (chapterNumber - 1) ~/ 100;
  }

  String _getGroupLabel(int groupIndex) {
    final start = groupIndex * 100 + 1;
    final end = (groupIndex + 1) * 100;
    return 'Chương $start - $end';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final settings = context.watch<SettingsProvider>();
    final player = context.watch<PlayerStateProvider>();
    final colors = AppTheme.getColors(settings.appThemeMode, context);

    final storyTitle = appState.currentChapter?.storyTitle.trim().isNotEmpty == true
        ? appState.currentChapter!.storyTitle.trim()
        : (appState.lastPlayedStoryTitle?.trim().isNotEmpty == true
            ? appState.lastPlayedStoryTitle!.trim()
            : 'Truyện hiện tại');

    // Lọc danh sách chương của truyện hiện tại
    final currentStoryAudios = appState.savedAudios
        .where((a) => a.storyTitle.trim().toLowerCase() == storyTitle.toLowerCase())
        .toList();

    // Sắp xếp số chương tăng dần (1, 2, 3...)
    currentStoryAudios.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));

    final currentChapterNum = appState.currentChapter?.chapterNumber ??
        int.tryParse(appState.chapterController.text.trim()) ??
        1;

    // Tự động mở rộng nhóm chứa chương đang đọc trong lần đầu dựng giao diện
    if (!_hasInitializedExpansion) {
      final currentGroup = _getGroupIndex(currentChapterNum);
      _expandedGroups.add(currentGroup);
      _hasInitializedExpansion = true;
    }

    // Lọc theo từ khóa tìm kiếm
    final query = _searchQuery.trim().toLowerCase();
    final List<SavedAudioItem> filteredAudios;
    if (query.isEmpty) {
      filteredAudios = currentStoryAudios;
    } else {
      filteredAudios = currentStoryAudios.where((item) {
        final numMatch = item.chapterNumber.toString().contains(query);
        final titleMatch = item.title.toLowerCase().contains(query);
        final displayTitleMatch = item.displayChapterTitle.toLowerCase().contains(query);
        return numMatch || titleMatch || displayTitleMatch;
      }).toList();
    }

    // Gom nhóm theo 100 chương
    final Map<int, List<SavedAudioItem>> groupedChapters = {};
    for (final item in filteredAudios) {
      final groupIdx = _getGroupIndex(item.chapterNumber);
      groupedChapters.putIfAbsent(groupIdx, () => []).add(item);
    }

    final sortedGroupKeys = groupedChapters.keys.toList()..sort();

    final isCrawlingThisStory = appState.isBackgroundCrawling &&
        appState.bgCrawlStoryTitle?.trim().toLowerCase() == storyTitle.toLowerCase();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: colors.border, width: 1.2),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thanh kéo modal
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
          const SizedBox(height: 10),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.format_list_bulleted_rounded, color: colors.primary, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            storyTitle,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${currentStoryAudios.length} chương đã lưu • Đang đọc: Chương $currentChapterNum',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          // Status bar tải ngầm nếu đang chạy
          if (isCrawlingThisStory) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đang tải ngầm: Chương ${appState.bgCrawlCurrentChapter} (Đã nạp ${appState.bgCrawlSuccessCount} chương)...',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: colors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => appState.stopBackgroundCrawl(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Dừng',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Ô tìm kiếm chương
          Container(
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm số chương hoặc tên chương...',
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: colors.textMuted),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: 16, color: colors.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: 10),

          // Danh sách nhóm 100 chương
          Expanded(
            child: currentStoryAudios.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_rounded, size: 40, color: colors.textMuted.withValues(alpha: 0.4)),
                        const SizedBox(height: 8),
                        Text(
                          'Chưa có danh sách chương nào được lưu cho truyện này.',
                          style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                        ),
                      ],
                    ),
                  )
                : filteredAudios.isEmpty
                    ? Center(
                        child: Text(
                          'Không tìm thấy chương phù hợp với từ khóa.',
                          style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: sortedGroupKeys.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, index) {
                          final groupKey = sortedGroupKeys[index];
                          final groupItems = groupedChapters[groupKey]!;
                          final isExpanded = _searchQuery.isNotEmpty || _expandedGroups.contains(groupKey);
                          final containsCurrent = groupItems.any((c) => c.chapterNumber == currentChapterNum);

                          return _buildChapterGroupCard(
                            context: context,
                            groupIndex: groupKey,
                            chapters: groupItems,
                            isExpanded: isExpanded,
                            containsCurrent: containsCurrent,
                            currentChapterNum: currentChapterNum,
                            appState: appState,
                            settings: settings,
                            player: player,
                            colors: colors,
                            onToggle: () {
                              setState(() {
                                if (_expandedGroups.contains(groupKey)) {
                                  _expandedGroups.remove(groupKey);
                                } else {
                                  _expandedGroups.add(groupKey);
                                }
                              });
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterGroupCard({
    required BuildContext context,
    required int groupIndex,
    required List<SavedAudioItem> chapters,
    required bool isExpanded,
    required bool containsCurrent,
    required int currentChapterNum,
    required AppStateProvider appState,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required AppThemeColors colors,
    required VoidCallback onToggle,
  }) {
    final groupTitle = _getGroupLabel(groupIndex);

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: containsCurrent ? colors.primary.withValues(alpha: 0.5) : colors.border,
          width: containsCurrent ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header nhóm 100 chương
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    containsCurrent ? Icons.bookmark_rounded : Icons.folder_rounded,
                    color: containsCurrent ? colors.primary : colors.textMuted,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          groupTitle,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: containsCurrent ? colors.primary : colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: colors.elevatedBackground,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${chapters.length} chương',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: colors.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Danh sách các chương con bên trong nhóm
          if (isExpanded) ...[
            Divider(color: colors.border.withValues(alpha: 0.4), height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: chapters.length,
              separatorBuilder: (_, __) => Divider(
                color: colors.border.withValues(alpha: 0.2),
                height: 1,
                indent: 12,
                endIndent: 12,
              ),
              itemBuilder: (ctx, idx) {
                final chapter = chapters[idx];
                final isCurrent = chapter.chapterNumber == currentChapterNum;

                return InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    await appState.changeToChapter(
                      chapter.chapterNumber,
                      settings: settings,
                      player: player,
                    );
                  },
                  child: Container(
                    color: isCurrent ? colors.primary.withValues(alpha: 0.08) : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                chapter.title.isNotEmpty ? chapter.title : 'Chương ${chapter.chapterNumber}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                  color: isCurrent ? colors.primary : colors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (chapter.content != null && chapter.content!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Đã tải sẵn • ${chapter.content!.split(RegExp(r'\s+')).length} từ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isCurrent) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Đang đọc',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ] else ...[
                          Icon(Icons.chevron_right_rounded, size: 16, color: colors.textMuted),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
