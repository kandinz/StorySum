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

  const StorySearchModal({Key? key, this.asPage = false}) : super(key: key);

  const StorySearchModal.page({Key? key}) : asPage = true, super(key: key);

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const StorySearchModal(),
    );
  }

  @override
  State<StorySearchModal> createState() => _StorySearchModalState();
}

class _StorySearchModalState extends State<StorySearchModal> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';
  final Set<String> _expandedStories = {};

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

  void _confirmDeleteChapter(BuildContext context, AppStateProvider appState, SavedAudioItem item, AppThemeColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Xóa chương ${item.chapterNumber}?',
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: colors.textPrimary),
        ),
        content: Text(
          'Bạn có chắc muốn xóa dữ liệu và âm thanh của chương ${item.chapterNumber} truyện "${item.storyTitle}"?',
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
            child: const Text('Xóa chương'),
            onPressed: () {
              Navigator.pop(ctx);
              appState.deleteSavedChapter(item.id);
            },
          ),
        ],
      ),
    );
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

    // Sắp xếp các chương trong mỗi truyện theo thứ tự số chương giảm dần (chương mới nhất ở trên cùng)
    for (final key in groupedMap.keys) {
      groupedMap[key]!.sort((a, b) => b.chapterNumber.compareTo(a.chapterNumber));
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
            filteredStories[entry.key] = matchingChapters;
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

        // Header Search Modal
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.search_rounded, color: colors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Tìm Kiếm',
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
              hintText: 'Dán URL chương truyện (VD: https://.../chuong-1)...',
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
                }
              }
            },
          ),
        ),
        const SizedBox(height: 12),

        // Kết quả: 1. Nếu là URL -> Hiển thị Card Tải Link Trực Tiếp
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
                      'Tải truyện từ liên kết này',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      if (!widget.asPage) Navigator.pop(context);
                      await appState.loadFromUrl(_query.trim(), settings: settings, player: player);
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
              ? 'Lịch sử'
              : (isUrlInput
                  ? 'Hoặc chọn từ lịch sử:'
                  : 'Kết quả tìm kiếm ($totalStories truyện • $totalChapters chương):'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 6),

        // Danh sách nhóm truyện trong Lịch sử hoặc Hướng dẫn cấu trúc link
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
                                  'Không tìm thấy truyện phù hợp trong lịch sử.',
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
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, index) {
                    final storyTitle = filteredStories.keys.elementAt(index);
                    final chapters = filteredStories[storyTitle]!;
                    final isExpanded = _query.isNotEmpty || _expandedStories.contains(storyTitle);

                    return _buildStoryGroupCard(
                      context: context,
                      storyTitle: storyTitle,
                      chapters: chapters,
                      isExpanded: isExpanded,
                      appState: appState,
                      settings: settings,
                      player: player,
                      colors: colors,
                      onToggleExpand: () {
                        setState(() {
                          if (_expandedStories.contains(storyTitle)) {
                            _expandedStories.remove(storyTitle);
                          } else {
                            _expandedStories.add(storyTitle);
                          }
                        });
                      },
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
            'Để tải và đọc truyện, bạn cần dán đường dẫn (URL) dẫn trực tiếp đến một chương cụ thể của truyện.',
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

  String _getChapterSentenceProgress(SavedAudioItem chapter, AppStateProvider appState) {
    final isCurrentActive = appState.currentChapter != null &&
        appState.currentChapter!.storyTitle.trim().toLowerCase() == chapter.storyTitle.trim().toLowerCase() &&
        appState.currentChapter!.chapterNumber == chapter.chapterNumber;

    int sTotal = chapter.summarySentenceCount;
    int cTotal = chapter.contentSentenceCount;
    int sIdx = chapter.lastPlayedSummaryIndex;
    int cIdx = chapter.lastPlayedContentIndex;
    String source = chapter.lastPlayedSource;
    bool sPlayed = chapter.lastPlayedAt != null || sIdx > 0;
    bool cPlayed = chapter.lastPlayedAt != null || cIdx > 0;

    if (isCurrentActive) {
      if (appState.summarySentences.isNotEmpty) sTotal = appState.summarySentences.length;
      if (appState.contentSentences.isNotEmpty) cTotal = appState.contentSentences.length;
      sIdx = appState.currentSummarySentenceIndex;
      cIdx = appState.currentContentSentenceIndex;
      source = appState.activeAudioSource.name;

      if (appState.activeSentenceIndex != null) {
        if (appState.activeAudioSource == AudioSourceType.summary) {
          sIdx = appState.activeSentenceIndex!;
          sPlayed = true;
        } else {
          cIdx = appState.activeSentenceIndex!;
          cPlayed = true;
        }
      }
    }

    int calcProgress(int index, int total, bool isPlayed) {
      if (total <= 0) return 0;
      if (!isPlayed || index < 0) return 0;
      if (index >= total) return total;
      return index + 1;
    }

    final sCur = calcProgress(sIdx, sTotal, sPlayed);
    final cCur = calcProgress(cIdx, cTotal, cPlayed);

    if (sTotal > 0 && cTotal > 0) {
      if (source == 'content') {
        return 'Nội dung: $cCur/$cTotal • Tóm tắt: $sCur/$sTotal';
      } else {
        return 'Tóm tắt: $sCur/$sTotal • Nội dung: $cCur/$cTotal';
      }
    } else if (sTotal > 0) {
      return 'Tóm tắt: $sCur/$sTotal câu';
    } else if (cTotal > 0) {
      return 'Nội dung: $cCur/$cTotal câu';
    }
    return '';
  }

  Widget _buildStoryGroupCard({
    required BuildContext context,
    required String storyTitle,
    required List<SavedAudioItem> chapters,
    required bool isExpanded,
    required AppStateProvider appState,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required AppThemeColors colors,
    required VoidCallback onToggleExpand,
  }) {
    final isCurrentlyOpenStory = appState.hasActiveChapter &&
        appState.currentChapter != null &&
        appState.currentChapter!.storyTitle.trim().toLowerCase() == storyTitle.trim().toLowerCase();

    final readingChapter = _getReadingChapter(chapters, appState, storyTitle);

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrentlyOpenStory
              ? colors.primary.withValues(alpha: 0.6)
              : colors.border,
          width: isCurrentlyOpenStory ? 1.3 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header nhóm truyện
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    color: isCurrentlyOpenStory ? colors.primary : colors.textMuted,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          storyTitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        if (isCurrentlyOpenStory)
                          Row(
                            children: [
                              Text(
                                '${chapters.length} chương',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.textMuted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '•',
                                style: TextStyle(fontSize: 10, color: colors.primary),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Đang đọc',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            '${chapters.length} chương đã lưu',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 15),
                    tooltip: 'Xóa toàn bộ truyện này',
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(),
                    onPressed: () => _confirmDeleteStory(context, appState, storyTitle, colors),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: colors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // Danh sách các chương của truyện (khi mở rộng)
          if (isExpanded) ...[
            Divider(color: colors.border.withValues(alpha: 0.4), height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: chapters.length,
              separatorBuilder: (_, __) => Divider(
                color: colors.border.withValues(alpha: 0.25),
                height: 1,
                indent: 10,
                endIndent: 10,
              ),
              itemBuilder: (ctx, idx) {
                final chapter = chapters[idx];
                final isCurrentlyOpenChapter = isCurrentlyOpenStory &&
                    appState.currentChapter!.chapterNumber == chapter.chapterNumber;
                final isLastReadOfThisStory = !isCurrentlyOpenStory &&
                    (chapter.chapterNumber == readingChapter.chapterNumber);
                final progressText = _getChapterSentenceProgress(chapter, appState);

                return InkWell(
                  onTap: () async {
                    if (!widget.asPage) Navigator.pop(context);
                    await appState.loadSavedChapter(
                      chapter,
                      settings: settings,
                      player: player,
                      focusLastPlayed: true,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                                  fontSize: 11.5,
                                  color: isCurrentlyOpenChapter
                                      ? colors.primary
                                      : colors.textPrimary,
                                  fontWeight: (isCurrentlyOpenChapter || isLastReadOfThisStory)
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (progressText.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(
                                  progressText,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: isCurrentlyOpenChapter
                                        ? colors.primary.withValues(alpha: 0.85)
                                        : colors.textMuted,
                                    fontWeight: FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (isCurrentlyOpenChapter) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'Đang đọc',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: colors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ] else if (isLastReadOfThisStory) ...[
                          Tooltip(
                            message: 'Chương đọc lần cuối',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: colors.primary.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bookmark_rounded, size: 10.5, color: colors.primary),
                                  const SizedBox(width: 2.5),
                                  Text(
                                    'Đọc lần cuối',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, size: 14, color: colors.textMuted),
                          tooltip: 'Xóa chương này',
                          padding: const EdgeInsets.all(2),
                          constraints: const BoxConstraints(),
                          onPressed: () => _confirmDeleteChapter(context, appState, chapter, colors),
                        ),
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
