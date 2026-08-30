import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../models/saved_audio_item.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/player_state_provider.dart';
import '../../providers/settings_provider.dart';

class ChapterListModal extends StatefulWidget {
  final VoidCallback? onNavigateToLibrary;

  const ChapterListModal({
    Key? key,
    this.onNavigateToLibrary,
  }) : super(key: key);

  static void show(BuildContext context, {VoidCallback? onNavigateToLibrary}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChapterListModal(onNavigateToLibrary: onNavigateToLibrary),
    );
  }

  @override
  State<ChapterListModal> createState() => _ChapterListModalState();
}

class _ChapterListModalState extends State<ChapterListModal> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  String _searchQuery = '';
  bool _onlyBookmarked = false;
  final Set<int> _expandedGroups = {};
  bool _hasInitializedExpansion = false;
  bool _hasInitializedUrl = false;
  bool _isCheckingUrl = false;

  @override
  void dispose() {
    _searchController.dispose();
    _urlController.dispose();
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

    final bool hasValidStory = appState.hasActiveChapter ||
        (appState.lastPlayedStoryTitle != null && appState.lastPlayedStoryTitle!.trim().isNotEmpty);
    final String storyTitle = (appState.currentChapter?.storyTitle.trim().isNotEmpty == true)
        ? appState.currentChapter!.storyTitle.trim()
        : ((appState.lastPlayedStoryTitle != null && appState.lastPlayedStoryTitle!.trim().isNotEmpty)
            ? appState.lastPlayedStoryTitle!.trim()
            : 'Chưa chọn truyện');
    final bool isStorySelected = hasValidStory && storyTitle != 'Chưa chọn truyện';

    // Lọc và hợp nhất danh sách chương của truyện hiện tại từ cả savedAudios và historyChapters
    final Map<int, SavedAudioItem> chapterMap = {};
    if (isStorySelected) {
      for (final item in appState.savedAudios) {
        if (AppStateProvider.isSameStory(item.storyTitle, storyTitle)) {
          chapterMap[item.chapterNumber] = item;
        }
      }
      for (final chap in appState.historyChapters) {
        if (AppStateProvider.isSameStory(chap.storyTitle, storyTitle) && !chapterMap.containsKey(chap.chapterNumber)) {
          chapterMap[chap.chapterNumber] = SavedAudioItem(
            id: 'audio_${chap.id}',
            title: chap.chapterTitle,
            storyTitle: storyTitle,
            chapterNumber: chap.chapterNumber,
            audioPath: '',
            content: chap.content,
            chapterId: chap.id,
            voiceUsed: settings.currentVoice.name,
          );
        }
      }
    }

    final currentStoryAudios = chapterMap.values.toList()
      ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));

    // Khởi tạo URL truyện: Nếu chưa chọn truyện thì để trống ô nhập link
    if (!_hasInitializedUrl) {
      String initialUrl = '';
      if (isStorySelected) {
        if (appState.currentChapter?.sourceUrl.isNotEmpty == true &&
            !appState.currentChapter!.sourceUrl.startsWith('file://')) {
          initialUrl = appState.currentChapter!.sourceUrl;
        } else {
          for (final chap in appState.historyChapters) {
            if (AppStateProvider.isSameStory(chap.storyTitle, storyTitle) &&
                chap.sourceUrl.isNotEmpty &&
                !chap.sourceUrl.startsWith('file://')) {
              initialUrl = chap.sourceUrl;
              break;
            }
          }
        }
      }
      _urlController.text = initialUrl;
      _hasInitializedUrl = true;
    }

    final currentChapterNum = appState.currentChapter?.chapterNumber ??
        int.tryParse(appState.chapterController.text.trim()) ??
        1;

    // Tự động mở rộng nhóm chứa chương đang đọc trong lần đầu dựng giao diện
    if (!_hasInitializedExpansion) {
      final currentGroup = _getGroupIndex(currentChapterNum);
      _expandedGroups.add(currentGroup);
      _hasInitializedExpansion = true;
    }

    // Lọc theo từ khóa tìm kiếm & Bookmark
    final query = _searchQuery.trim().toLowerCase();
    List<SavedAudioItem> filteredAudios = currentStoryAudios;

    if (_onlyBookmarked) {
      filteredAudios = filteredAudios.where((item) {
        return appState.isChapterBookmarked(item.chapterNumber);
      }).toList();
    }

    if (query.isNotEmpty) {
      filteredAudios = filteredAudios.where((item) {
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
                          if (isStorySelected) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Chương mới nhất: ${currentStoryAudios.isNotEmpty ? currentStoryAudios.last.chapterNumber : currentChapterNum} • Chương đang đọc: $currentChapterNum',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
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

          // Status bar tải nếu đang chạy
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
                      'Đang tải: Chương ${appState.bgCrawlCurrentChapter} (Đã nạp ${appState.bgCrawlSuccessCount} chương)...',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: colors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Ô nhập Link truyện & Nút Tải chương mới (để tiếp tục tải các chương còn thiếu)
          Container(
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 18, color: isStorySelected ? colors.primary : colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    enabled: isStorySelected,
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: isStorySelected
                          ? 'Dán link truyện để tải thêm chương...'
                          : 'Chọn một truyện để kích hoạt tải thêm chương',
                      hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCrawlingThisStory ? Colors.redAccent : colors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: colors.border.withValues(alpha: 0.5),
                      disabledForegroundColor: colors.textMuted,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: _isCheckingUrl
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            isCrawlingThisStory ? Icons.stop_rounded : Icons.download_rounded,
                            size: 15,
                          ),
                    label: Text(
                      _isCheckingUrl
                          ? 'Đang kiểm tra...'
                          : isCrawlingThisStory
                              ? 'Dừng tải'
                              : 'Tải chương mới',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: (_isCheckingUrl || (!isStorySelected && !isCrawlingThisStory))
                        ? null
                        : () async {
                            if (isCrawlingThisStory) {
                              appState.stopBackgroundCrawl();
                              return;
                            }

                            final inputUrl = _urlController.text.trim();
                            if (inputUrl.isEmpty) {
                              AppToast.showWarning(
                                context,
                                'Vui lòng nhập link truyện hợp lệ!',
                              );
                              return;
                            }

                            if (!isStorySelected) {
                              AppToast.showWarning(
                                context,
                                'Vui lòng chọn hoặc mở một truyện trước khi tải chương mới!',
                              );
                              return;
                            }

                            // Ưu tiên tải các chương lớn hơn chương đang đọc trước (currentChapterNum + 1)
                            int nextStartChapter = currentChapterNum + 1;
                            if (currentStoryAudios.isNotEmpty) {
                              final existingNums = currentStoryAudios.map((c) => c.chapterNumber).toSet();
                              if (!existingNums.contains(currentChapterNum)) {
                                nextStartChapter = currentChapterNum;
                              }
                            }

                            // Kiểm tra xem tên truyện trong URL có khớp với truyện đang chọn không
                            setState(() => _isCheckingUrl = true);
                            try {
                              final probedChapter = await appState.crawlerService.fetchChapter(
                                baseUrl: inputUrl,
                                chapterNumber: nextStartChapter,
                              );
                              final crawledTitle = probedChapter.storyTitle.trim();
                              final targetTitle = storyTitle.trim();

                              if (!AppStateProvider.isSameStory(crawledTitle, targetTitle)) {
                                if (context.mounted) {
                                  setState(() => _isCheckingUrl = false);
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: colors.cardBackground,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      title: Row(
                                        children: const [
                                          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 24),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Tên Truyện Không Khớp',
                                              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Link bạn vừa nhập thuộc về truyện:',
                                            style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            crawledTitle.isNotEmpty ? '• $crawledTitle' : '• (Không xác định)',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colors.primary),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            'Truyện đang chọn là:',
                                            style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '• $targetTitle',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colors.textPrimary),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Ứng dụng đã dừng tải để tránh nhầm lẫn hoặc ghi đè sai chương.',
                                            style: TextStyle(fontSize: 12, color: colors.textMuted, height: 1.4),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          child: const Text('Đã hiểu', style: TextStyle(fontWeight: FontWeight.bold)),
                                          onPressed: () => Navigator.pop(ctx),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return;
                              }

                              if (context.mounted) {
                                setState(() => _isCheckingUrl = false);
                                AppToast.showSuccess(
                                  context,
                                  'Bắt đầu tải các chương tiếp theo của truyện "$storyTitle"...',
                                  title: 'Đang Tải Truyện Ngầm',
                                );
                              }

                              // Tên truyện khớp -> Bắt đầu tiến trình tải ngầm toàn bộ truyện
                              appState.startBackgroundStoryCrawl(
                                baseUrl: inputUrl,
                                storyTitle: storyTitle,
                                settings: settings,
                                startChapter: nextStartChapter,
                              );
                            } catch (e) {
                              if (context.mounted) {
                                setState(() => _isCheckingUrl = false);
                                AppToast.showError(
                                  context,
                                  'Không thể kiểm tra link truyện: $e',
                                  duration: const Duration(seconds: 4),
                                );
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Ô tìm kiếm chương
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _onlyBookmarked ? colors.primary : colors.border,
                width: _onlyBookmarked ? 1.4 : 1.0,
              ),
            ),
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: _onlyBookmarked
                    ? 'Tìm trong chương đã đánh dấu...'
                    : 'Tìm kiếm số chương hoặc tên chương...',
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: _searchQuery.isNotEmpty ? colors.primary : colors.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 44),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.cancel_rounded, size: 18, color: colors.textMuted),
                        splashRadius: 18,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                    Tooltip(
                      message: _onlyBookmarked
                          ? 'Đang lọc chương đã đánh dấu (Chạm để hiện tất cả)'
                          : 'Chỉ hiện chương đã đánh dấu',
                      child: IconButton(
                        icon: Icon(
                          _onlyBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          size: 20,
                          color: _onlyBookmarked ? Colors.amber.shade600 : colors.textMuted,
                        ),
                        splashRadius: 18,
                        constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() {
                            _onlyBookmarked = !_onlyBookmarked;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: 10),

          // Danh sách nhóm 100 chương
          Expanded(
            child: currentStoryAudios.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.local_library_rounded,
                              size: 40,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            !isStorySelected
                                ? 'Chưa chọn truyện nào'
                                : 'Chưa có danh sách chương',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            !isStorySelected
                                ? 'Vui lòng mở kho truyện để chọn một tác phẩm có sẵn hoặc nhập truyện mới từ tệp / link.'
                                : 'Chưa có danh sách chương nào được lưu cho truyện này.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onNavigateToLibrary?.call();
                            },
                            icon: const Icon(Icons.library_books_rounded, size: 18),
                            label: const Text(
                              'Chuyển Đến Kho Truyện',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : filteredAudios.isEmpty
                    ? Center(
                        child: Text(
                          _onlyBookmarked
                              ? 'Chưa có chương nào được đánh dấu bookmark trong truyện này.'
                              : 'Không tìm thấy chương phù hợp với từ khóa.',
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
                          final isExpanded = _onlyBookmarked || _searchQuery.isNotEmpty || _expandedGroups.contains(groupKey);
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
                final isBookmarked = appState.isChapterBookmarked(chapter.chapterNumber);

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
                          child: Text(
                            chapter.title.isNotEmpty ? chapter.title : 'Chương ${chapter.chapterNumber}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                              color: isCurrent ? colors.primary : colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isBookmarked) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              Icons.bookmark_rounded,
                              size: 17,
                              color: Colors.amber.shade600,
                            ),
                            tooltip: 'Bỏ đánh dấu',
                            splashRadius: 14,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              appState.toggleBookmark(
                                chapter.storyTitle,
                                chapter.chapterNumber,
                                chapter.title,
                              );
                            },
                          ),
                        ],
                        if (isCurrent) ...[
                          const SizedBox(width: 4),
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
                        ] else if (!isBookmarked) ...[
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
