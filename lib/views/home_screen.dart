import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/sentence_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/player_state_provider.dart';
import '../providers/settings_provider.dart';
import 'widgets/settings_modal.dart';
import 'widgets/story_search_modal.dart';
import 'widgets/chapter_list_modal.dart';

enum StoryViewTab {
  summary,
  content,
}

enum NavTab {
  library,
  reader,
  settings,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chapterFocusNode = FocusNode();
  final Map<String, GlobalKey> _sentenceKeys = {};
  late final AnimationController _syncController;
  int? _lastActiveSentenceIndex;
  AudioSourceType? _lastActiveSourceType;
  Timer? _chapterDebounceTimer;
  StoryViewTab _activeTab = StoryViewTab.summary;
  NavTab _activeNavTab = NavTab.library;
  int _settingsInitialTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final player = Provider.of<PlayerStateProvider>(context, listen: false);
      appState.loadSavedDataProgressive(settings: settings, player: player);
    });
  }

  @override
  void dispose() {
    _syncController.dispose();
    _scrollController.dispose();
    _chapterFocusNode.dispose();
    _chapterDebounceTimer?.cancel();
    super.dispose();
  }

  GlobalKey _getSentenceKey(AudioSourceType type, int index) {
    final keyStr = '${type.name}_$index';
    return _sentenceKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  void _onChapterInputSubmittedOrUnfocused(AppStateProvider appState, SettingsProvider settings, PlayerStateProvider player) {
    _chapterDebounceTimer?.cancel();
    final trimmed = appState.chapterController.text.trim();
    final parsed = int.tryParse(trimmed);
    if (parsed != null && parsed > 0) {
      final currentNum = appState.currentChapter?.chapterNumber;
      if (currentNum == null || currentNum != parsed) {
        if (!appState.isProcessing) {
          appState.changeToChapter(parsed, settings: settings, player: player);
        }
      }
    } else {
      if (appState.currentChapter != null) {
        appState.chapterController.text = appState.currentChapter!.chapterNumber.toString();
      }
    }
  }

  void _checkAndScrollToActive(AppStateProvider appState) {
    if (appState.activeSentenceIndex != null) {
      if (_lastActiveSentenceIndex != appState.activeSentenceIndex ||
          _lastActiveSourceType != appState.activeAudioSource) {
        _lastActiveSentenceIndex = appState.activeSentenceIndex;
        _lastActiveSourceType = appState.activeAudioSource;

        // Tự động chuyển tab hiển thị theo phần đang phát
        if (appState.activeAudioSource == AudioSourceType.summary && _activeTab != StoryViewTab.summary) {
          setState(() => _activeTab = StoryViewTab.summary);
        } else if (appState.activeAudioSource == AudioSourceType.content && _activeTab != StoryViewTab.content) {
          setState(() => _activeTab = StoryViewTab.content);
        }

        void attemptScroll([int retryCount = 0]) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final targetIdx = appState.activeSentenceIndex ?? 0;
            if (targetIdx == 0 && _scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
              );
              return;
            }
            final key = _sentenceKeys['${appState.activeAudioSource.name}_$targetIdx'];
            if (key != null && key.currentContext != null) {
              Scrollable.ensureVisible(
                key.currentContext!,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                alignment: 0.35,
              );
            } else if (retryCount < 5) {
              Future.delayed(Duration(milliseconds: 80 * (retryCount + 1)), () {
                if (mounted) attemptScroll(retryCount + 1);
              });
            }
          });
        }

        attemptScroll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final settings = context.watch<SettingsProvider>();
    final player = context.watch<PlayerStateProvider>();
    final colors = AppTheme.getColors(settings.appThemeMode, context);

    // Kích hoạt xoay icon sync khi đang có tiến trình tải truyện ngầm
    if (appState.isBackgroundCrawling) {
      if (!_syncController.isAnimating) {
        _syncController.repeat();
      }
    } else {
      if (_syncController.isAnimating) {
        _syncController.stop();
        _syncController.reset();
      }
    }

    // Tự động cuộn đến câu đang phát nếu có thay đổi
    _checkAndScrollToActive(appState);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ==========================================
                // BODY: Nội dung theo tab đang chọn
                // ==========================================
                Expanded(
                  child: _activeNavTab == NavTab.library
                      ? _buildLibraryTab(context, appState, settings, player, colors)
                      : _activeNavTab == NavTab.settings
                          ? _buildSettingsTab(context, colors)
                          : _buildReaderTab(context, appState, settings, player, colors),
                ),

                // ==========================================
                // BOTTOM ACTION BAR: chỉ hiển thị khi đang ở tab Đọc truyện
                // ==========================================
            if (_activeNavTab == NavTab.reader)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.background,
                  border: Border(
                    top: BorderSide(color: colors.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    // Nút [ < ] (Chương trước)
                    Expanded(
                      flex: 2,
                      child: _buildBottomNavButton(
                        icon: Icons.chevron_left_rounded,
                        colors: colors,
                        onTap: appState.isProcessing
                            ? null
                            : () => appState.goToPreviousChapter(settings: settings, player: player),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Input nhập số chương
                    _buildChapterInputField(
                      appState: appState,
                      settings: settings,
                      player: player,
                      colors: colors,
                    ),
                    const SizedBox(width: 8),

                    // Nút Icon Menu danh sách chương (Kế bên input số chương)
                    _buildChapterMenuButton(
                      context: context,
                      appState: appState,
                      colors: colors,
                    ),
                    const SizedBox(width: 8),

                    // Nút [ ▶ / ⏸ ] (Phát / Tạm dừng audio)
                    _buildPlayPauseButton(
                      isPlaying: player.isPlaying,
                      colors: colors,
                      onTap: () => appState.toggleMainPlayPause(
                        settings: settings,
                        player: player,
                        currentSource: _activeTab == StoryViewTab.summary
                            ? AudioSourceType.summary
                            : AudioSourceType.content,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Nút [ > ] (Chương sau)
                    Expanded(
                      flex: 2,
                      child: _buildBottomNavButton(
                        icon: Icons.chevron_right_rounded,
                        colors: colors,
                        onTap: appState.isProcessing
                            ? null
                            : () => appState.goToNextChapter(settings: settings, player: player),
                        hasPreloaded: appState.hasPreloadedNext,
                      ),
                    ),
                  ],
                ),
              ),

            // ==========================================
            // BANNER TIẾN TRÌNH TẢI TRUYỆN: Chỉ hiển thị bên tab Kho truyện (Non-blocking, hiển thị % & nút Hủy)
            // ==========================================
            if (_activeNavTab == NavTab.library && (appState.isImportingFile || appState.isBackgroundCrawling))
              _buildStoryLoadingProgressBar(appState, colors),

            // ==========================================
            // BOTTOM NAV BAR: 3 tab
            // ==========================================
            _buildBottomNavBar(appState, settings, player, colors),
          ],
        ),
      ],
    ),
  ),
);
  }

  /// Tab Kho truyện
  Widget _buildLibraryTab(
    BuildContext context,
    AppStateProvider appState,
    SettingsProvider settings,
    PlayerStateProvider player,
    AppThemeColors colors,
  ) {
    return StorySearchModal.page(
      onStoryOpened: () {
        setState(() => _activeNavTab = NavTab.reader);
      },
    );
  }

  /// Tab Đọc truyện
  Widget _buildReaderTab(
    BuildContext context,
    AppStateProvider appState,
    SettingsProvider settings,
    PlayerStateProvider player,
    AppThemeColors colors,
  ) {
    return Column(
      children: [
        const SizedBox(height: 10),

        // 1. Header: Story Title + Chapter Subtitle + Sleep Timer Badge + Bookmark Icon
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Tiêu đề truyện & Tên chương bên dưới
              Expanded(
                child: Tooltip(
                  message: appState.hasActiveChapter ? 'Chạm để tải lại chương' : 'Chạm để tìm kiếm hoặc dán link',
                  child: InkWell(
                    onTap: () {
                      if (appState.hasActiveChapter) {
                        if (!appState.isProcessing) {
                          appState.reloadCurrentChapter(settings: settings, player: player);
                        }
                      } else {
                        setState(() => _activeNavTab = NavTab.library);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        children: [
                          Icon(
                            appState.hasActiveChapter ? Icons.menu_book_rounded : Icons.auto_stories_rounded,
                            size: 20,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        appState.hasActiveChapter ? appState.displayStoryTitle : 'StorySum',
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.bold,
                                          color: appState.hasActiveChapter ? colors.textPrimary : colors.primary,
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!appState.hasActiveChapter) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: colors.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(
                                            color: colors.primary.withValues(alpha: 0.35),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          'v${AppConstants.appVersion}',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: colors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (appState.hasActiveChapter && appState.displayChapterSubtitle.isNotEmpty) ...[
                                  const SizedBox(height: 1.5),
                                  Text(
                                    appState.displayChapterSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: colors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Badge Hẹn giờ dừng phát khi đang bật
              if (player.sleepTimerEnabled) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() {
                    _settingsInitialTabIndex = 0; // Tab Audio & Truyện
                    _activeNavTab = NavTab.settings;
                  }),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.primary.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 12, color: colors.primary),
                        const SizedBox(width: 3),
                        Text(
                          player.formattedSleepTimerRemaining,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Icon Bookmark (Góc trên bên phải, đánh dấu trang đang đọc)
              if (appState.hasActiveChapter) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(
                    appState.isCurrentChapterBookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: appState.isCurrentChapterBookmarked
                        ? Colors.amber.shade600
                        : colors.textSecondary,
                    size: 22,
                  ),
                  tooltip: appState.isCurrentChapterBookmarked
                      ? 'Đã đánh dấu chương này (Chạm để bỏ đánh dấu)'
                      : 'Đánh dấu chương đang đọc',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () async {
                    await appState.toggleBookmarkCurrentChapter();
                  },
                ),
              ],
            ],
          ),
        ),

        if (appState.isProcessing) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: appState.overallProgress > 0 ? appState.overallProgress : null,
                  backgroundColor: colors.elevatedBackground,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  minHeight: 2.5,
                ),
                const SizedBox(height: 4),
                Text(
                  appState.currentStatusMessage,
                  style: TextStyle(fontSize: 11, color: colors.accent),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 8),

        // 2. Switcher Button qua lại giữa Tóm tắt và Nội dung (khi có chương truyện)
        if (appState.hasActiveChapter)
          _buildViewSwitcher(
            activeTab: _activeTab,
            appState: appState,
            settings: settings,
            colors: colors,
            onTabChanged: (tab) {
              setState(() => _activeTab = tab);
              final targetSource = tab == StoryViewTab.summary
                  ? AudioSourceType.summary
                  : AudioSourceType.content;
              appState.switchAudioTab(targetSource, settings: settings, player: player);
            },
          ),

        const SizedBox(height: 4),

        // 3. Main Content View
        Expanded(
          child: !appState.hasActiveChapter
              ? _buildEmptyInitialState(context, appState, settings, player, colors)
              : Stack(
                  children: [
                    _buildSelectedTabView(
                      context: context,
                      activeTab: _activeTab,
                      appState: appState,
                      settings: settings,
                      player: player,
                      colors: colors,
                    ),
                    Positioned(
                      right: 22,
                      bottom: 22,
                      child: _buildScrollToTopButton(colors),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Tab Cài đặt — mở Settings Modal ngay khi chuyển sang tab này
  Widget _buildSettingsTab(BuildContext context, AppThemeColors colors) {
    return SettingsModal.page(
      key: ValueKey('settings_page_$_settingsInitialTabIndex'),
      initialTabIndex: _settingsInitialTabIndex,
    );
  }

  /// Bottom Navigation Bar với 3 tab
  Widget _buildBottomNavBar(AppStateProvider appState, SettingsProvider settings, PlayerStateProvider player, AppThemeColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          top: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _buildNavItem(
                icon: Icons.library_books_rounded,
                label: 'Kho truyện',
                tab: NavTab.library,
                colors: colors,
                onTap: () => setState(() => _activeNavTab = NavTab.library),
              ),
              _buildNavItem(
                icon: Icons.menu_book_rounded,
                label: 'Đọc truyện',
                tab: NavTab.reader,
                colors: colors,
                onTap: () => setState(() => _activeNavTab = NavTab.reader),
              ),
              _buildNavItem(
                icon: Icons.settings_rounded,
                label: 'Cài đặt',
                tab: NavTab.settings,
                colors: colors,
                onTap: () => setState(() => _activeNavTab = NavTab.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required NavTab tab,
    required AppThemeColors colors,
    required VoidCallback onTap,
  }) {
    final isActive = _activeNavTab == tab;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: isActive ? colors.primary : colors.textMuted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? colors.primary : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  /// Thanh chuyển đổi giữa Tóm tắt và Nội dung
  Widget _buildViewSwitcher({
    required StoryViewTab activeTab,
    required AppStateProvider appState,
    required SettingsProvider settings,
    required AppThemeColors colors,
    required ValueChanged<StoryViewTab> onTabChanged,
  }) {
    final summaryLoaded = appState.summarySentences.where((s) => s.hasAudio).length;
    final summaryTotal = appState.summarySentences.length;
    final contentLoaded = appState.contentSentences.where((s) => s.hasAudio).length;
    final contentTotal = appState.contentSentences.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border, width: 1.0),
      ),
      child: Row(
        children: [
          // Tab 1: Tóm tắt
          Expanded(
            child: InkWell(
              onTap: () => onTabChanged(StoryViewTab.summary),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: activeTab == StoryViewTab.summary
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.summarize_rounded,
                      size: 15,
                      color: activeTab == StoryViewTab.summary
                          ? Colors.white
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tóm tắt',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: activeTab == StoryViewTab.summary
                            ? Colors.white
                            : colors.textSecondary,
                      ),
                    ),
                    if (summaryTotal > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: activeTab == StoryViewTab.summary
                              ? Colors.white.withValues(alpha: 0.25)
                              : colors.elevatedBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$summaryLoaded/$summaryTotal',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: activeTab == StoryViewTab.summary
                                ? Colors.white
                                : colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Tab 2: Nội dung
          Expanded(
            child: InkWell(
              onTap: () => onTabChanged(StoryViewTab.content),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: activeTab == StoryViewTab.content
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 15,
                      color: activeTab == StoryViewTab.content
                          ? Colors.white
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Nội dung',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: activeTab == StoryViewTab.content
                            ? Colors.white
                            : colors.textSecondary,
                      ),
                    ),
                    if (contentTotal > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: activeTab == StoryViewTab.content
                              ? Colors.white.withValues(alpha: 0.25)
                              : colors.elevatedBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$contentLoaded/$contentTotal',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: activeTab == StoryViewTab.content
                                ? Colors.white
                                : colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Khung hiển thị nội dung của Tab đang được chọn (Tóm tắt hoặc Nội dung)
  Widget _buildSelectedTabView({
    required BuildContext context,
    required StoryViewTab activeTab,
    required AppStateProvider appState,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required AppThemeColors colors,
  }) {
    final isSummary = activeTab == StoryViewTab.summary;
    final sentences = isSummary ? appState.summarySentences : appState.contentSentences;
    final sourceType = isSummary ? AudioSourceType.summary : AudioSourceType.content;

    if (isSummary &&
        sentences.isEmpty &&
        !appState.isProcessing &&
        appState.hasActiveChapter &&
        (appState.currentSummary == null || appState.currentSummary!.summaryText.trim().isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appState.autoSummarizeIfEmpty(settings);
      });
    }

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: sentences.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isSummary && !appState.isProcessing && settings.currentProviderApiKeys.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.key_off_rounded,
                            size: 32,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có API Key cho ${settings.aiProvider}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Vui lòng cấu hình API Key trong phần Cài đặt để sử dụng tính năng tóm tắt AI.',
                          style: TextStyle(color: colors.textSecondary, fontSize: 12.5, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => setState(() {
                            _settingsInitialTabIndex = 1; // Tab Dịch & Tóm tắt
                            _activeNavTab = NavTab.settings;
                          }),
                          icon: const Icon(Icons.settings_rounded, size: 18),
                          label: const Text('Mở Cài Đặt API Key', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          ),
                        ),
                      ] else if (isSummary && !appState.isProcessing && (appState.summaryErrorMessage != null || settings.workingApiKeys.isEmpty)) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            size: 32,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Không thể tóm tắt AI',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          appState.summaryErrorMessage ?? 'Tất cả ${settings.currentProviderApiKeys.length} API Key của ${settings.aiProvider} đều bị lỗi hoặc hết hạn mức/quota.',
                          style: TextStyle(color: colors.textSecondary, fontSize: 12.5, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => setState(() {
                                _settingsInitialTabIndex = 1; // Tab Dịch & Tóm tắt
                                _activeNavTab = NavTab.settings;
                              }),
                              icon: const Icon(Icons.settings_rounded, size: 16),
                              label: const Text('Cài Đặt API Key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.primary,
                                side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: () => appState.summarizeCurrentChapter(settings),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Thử Lại', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colors.elevatedBackground,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSummary ? Icons.summarize_outlined : Icons.menu_book_outlined,
                            size: 28,
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isSummary
                              ? (appState.isProcessing ? 'Đang tóm tắt AI...' : 'Chưa có bản tóm tắt cho chương này.')
                              : (appState.isProcessing ? 'Đang tải nội dung...' : 'Chưa có nội dung truyện.'),
                          style: TextStyle(color: colors.textMuted, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        if (isSummary && appState.isProcessing) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                            ),
                          ),
                        ] else if (isSummary && !appState.isProcessing) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => appState.summarizeCurrentChapter(settings),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Thử Lại Tóm Tắt AI', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary.withValues(alpha: 0.15),
                              foregroundColor: colors.primary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              )
            : Wrap(
                children: sentences.map((sentence) {
                  return _buildSentenceWidget(
                    key: _getSentenceKey(sourceType, sentence.index),
                    sentence: sentence,
                    sourceType: sourceType,
                    appState: appState,
                    settings: settings,
                    player: player,
                    colors: colors,
                  );
                }).toList(),
              ),
      ),
    );
  }

  /// Nút nổi cuộn nhanh lên đầu trang
  Widget _buildScrollToTopButton(AppThemeColors colors) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: 'Cuộn lên đầu trang',
        child: InkWell(
          onTap: () {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.elevatedBackground.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(color: colors.border, width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(Icons.arrow_upward_rounded, size: 18, color: colors.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton({
    required bool isPlaying,
    required AppThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isPlaying
              ? colors.primary.withValues(alpha: 0.15)
              : colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPlaying ? colors.primary : colors.border,
            width: 1.2,
          ),
        ),
        child: Center(
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: isPlaying ? colors.accent : colors.primary,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildChapterInputField({
    required AppStateProvider appState,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required AppThemeColors colors,
  }) {
    return Container(
      width: 70,
      height: 42,
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border, width: 1.2),
      ),
      child: Center(
        child: Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) {
              _onChapterInputSubmittedOrUnfocused(appState, settings, player);
            }
          },
          child: TextField(
            controller: appState.chapterController,
            focusNode: _chapterFocusNode,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              hintText: 'Số',
              hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            onSubmitted: (_) {
              _onChapterInputSubmittedOrUnfocused(appState, settings, player);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildChapterMenuButton({
    required BuildContext context,
    required AppStateProvider appState,
    required AppThemeColors colors,
  }) {
    final isDownloading = appState.isBackgroundCrawling;

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: isDownloading
            ? 'Đang tải thêm chương ngầm... Chạm để xem danh sách'
            : 'Danh sách chương',
        child: InkWell(
          onTap: () => ChapterListModal.show(
            context,
            onNavigateToLibrary: () {
              setState(() => _activeNavTab = NavTab.library);
            },
          ),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDownloading
                  ? colors.primary.withValues(alpha: 0.15)
                  : colors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDownloading ? colors.primary : colors.border,
                width: isDownloading ? 1.5 : 1.2,
              ),
            ),
            child: isDownloading
                ? RotationTransition(
                    turns: _syncController,
                    child: Icon(
                      Icons.sync_rounded,
                      color: colors.primary,
                      size: 21,
                    ),
                  )
                : Icon(
                    Icons.format_list_bulleted_rounded,
                    color: colors.primary,
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSentenceWidget({
    Key? key,
    required SentenceItem sentence,
    required AudioSourceType sourceType,
    required AppStateProvider appState,
    required SettingsProvider settings,
    required PlayerStateProvider player,
    required AppThemeColors colors,
  }) {
    final isSelected = appState.activeAudioSource == sourceType &&
        appState.activeSentenceIndex == sentence.index;

    return InkWell(
      key: key,
      onTap: () => appState.playSentence(
        sourceType: sourceType,
        sentenceIndex: sentence.index,
        settings: settings,
        player: player,
      ),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(
                  color: colors.primary.withValues(alpha: 0.55),
                  width: 1.1,
                )
              : null,
        ),
        child: Text(
          '${sentence.text} ',
          style: AppTheme.getStoryTextStyle(
            fontFamily: settings.fontFamily,
            fontSize: settings.fontSize,
            color: isSelected ? colors.textPrimary : colors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            height: 1.65,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavButton({
    required IconData icon,
    required AppThemeColors colors,
    required VoidCallback? onTap,
    bool hasPreloaded = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border, width: 1.2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: Icon(icon, color: colors.textSecondary, size: 24),
            ),
            if (hasPreloaded)
              Positioned(
                top: 4,
                right: 6,
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildEmptyInitialState(
    BuildContext context,
    AppStateProvider appState,
    SettingsProvider settings,
    PlayerStateProvider player,
    AppThemeColors colors,
  ) {
    // 1. Trạng thái Đang tải chương / tải từ URL
    if (appState.isProcessing) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3.2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                appState.headerTitle.isNotEmpty ? appState.headerTitle : 'Đang tải dữ liệu...',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                appState.currentStatusMessage.isNotEmpty
                    ? appState.currentStatusMessage
                    : 'Đang kết nối đến máy chủ truyện, vui lòng chờ trong giây lát...',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textMuted,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // 2. Trạng thái Gặp lỗi khi tải chương truyện từ URL hoặc mạng
    final hasError = appState.currentStatusMessage.isNotEmpty &&
        (appState.currentStatusMessage.startsWith('Lỗi') ||
            appState.currentStatusMessage.startsWith('Tải thất bại'));

    if (hasError) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35), width: 1.5),
                ),
                child: const Icon(Icons.cloud_off_rounded, size: 36, color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              Text(
                'Không Thể Tải Truyện',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  appState.currentStatusMessage,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.redAccent,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: const Icon(Icons.library_books_rounded, size: 18),
                      label: const Text('Kho Truyện', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () => setState(() => _activeNavTab = NavTab.library),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Thử Lại', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () => appState.reloadCurrentChapter(
                        settings: settings,
                        player: player,
                        forceRefresh: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // 3. Trạng thái Mặc định: Chưa chọn truyện nào
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: colors.primary.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Icon(Icons.auto_stories_rounded, size: 36, color: colors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa Chọn Truyện',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Vui lòng chọn truyện từ Kho truyện hoặc nhập liên kết để bắt đầu đọc và nghe audio.',
              style: TextStyle(
                fontSize: 13,
                color: colors.textMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.library_books_rounded, size: 20),
                label: const Text(
                  'Chọn Truyện Từ Kho Truyện',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: () => setState(() => _activeNavTab = NavTab.library),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Thanh hiển thị tiến trình tải truyện (nhập file TXT/EPUB hoặc tải từ Link web) đồng bộ kèm % và nút Hủy (Cancel)
  Widget _buildStoryLoadingProgressBar(AppStateProvider appState, AppThemeColors colors) {
    final isFile = appState.isImportingFile;
    final isCrawl = appState.isBackgroundCrawling;
    if (!isFile && !isCrawl) return const SizedBox.shrink();

    final String title = isFile
        ? 'Đang nhập từ file: ${appState.importingStoryTitle ?? 'Tệp tin'}'
        : 'Đang tải từ link: ${appState.bgCrawlStoryTitle ?? 'Truyện web'}';

    final double? progress = isFile
        ? (appState.importProgress.clamp(0.0, 1.0))
        : null;

    final String status = isFile
        ? (appState.importStatusMessage.isNotEmpty ? appState.importStatusMessage : 'Đang xử lý truyện...')
        : 'Đang tải chương ${appState.bgCrawlCurrentChapter}...';

    final String counterText = isFile
        ? (appState.importTotalChapters > 0 ? '${appState.importCurrentChapter}/${appState.importTotalChapters}' : '')
        : 'Đã lưu: ${appState.bgCrawlSuccessCount} chương';

    final String percentText = isFile
        ? '${((progress ?? 0) * 100).toInt()}%'
        : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (percentText.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.primary.withValues(alpha: 0.3), width: 0.8),
                  ),
                  child: Text(
                    percentText,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              // Nút Dừng quá trình thêm/tải truyện
              InkWell(
                onTap: () {
                  if (isFile) {
                    appState.cancelFileImport();
                  } else {
                    appState.stopBackgroundCrawl();
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.stop_rounded, size: 14, color: Colors.redAccent),
                      SizedBox(width: 2),
                      Text(
                        'Dừng',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (progress != null && progress > 0) ? progress : null,
              backgroundColor: colors.border,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              minHeight: 4.5,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (counterText.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  counterText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
