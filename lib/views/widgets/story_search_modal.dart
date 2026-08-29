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

  static const List<String> sampleUrls = [
    'https://mtruyen.net/truyen/tien-nghich/chuong-1',
    'https://truyendichmienphi.com/truyen/quy-bi-chi-chu/chuong/1',
    'https://webnovel.vn/van-co-than-de/chuong-1/',
    'https://xtruyen.vn/truyen/tu-tien-ta-that-khong-co-muon-lam-liem-cho/chuong-178',
    'https://truyenfull.live/quy-bi-chi-chu/chuong-1/',
  ];

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

  /// Mở Modal "Thêm Truyện" với 2 cách: Thêm từ Link & Thêm từ File kèm hướng dẫn chi tiết
  void _showAddStoryModal(
    BuildContext context,
    AppThemeColors colors,
    AppStateProvider appState,
    SettingsProvider settings,
    PlayerStateProvider player,
  ) {
    final urlInputController = TextEditingController();
    String? urlErrorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            final isImporting = appState.isImportingFile;

            Future<void> pasteFromClipboard() async {
              final data = await Clipboard.getData('text/plain');
              if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
                setModalState(() {
                  urlInputController.text = data.text!.trim();
                  urlErrorText = null;
                });
              }
            }

            Future<void> handleLoadUrl() async {
              final url = urlInputController.text.trim();
              if (url.isEmpty) {
                setModalState(() {
                  urlErrorText = 'Vui lòng nhập đường dẫn chương truyện';
                });
                return;
              }
              if (!_isUrl(url)) {
                setModalState(() {
                  urlErrorText = 'Đường dẫn không hợp lệ. Vui lòng nhập link chương truyện';
                });
                return;
              }

              Navigator.pop(modalCtx);
              if (!widget.asPage) {
                Navigator.pop(context);
              }
              await appState.loadFromUrl(url, settings: settings, player: player);
              widget.onStoryOpened?.call();
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (scrollCtx, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    18,
                    12,
                    18,
                    MediaQuery.of(modalCtx).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.add_circle_outline_rounded, color: colors.primary, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Thêm Truyện Mới',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                            onPressed: () => Navigator.pop(modalCtx),
                          ),
                        ],
                      ),
                      Divider(color: colors.border, height: 18),

                      // Cách 1: Thêm truyện từ Link web
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.link_rounded, color: colors.primary, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '1. Thêm truyện bằng Link web',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Copy liên kết (URL) của một chương bất kỳ từ các website đọc truyện trực tuyến (như mtruyen.net, truyendichmienphi.com, webnovel.vn, truyenfull, xtruyen...) và dán vào ô bên dưới.',
                              style: TextStyle(fontSize: 12.5, color: colors.textSecondary, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            // Ô nhập dán link
                            Container(
                              height: 46,
                              decoration: BoxDecoration(
                                color: colors.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: urlErrorText != null ? Colors.redAccent : colors.border,
                                ),
                              ),
                              child: TextField(
                                controller: urlInputController,
                                textAlignVertical: TextAlignVertical.center,
                                style: TextStyle(fontSize: 13, color: colors.textPrimary),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Dán link chương truyện tại đây...',
                                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 12.5),
                                  prefixIcon: Icon(Icons.link_rounded, size: 20, color: colors.primary),
                                  prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 46),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (urlInputController.text.isNotEmpty)
                                        IconButton(
                                          icon: Icon(Icons.clear_rounded, size: 18, color: colors.textMuted),
                                          splashRadius: 18,
                                          constraints: const BoxConstraints(minWidth: 38, minHeight: 46),
                                          padding: EdgeInsets.zero,
                                          onPressed: () {
                                            setModalState(() {
                                              urlInputController.clear();
                                              urlErrorText = null;
                                            });
                                          },
                                        )
                                      else
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: TextButton.icon(
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              backgroundColor: colors.primary.withValues(alpha: 0.12),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            icon: Icon(Icons.paste_rounded, size: 14, color: colors.primary),
                                            label: Text(
                                              'Dán',
                                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: colors.primary),
                                            ),
                                            onPressed: pasteFromClipboard,
                                          ),
                                        ),
                                    ],
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                                onChanged: (val) {
                                  if (urlErrorText != null) {
                                    setModalState(() => urlErrorText = null);
                                  } else {
                                    setModalState(() {});
                                  }
                                },
                                onSubmitted: (_) => handleLoadUrl(),
                              ),
                            ),
                            if (urlErrorText != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                urlErrorText!,
                                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                              ),
                            ],
                            const SizedBox(height: 10),
                            // Nút Tải truyện từ Link
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.download_rounded, size: 18),
                                label: const Text(
                                  'Tải & Đọc truyện từ Link',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                onPressed: handleLoadUrl,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Ví dụ link hợp lệ (Chạm để dán thử ngay):',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: colors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            ...sampleUrls.map((url) => InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      urlInputController.text = url;
                                      urlErrorText = null;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
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
                      ),

                      // Cách 2: Thêm truyện từ file TXT / EPUB
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.file_present_rounded, color: colors.primary, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '2. Thêm truyện từ File TXT / EPUB',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Chọn tệp truyện đã tải về sẵn trên điện thoại của bạn:\n• Hỗ trợ đầy đủ định dạng văn bản (.txt) và sách điện tử (.epub).\n• Ứng dụng tự động nhận diện tiêu đề, phân chia chương và lưu trữ để bạn đọc và nghe offline.',
                              style: TextStyle(fontSize: 12.5, color: colors.textSecondary, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colors.primary,
                                  side: BorderSide(color: colors.primary.withValues(alpha: 0.6), width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  backgroundColor: colors.primary.withValues(alpha: 0.06),
                                ),
                                icon: isImporting
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                                        ),
                                      )
                                    : const Icon(Icons.upload_file_rounded, size: 20),
                                label: Text(
                                  isImporting
                                      ? 'Đang thêm truyện từ file...'
                                      : 'Chọn file từ thiết bị (TXT, EPUB)',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                onPressed: isImporting
                                    ? null
                                    : () async {
                                        final success = await appState.importStoryFromFile(
                                          settings: settings,
                                          player: player,
                                        );
                                        if (success) {
                                          Navigator.pop(modalCtx);
                                          if (!widget.asPage) {
                                            Navigator.pop(context);
                                          }
                                          widget.onStoryOpened?.call();
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
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

    // Gom nhóm danh sách mục đã lưu theo tên truyện (kết hợp cả savedAudios và historyChapters)
    final Map<String, List<SavedAudioItem>> groupedMap = {};
    for (final item in appState.savedAudios) {
      final storyKey = item.storyTitle.trim().isNotEmpty
          ? item.storyTitle.trim()
          : 'Truyện chưa đặt tên';

      // Tìm xem đã có nhóm nào trùng tên truyện qua isSameStory chưa
      String matchedKey = storyKey;
      for (final existingKey in groupedMap.keys) {
        if (AppStateProvider.isSameStory(existingKey, storyKey)) {
          matchedKey = existingKey;
          break;
        }
      }
      groupedMap.putIfAbsent(matchedKey, () => []).add(item);
    }

    // Bổ sung các chương từ historyChapters nếu chưa có trong savedAudios
    for (final chap in appState.historyChapters) {
      final storyKey = chap.storyTitle.trim().isNotEmpty
          ? chap.storyTitle.trim()
          : 'Truyện chưa đặt tên';

      String matchedKey = storyKey;
      for (final existingKey in groupedMap.keys) {
        if (AppStateProvider.isSameStory(existingKey, storyKey)) {
          matchedKey = existingKey;
          break;
        }
      }

      final list = groupedMap.putIfAbsent(matchedKey, () => []);
      if (!list.any((a) => a.chapterNumber == chap.chapterNumber)) {
        list.add(SavedAudioItem(
          id: 'audio_${chap.id}',
          title: chap.chapterTitle,
          storyTitle: matchedKey,
          chapterNumber: chap.chapterNumber,
          audioPath: '',
          content: chap.content,
          chapterId: chap.id,
          voiceUsed: settings.currentVoice.name,
          lastPlayedSentenceIndex: chap.lastPlayedSentenceIndex,
          lastPlayedSummaryIndex: chap.lastPlayedSummaryIndex,
          lastPlayedContentIndex: chap.lastPlayedContentIndex,
          lastPlayedSource: chap.lastPlayedSource,
          lastPlayedAt: chap.lastPlayedAt,
        ));
      }
    }

    // Sắp xếp các chương trong mỗi truyện theo thứ tự số chương tăng dần
    for (final key in groupedMap.keys) {
      groupedMap[key]!.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    }

    // Lọc theo từ khóa tìm kiếm tên truyện
    final filteredStories = <String, List<SavedAudioItem>>{};
    final queryTrimmed = _query.toLowerCase().trim();

    if (queryTrimmed.isEmpty) {
      filteredStories.addAll(groupedMap);
    } else {
      for (final entry in groupedMap.entries) {
        if (entry.key.toLowerCase().contains(queryTrimmed)) {
          filteredStories[entry.key] = entry.value;
        }
      }
    }

    final totalStories = filteredStories.length;

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

        // Header Kho Truyện: Tiêu đề & Nút Thêm Truyện
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
              ],
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'Thêm Truyện',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _showAddStoryModal(context, colors, appState, settings, player),
                ),
                if (!widget.asPage) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ],
            ),
          ],
        ),
        Divider(color: colors.border, height: 16),

        // Thanh Tìm kiếm theo tên truyện
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Tìm kiếm theo tên truyện...',
              hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: _query.isNotEmpty ? colors.primary : colors.textMuted,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 44),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.cancel_rounded, size: 18, color: colors.textMuted),
                      splashRadius: 18,
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (val) {
              setState(() => _query = val);
            },
            onSubmitted: (_) {
              FocusScope.of(context).unfocus();
            },
          ),
        ),
        const SizedBox(height: 12),

        // Tiêu đề danh sách khi có tìm kiếm
        if (_query.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Kết quả tìm kiếm ($totalStories truyện):',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: colors.textMuted,
              ),
            ),
          ),
        ],

        // Danh sách truyện trong Kho truyện
        Expanded(
          child: appState.isLoadingLibrary
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Đang tải kho truyện...',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : filteredStories.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _query.isNotEmpty ? Icons.search_off_rounded : Icons.menu_book_outlined,
                              size: 54,
                              color: colors.textMuted.withValues(alpha: 0.35),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _query.isNotEmpty
                                  ? 'Không tìm thấy truyện phù hợp'
                                  : 'Kho truyện đang trống',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _query.isNotEmpty
                                  ? 'Không tìm thấy truyện nào khớp với từ khóa "$_query".'
                                  : 'Bạn chưa lưu truyện nào trong kho. Hãy bấm nút "Thêm Truyện" để thêm truyện từ file hoặc link web.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textMuted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                elevation: 0,
                              ),
                              icon: Icon(_query.isNotEmpty ? Icons.clear_rounded : Icons.add_rounded, size: 18),
                              label: Text(
                                _query.isNotEmpty ? 'Xóa từ khóa tìm kiếm' : 'Thêm Truyện Ngay',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                if (_query.isNotEmpty) {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                } else {
                                  _showAddStoryModal(context, colors, appState, settings, player);
                                }
                              },
                            ),
                          ],
                        ),
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
                            'Chương mới nhất: ${chapters.isNotEmpty ? chapters.last.chapterNumber : 0}',
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
}
