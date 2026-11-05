import 'dart:async' show Timer;

import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/dialog/report.dart';
import 'package:PiliPlus/common/widgets/marquee.dart';
import 'package:PiliPlus/common/widgets/player_bar.dart';
import 'package:PiliPlus/http/danmaku.dart';
import 'package:PiliPlus/http/danmaku_block.dart';
import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/pages/setting/widgets/popup_item.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/local/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/action_item.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/menu_row.dart';
import 'package:PiliPlus/pages/video/widgets/header_mixin.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/player_backend.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart'
    show shutdownTimerService, ShutdownPanel;
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide showBottomSheet;

mixin PlayerClockMixin<T extends StatefulWidget> on State<T> {
  PlPlayerController get plPlayerController;
  late final titleKey = GlobalKey();
  ContextSingleTicker? provider;
  ContextSingleTicker get effectiveProvider => provider ??= ContextSingleTicker(
    context,
    autoStart: () =>
        plPlayerController.showControls.value &&
        !plPlayerController.controlsLock.value,
  );

  bool get isPortrait;
  bool get isFullScreen;

  Timer? _clock;
  RxString now = ''.obs;

  static final _format = DateFormat('HH:mm');

  @override
  void dispose() {
    stopClock();
    super.dispose();
  }

  void startClock() {
    if (!_showCurrTime) return;
    if (_clock == null) {
      now.value = _format.format(DateTime.now());
      _clock ??= Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          stopClock();
          return;
        }
        now.value = _format.format(DateTime.now());
      });
    }
  }

  void stopClock() {
    _clock?.cancel();
    _clock = null;
  }

  bool _showCurrTime = false;
  void showCurrTimeIfNeeded(bool isFullScreen) {
    _showCurrTime =
        !isPortrait && (isFullScreen || plPlayerController.isDesktopPip);
    if (!_showCurrTime) {
      stopClock();
    }
  }

  List<Widget>? get clockWidgets {
    if (_showCurrTime) {
      return [
        Obx(
          () => Text(
            now.value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
            ),
          ),
        ),
      ];
    }
    return null;
  }
}

class HeaderControl extends StatefulWidget {
  const HeaderControl({
    required this.isPortrait,
    required this.controller,
    required this.videoDetailCtr,
    required this.heroTag,
    super.key,
  });

  final bool isPortrait;
  final PlPlayerController controller;
  final VideoDetailController videoDetailCtr;
  final String heroTag;

  @override
  State<HeaderControl> createState() => HeaderControlState();

  static Future<bool> likeDanmaku(VideoDanmaku extra, int cid) async {
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('请先登录');
      return false;
    }
    final isLike = !extra.isLike;
    final res = await DanmakuHttp.danmakuLike(
      isLike: isLike,
      cid: cid,
      id: extra.id,
    );
    if (res.isSuccess) {
      extra.isLike = isLike;
      if (isLike) {
        extra.like++;
      } else {
        extra.like--;
      }
      SmartDialog.showToast('${isLike ? '' : '取消'}点赞成功');
      return true;
    } else {
      res.toast();
      if (res case Error(:final code)) {
        if (code == 65006) {
          extra.isLike = true;
          return true;
        }
        if (code == 65004) {
          extra.isLike = false;
          return true;
        }
      }
      return false;
    }
  }

  static Future<bool> deleteDanmaku(int id, int cid) async {
    final res = await DanmakuHttp.danmakuRecall(
      cid: cid,
      id: id,
    );
    if (res.isSuccess) {
      SmartDialog.showToast('删除成功');
      return true;
    } else {
      res.toast();
      return false;
    }
  }

  static Future<void> reportDanmaku(
    BuildContext context, {
    required VideoDanmaku extra,
    required PlPlayerController ctr,
  }) {
    if (Accounts.main.isLogin) {
      return autoWrapReportDialog(
        context,
        mid: () => int.parse(extra.mid),
        ReportOptions.danmakuReport,
        withContent: ReportOptions.danmakuReportCheck,
        contentRequired: ReportOptions.danmakuReportCheck,
        (reasonType, reasonDesc, banUid) {
          if (banUid) {
            final filter = ctr.filters;
            if (filter.dmUid.add(extra.mid)) {
              filter.count++;
              GStorage.localCache.put(LocalCacheKey.danmakuFilterRules, filter);
            }
            DanmakuFilterHttp.danmakuFilterAdd(filter: extra.mid, type: 2);
          }
          return DanmakuHttp.danmakuReport(
            reason: reasonType,
            cid: ctr.cid!,
            id: extra.id,
            content: reasonDesc,
          );
        },
      );
    } else {
      return SmartDialog.showToast('请先登录');
    }
  }

  static Future<void> reportLiveDanmaku(
    BuildContext context, {
    required int roomId,
    required String msg,
    required LiveDanmaku extra,
  }) {
    if (Accounts.main.isLogin) {
      return autoWrapReportDialog(
        context,
        ReportOptions.liveDanmakuReport,
        withContent: ReportOptions.liveDanmakuReportCheck,
        contentRequired: ReportOptions.liveDanmakuReportCheck,
        (reasonType, reasonDesc, banUid) {
          // if (banUid) {
          //   final filter = ctr.filters;
          //   if (filter.dmUid.add(extra.mid)) {
          //     filter.count++;
          //     GStorage.localCache.put(
          //       LocalCacheKey.danmakuFilterRules,
          //       filter,
          //     );
          //   }
          //   DanmakuFilterHttp.danmakuFilterAdd(
          //     filter: extra.mid,
          //     type: 2,
          //   );
          // }
          return LiveHttp.liveDmReport(
            roomId: roomId,
            mid: extra.mid,
            msg: msg,
            reason: ReportOptions.liveDanmakuReport['']![reasonType]!,
            reasonId: reasonType,
            dmType: extra.dmType,
            idStr: extra.id,
            ts: extra.ts,
            sign: extra.ct,
          );
        },
      );
    } else {
      return SmartDialog.showToast('请先登录');
    }
  }
}

class HeaderControlState extends State<HeaderControl>
    with HeaderMixin, PlayerClockMixin {
  @override
  late final PlPlayerController plPlayerController = widget.controller;
  late final VideoDetailController videoDetailCtr = widget.videoDetailCtr;
  late final PlayUrlModel videoInfo = videoDetailCtr.data;
  static const TextStyle subTitleStyle = TextStyle(fontSize: 12);
  static const TextStyle titleStyle = TextStyle(fontSize: 14);

  String get heroTag => widget.heroTag;
  late final UgcIntroController ugcIntroController;
  late final PgcIntroController pgcIntroController;
  late final LocalIntroController localIntroController;
  late CommonIntroController introController = isFileSource
      ? localIntroController
      : videoDetailCtr.isUgc
      ? ugcIntroController
      : pgcIntroController;

  @override
  bool get isPortrait => widget.isPortrait;

  Box setting = GStorage.setting;

  @override
  void initState() {
    super.initState();
    if (isFileSource) {
      introController = Get.find<LocalIntroController>(tag: heroTag);
    } else if (videoDetailCtr.isUgc) {
      introController = Get.find<UgcIntroController>(tag: heroTag);
    } else {
      introController = Get.find<PgcIntroController>(tag: heroTag);
    }
  }

  /// 设置面板
  void showSettingSheet() {
    showBottomSheet(
      (context, setState) {
        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            clipBehavior: Clip.hardEdge,
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 14),
              children: [
                ListTile(
                  dense: true,
                  onTap: () {
                    Get.back();
                    introController.viewLater();
                  },
                  leading: const Icon(Icons.watch_later_outlined, size: 20),
                  title: const Text('添加至「稍后再看」', style: titleStyle),
                ),
                if (videoDetailCtr.epId == null)
                  ListTile(
                    dense: true,
                    onTap: () {
                      Get.back();
                      videoDetailCtr.showNoteList(context);
                    },
                    leading: const Icon(Icons.note_alt_outlined, size: 20),
                    title: const Text('查看笔记', style: titleStyle),
                  ),
                if (!isFileSource)
                  ListTile(
                    dense: true,
                    onTap: () {
                      Get.back();
                      videoDetailCtr.onDownload(this.context);
                    },
                    leading: const Icon(
                      MdiIcons.folderDownloadOutline,
                      size: 20,
                    ),
                    title: const Text('离线缓存', style: titleStyle),
                  ),
                if (widget.videoDetailCtr.cover.value.isNotEmpty)
                  ListTile(
                    dense: true,
                    onTap: () {
                      Get.back();
                      ImageUtils.downloadImg([
                        widget.videoDetailCtr.cover.value,
                      ]);
                    },
                    leading: const Icon(Icons.image_outlined, size: 20),
                    title: const Text('保存封面', style: titleStyle),
                  ),
                ListTile(
                  dense: true,
                  onTap: () {
                    Get.back();
                    shutdownTimerService.showScheduleExitDialog(
                      this.context,
                      isFullScreen: isFullScreen,
                    );
                  },
                  leading: const Icon(Icons.hourglass_top_outlined, size: 20),
                  title: const Text('定时关闭', style: titleStyle),
                  subtitle: shutdownTimerService.isActive
                      ? ShutdownPanel(
                          buildCountdownText: (text) =>
                              Text(text == null ? '已结束' : '剩余 $text'),
                          builder: (
                            context,
                            countdown,
                            onCountdown,
                            setState,
                          ) => countdown,
                        )
                      : null,
                ),
                if (!isFileSource) ...[
                  ListTile(
                    dense: true,
                    onTap: () {
                      Get.back();
                      videoDetailCtr.editPlayUrl();
                    },
                    leading: const Icon(
                      Icons.link,
                      size: 20,
                    ),
                    title: const Text('播放地址', style: titleStyle),
                  ),
                  ListTile(
                    dense: true,
                    onTap: () {
                      Get.back();
                      videoDetailCtr.queryVideoUrl(fromReset: true);
                    },
                    leading: const Icon(Icons.refresh_outlined, size: 20),
                    title: const Text('重载视频', style: titleStyle),
                  ),
                ],
                if (!isFileSource)
                  ListTile(
                    dense: true,
                    title: const Text('CDN 设置', style: titleStyle),
                    leading: const Icon(MdiIcons.cloudPlusOutline, size: 20),
                    subtitle: Text(
                      '当前：${VideoUtils.cdnService.desc}，无法播放请切换',
                      style: subTitleStyle,
                    ),
                    onTap: () async {
                      Get.back();
                      final result = await showDialog<CDNService>(
                        context: context,
                        builder: (context) => CdnSelectDialog(
                          sample: videoInfo.dash?.video?.firstOrNull,
                        ),
                      );
                      if (result != null) {
                        VideoUtils.cdnService = result;
                        setting.put(SettingBoxKey.CDNService, result.name);
                        SmartDialog.showToast('已设置为 ${result.desc}，正在重载视频');
                        videoDetailCtr.queryVideoUrl(fromReset: true);
                      }
                    },
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    spacing: 10,
                    children: [
                      if (PlatformUtils.isDesktop) ...[
                        ActionIconItem(
                          tooltip: '向左旋转',
                          onTap: () => videoDetailCtr.rotate = videoDetailCtr
                              .calcRotate(-90),
                          iconData: Icons.rotate_left,
                        ),
                        ActionIconItem(
                          tooltip: '向右旋转',
                          onTap: () => videoDetailCtr.rotate = videoDetailCtr
                              .calcRotate(90),
                          iconData: Icons.rotate_right,
                        ),
                      ],
                      Obx(
                        () => ActionRowLineItem(
                          text: " 左右翻转 ",
                          iconData: Icons.flip,
                          onTap: plPlayerController.flipX.toggle,
                          selectStatus: plPlayerController.flipX.value,
                        ),
                      ),
                      Obx(
                        () => ActionRowLineItem(
                          text: " 上下翻转 ",
                          iconData: CustomIcons.flip_rotate_90,
                          onTap: plPlayerController.flipY.toggle,
                          selectStatus: plPlayerController.flipY.value,
                        ),
                      ),
                      if ((isFileSource &&
                              !(plPlayerController.dataSource as FileSource)
                                  .isMp4) ||
                          (!isFileSource &&
                              videoDetailCtr.audioUrl?.isNotEmpty == true))
                        Obx(
                          () {
                            final onlyPlayAudio =
                                plPlayerController.onlyPlayAudio.value;
                            return ActionRowLineItem(
                              iconData: Icons.headphones,
                              onTap: () {
                                plPlayerController.onlyPlayAudio.value =
                                    !onlyPlayAudio;
                                videoDetailCtr.playedTime = plPlayerController
                                    .videoPlayerController
                                    ?.state
                                    .position;
                                videoDetailCtr.playerInit();
                              },
                              text: " 听视频 ",
                              selectStatus: onlyPlayAudio,
                            );
                          },
                        ),
                      Obx(
                        () => ActionRowLineItem(
                          iconData: Icons.play_circle_outline,
                          onTap: plPlayerController.setContinuePlayInBackground,
                          text: " 后台播放 ",
                          selectStatus:
                              plPlayerController.continuePlayInBackground.value,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isFileSource) ...[
                  ListTile(
                    dense: true,
                    onTap: () {
                      Get.back();
                      showSetVideoQa();
                    },
                    leading: const Icon(Icons.play_circle_outline, size: 20),
                    title: const Text('选择画质', style: titleStyle),
                    subtitle: Text(
                      '当前画质 ${videoDetailCtr.currentVideoQa.value?.desc}',
                      style: subTitleStyle,
                    ),
                  ),
                  if (videoDetailCtr.currentAudioQa != null)
                    ListTile(
                      dense: true,
                      onTap: () {
                        Get.back();
                        showSetAudioQa();
                      },
                      leading: const Icon(Icons.album_outlined, size: 20),
                      title: const Text('选择音质', style: titleStyle),
                      subtitle: Text(
                        '当前音质 ${videoDetailCtr.currentAudioQa!.desc}',
                        style: subTitleStyle,
                      ),
                    ),
                ],
                PopupListTile(
                  dense: true,
                  leading: const Icon(Icons.repeat, size: 20),
                  title: const Text('播放顺序', style: titleStyle),
                  titleStyle: theme.textTheme.bodyLarge,
                  value: () {
                    final value = plPlayerController.playRepeat;
                    return (value, value.label);
                  },
                  itemBuilder: (_) => enumItemBuilder(PlayRepeat.values),
                  onSelected: (value, setState) {
                    plPlayerController.setPlayRepeat(value);
                    setState();
                  },
                  descPosType: .subtitle,
                  descStyle: subTitleStyle,
                ),
                ListTile(
                  dense: true,
                  onTap: () {
                    Get.back();
                    showDanmakuPool();
                  },
                  leading: const Icon(CustomIcons.dm_on, size: 20),
                  title: const Text('弹幕列表', style: titleStyle),
                ),
                ListTile(
                  dense: true,
                  onTap: () {
                    Get.back();
                    showSetDanmaku();
                  },
                  leading: const Icon(CustomIcons.dm_settings, size: 20),
                  title: const Text('弹幕设置', style: titleStyle),
                ),
                if (plPlayerController.videoPlayerController case final player?)
                  ListTile(
                    dense: true,
                    title: const Text('播放信息', style: titleStyle),
                    leading: const Icon(Icons.info_outline, size: 20),
                    onTap: () => showPlayerInfo(context, player: player),
                  ),
                ListTile(
                  dense: true,
                  onTap: () {
                    if (!Accounts.main.isLogin) {
                      SmartDialog.showToast('账号未登录');
                      return;
                    }
                    Get.back();
                    PageUtils.reportVideo(videoDetailCtr.aid);
                  },
                  leading: const Icon(Icons.error_outline, size: 20),
                  title: const Text('举报', style: titleStyle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void showPlayerInfo(
    BuildContext context, {
    required PlayerBackend player,
  }) {
    final state = player.state;
    final colorScheme = ColorScheme.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('播放信息'),
          contentPadding: const EdgeInsets.only(top: 16),
          content: Material(
            type: MaterialType.transparency,
            child: ListTileTheme(
              contentPadding: const .symmetric(horizontal: 24),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: const Text('分辨率'),
                      subtitle: Text('${state.width}x${state.height}'),
                      onTap: () => Utils.copyText(
                        '分辨率\n${state.width}x${state.height}',
                      ),
                    ),
                    ListTile(
                      dense: true,
                      title: const Text('进度'),
                      subtitle: Text(
                        '${state.position.inSeconds} / ${state.duration.inSeconds}',
                      ),
                      onTap: () => Utils.copyText(
                        '进度\n${state.position.inSeconds} / ${state.duration.inSeconds}',
                      ),
                    ),
                    ListTile(
                      dense: true,
                      title: const Text('倍速'),
                      subtitle: Text(state.rate.toString()),
                      onTap: () => Utils.copyText('倍速\n${state.rate}'),
                    ),
                    ListTile(
                      dense: true,
                      title: const Text('音量'),
                      subtitle: Text(state.volume.toStringAsFixed(2)),
                      onTap: () => Utils.copyText('音量\n${state.volume}'),
                    ),
                    ListTile(
                      dense: true,
                      title: const Text('解码器'),
                      subtitle: Text(
                        player.getProperty('decoder.video') ?? '未知',
                      ),
                      onTap: () => Utils.copyText(
                        '解码器\n${player.getProperty('decoder.video') ?? '未知'}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '确定',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 选择画质
  void showSetVideoQa() {
    if (videoInfo.dash == null) {
      SmartDialog.showToast('当前视频不支持选择画质');
      return;
    }
    final VideoQuality? currentVideoQa = videoDetailCtr.currentVideoQa.value;
    if (currentVideoQa == null) return;

    final List<FormatItem> videoFormat = videoInfo.supportFormats!;
    final availableQa = videoInfo.dash!.video!.availableVideoQualities;

    showBottomSheet(
      (context, setState) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            clipBehavior: Clip.hardEdge,
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 45,
                    child: GestureDetector(
                      onTap: () => SmartDialog.showToast(
                        '标灰画质需要bilibili会员（已是会员？请关闭无痕模式）；4k和杜比视界播放效果可能不佳',
                      ),
                      child: Row(
                        spacing: 8,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('选择画质', style: titleStyle),
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: theme.colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: videoFormat.length,
                  itemBuilder: (context, index) {
                    final item = videoFormat[index];
                    final isCurr = currentVideoQa.code == item.quality;
                    return ListTile(
                      dense: true,
                      onTap: () async {
                        if (isCurr) {
                          return;
                        }
                        Get.back();
                        final int quality = item.quality!;
                        final newQa = VideoQuality.fromCode(quality);
                        videoDetailCtr
                          ..plPlayerController.cacheVideoQa = newQa.code
                          ..currentVideoQa.value = newQa
                          ..updatePlayer();

                        SmartDialog.showToast("画质已变为：${newQa.desc}");

                        // update
                        if (!plPlayerController.tempPlayerConf) {
                          setting.put(
                            await ConnectivityUtils.isWiFi
                                ? SettingBoxKey.defaultVideoQa
                                : SettingBoxKey.defaultVideoQaCellular,
                            quality,
                          );
                        }
                      },
                      // 可能包含会员解锁画质
                      enabled: availableQa.contains(item.quality),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      title: Text(item.newDesc!),
                      trailing: isCurr
                          ? Icon(
                              Icons.done,
                              color: theme.colorScheme.primary,
                            )
                          : Text(
                              item.format!,
                              style: subTitleStyle,
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 选择音质
  void showSetAudioQa() {
    final AudioQuality currentAudioQa = videoDetailCtr.currentAudioQa!;
    final List<AudioItem> audio = videoInfo.dash!.audio!;
    showBottomSheet(
      (context, setState) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            clipBehavior: Clip.hardEdge,
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 45,
                    child: Center(
                      child: Text('选择音质', style: titleStyle),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: audio.length,
                  itemBuilder: (context, index) {
                    final item = audio[index];
                    final isCurr = currentAudioQa.code == item.id;
                    return ListTile(
                      dense: true,
                      onTap: () async {
                        if (isCurr) {
                          return;
                        }
                        Get.back();
                        final int quality = item.id;
                        final newQa = AudioQuality.fromCode(quality);
                        videoDetailCtr
                          ..plPlayerController.cacheAudioQa = newQa.code
                          ..currentAudioQa = newQa
                          ..updatePlayer();

                        SmartDialog.showToast("音质已变为：${newQa.desc}");

                        // update
                        if (!plPlayerController.tempPlayerConf) {
                          setting.put(
                            await ConnectivityUtils.isWiFi
                                ? SettingBoxKey.defaultAudioQa
                                : SettingBoxKey.defaultAudioQaCellular,
                            quality,
                          );
                        }
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      title: Text(item.quality),
                      subtitle: Text(
                        item.codecs!,
                        style: subTitleStyle,
                      ),
                      trailing: isCurr
                          ? Icon(
                              Icons.done,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showDanmakuPool() {
    final ctr = plPlayerController.danmakuController;
    if (ctr == null) return;
    showBottomSheet((context, setState) {
      final theme = Theme.of(context);
      return Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Column(
          children: [
            Container(
              height: 45,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('弹幕列表'),
                  iconButton(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Material(
                type: .transparency,
                clipBehavior: .hardEdge,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                child: CustomScrollView(
                  slivers: [
                    ?_buildDanmakuList(ctr.staticDanmaku.nonNulls.toList()),
                    ?_buildDanmakuList(
                      ctr.scrollDanmaku.expand((e) => e).toList(),
                    ),
                    ?_buildDanmakuList(ctr.specialDanmaku.toList()),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget? _buildDanmakuList(List<DanmakuItem<DanmakuExtra>> list) {
    if (list.isEmpty) return null;

    return SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final extra = item.content.extra! as VideoDanmaku;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          onLongPress: () => Utils.copyText(item.content.text),
          title: Text(
            item.content.text,
            style: const TextStyle(fontSize: 14),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Builder(
                builder: (context) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    iconButton(
                      onPressed: () async {
                        if (await HeaderControl.likeDanmaku(
                              extra,
                              plPlayerController.cid!,
                            ) &&
                            context.mounted) {
                          (context as Element).markNeedsBuild();
                        }
                      },
                      icon: extra.isLike
                          ? const Icon(CustomIcons.player_dm_tip_like_solid)
                          : const Icon(CustomIcons.player_dm_tip_like),
                    ),
                    if (extra.like > 0)
                      Positioned(
                        left: 24.5,
                        top: 1.5,
                        child: Text(
                          extra.like.toString(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0,
                            // fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (item.content.selfSend)
                iconButton(
                  onPressed: () => HeaderControl.deleteDanmaku(
                    extra.id,
                    plPlayerController.cid!,
                  ).then((_) => item.expired = true),
                  icon: const Icon(CustomIcons.player_dm_tip_recall),
                )
              else
                iconButton(
                  onPressed: () => HeaderControl.reportDanmaku(
                    context,
                    extra: extra,
                    ctr: plPlayerController,
                  ),
                  icon: const Icon(CustomIcons.player_dm_tip_back),
                ),
            ],
          ),
        );
      },
    );
  }

  late final isFileSource = videoDetailCtr.isFileSource;

  static const btnWidth = 42.0;
  static const btnHeight = 34.0;
  static const btnStyle = ButtonStyle(padding: WidgetStatePropertyAll(.zero));

  @override
  Widget build(BuildContext context) {
    final isFullScreen = this.isFullScreen;
    final isFSOrPip = isFullScreen || plPlayerController.isDesktopPip;
    final showFSActionItem =
        !isFileSource && plPlayerController.showFSActionItem && isFSOrPip;
    showCurrTimeIfNeeded(isFullScreen);

    Widget? title;
    if (introController.videoDetail.value.title != null &&
        (isFullScreen || (plPlayerController.isDesktopPip && !isPortrait))) {
      title = Padding(
        key: titleKey,
        padding: isPortrait
            ? EdgeInsets.zero
            : const EdgeInsets.only(right: 10),
        child: Obx(
          () {
            final videoDetail = introController.videoDetail.value;
            final String title;
            if (isFileSource || videoDetail.videos == 1) {
              title = videoDetail.title!;
            } else {
              title =
                  videoDetail.pages
                      ?.firstWhereOrNull(
                        (e) => e.cid == videoDetailCtr.cid.value,
                      )
                      ?.part ??
                  videoDetail.title!;
            }
            return MarqueeText(
              title,
              spacing: 30,
              velocity: 30,
              strutStyle: const StrutStyle(fontSize: 16, leading: 0),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              provider: effectiveProvider,
            );
          },
        ),
      );
      if (introController.isShowOnlineTotal) {
        title = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            Obx(
              () => Text(
                '${introController.total.value}人正在看',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        );
      }
    }

    return Padding(
      padding: const .symmetric(vertical: 12),
      child: Column(
        mainAxisSize: .min,
        children: [
          PlayerBar(
            left: Row(
              mainAxisSize: .min,
              children: [
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: IconButton(
                    tooltip: '返回',
                    style: btnStyle,
                    icon: const Icon(
                      FontAwesomeIcons.arrowLeft,
                      size: 15,
                      color: Colors.white,
                    ),
                    onPressed: () =>
                        plPlayerController.onPopInvokedWithResult(false, null),
                  ),
                ),
                if (!plPlayerController.isDesktopPip &&
                    (!isFullScreen || !isPortrait))
                  SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: IconButton(
                      tooltip: '返回主页',
                      style: btnStyle,
                      icon: const Icon(
                        FontAwesomeIcons.house,
                        size: 15,
                        color: Colors.white,
                      ),
                      onPressed: plPlayerController.onCloseAll,
                    ),
                  ),
              ],
            ),
            right: Row(
              mainAxisSize: .min,
              children: [
                // show current datetime
                ...?clockWidgets,
                if (PlatformUtils.isDesktop && !plPlayerController.isDesktopPip)
                  Obx(() {
                    final isAlwaysOnTop =
                        plPlayerController.isAlwaysOnTop.value;
                    return SizedBox(
                      width: btnWidth,
                      height: btnHeight,
                      child: IconButton(
                        style: btnStyle,
                        tooltip: '${isAlwaysOnTop ? '取消' : ''}置顶',
                        onPressed: () =>
                            plPlayerController.setAlwaysOnTop(!isAlwaysOnTop),
                        icon: isAlwaysOnTop
                            ? const Icon(
                                size: 19,
                                Icons.push_pin,
                                color: Colors.white,
                              )
                            : const Icon(
                                size: 19,
                                Icons.push_pin_outlined,
                                color: Colors.white,
                              ),
                      ),
                    );
                  }),
                if (!isFileSource) ...[
                  if (!isFSOrPip) ...[
                    if (videoDetailCtr.isUgc)
                      SizedBox(
                        width: btnWidth,
                        height: btnHeight,
                        child: IconButton(
                          tooltip: '听音频',
                          style: btnStyle,
                          onPressed: videoDetailCtr.toAudioPage,
                          icon: const Icon(
                            Icons.headphones_outlined,
                            size: 19,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: btnWidth,
                      height: btnHeight,
                      child: IconButton(
                        tooltip: '投屏',
                        style: btnStyle,
                        onPressed: videoDetailCtr.onCast,
                        icon: const Icon(
                          Icons.cast,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  if (kDebugMode || plPlayerController.enableSponsorBlock)
                    SizedBox(
                      width: btnWidth,
                      height: btnHeight,
                      child: IconButton(
                        tooltip: '提交片段',
                        style: btnStyle,
                        onPressed: () => videoDetailCtr.onBlock(context),
                        icon: const Icon(
                          CustomIcons.shield_play_arrow,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
                if (plPlayerController.enableBlock)
                  Obx(
                    () => videoDetailCtr.segmentProgressList.isNotEmpty
                        ? SizedBox(
                            width: btnWidth,
                            height: btnHeight,
                            child: IconButton(
                              tooltip: '片段信息',
                              style: btnStyle,
                              onPressed: videoDetailCtr.showSBDetail,
                              icon: const Icon(
                                MdiIcons.advertisements,
                                size: 19,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                if (!isPortrait || isFullScreen || PlatformUtils.isDesktop) ...[
                  SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: IconButton(
                      tooltip: '发弹幕',
                      style: btnStyle,
                      onPressed: videoDetailCtr.showShootDanmakuSheet,
                      icon: const Icon(
                        Icons.comment_outlined,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: Obx(
                      () {
                        final enableShowDanmaku =
                            plPlayerController.enableShowDanmaku.value;
                        return IconButton(
                          tooltip: '弹幕已关闭',
                          style: btnStyle,
                          onPressed: null,
                          icon: enableShowDanmaku
                              ? const Icon(
                                  size: 20,
                                  CustomIcons.dm_on,
                                  color: Colors.white,
                                )
                              : const Icon(
                                  size: 20,
                                  CustomIcons.dm_off,
                                  color: Colors.white,
                                ),
                        );
                      },
                    ),
                  ),
                ],
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: IconButton(
                    tooltip: '弹幕设置',
                    style: btnStyle,
                    onPressed: showSetDanmaku,
                    icon: const Icon(
                      size: 20,
                      CustomIcons.dm_settings,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (!isFullScreen)
                  SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: IconButton(
                      tooltip: '画中画',
                      style: btnStyle,
                      onPressed: plPlayerController.toggleDesktopPip,
                      icon: const Icon(
                        Icons.picture_in_picture_outlined,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                  ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: IconButton(
                    tooltip: "更多设置",
                    style: btnStyle,
                    onPressed: showSettingSheet,
                    icon: const Icon(
                      Icons.more_vert_outlined,
                      size: 19,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            title: title,
          ),
          if (showFSActionItem)
            Row(
              mainAxisAlignment: .end,
              crossAxisAlignment: .start,
              children: [
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: Obx(
                    () => ActionItem(
                      expand: false,
                      icon: const Icon(
                        FontAwesomeIcons.thumbsUp,
                        color: Colors.white,
                      ),
                      selectIcon: const Icon(FontAwesomeIcons.solidThumbsUp),
                      selectStatus: introController.hasLike.value,
                      semanticsLabel: '点赞',
                      animation: introController.tripleAnimation,
                      onStartTriple: () {
                        plPlayerController.tripling = true;
                        introController.onStartTriple();
                      },
                      onCancelTriple: ([bool isTapUp = false]) {
                        plPlayerController
                          ..tripling = false
                          ..hideTaskControls();
                        introController.onCancelTriple(isTapUp);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: Obx(
                    () => ActionItem(
                      expand: false,
                      animation: introController.tripleAnimation,
                      icon: const Icon(
                        FontAwesomeIcons.b,
                        color: Colors.white,
                      ),
                      selectIcon: const Icon(FontAwesomeIcons.b),
                      onTap: introController.actionCoinVideo,
                      selectStatus: introController.hasCoin,
                      semanticsLabel: '投币',
                    ),
                  ),
                ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: Obx(
                    () => ActionItem(
                      expand: false,
                      animation: introController.tripleAnimation,
                      icon: const Icon(
                        FontAwesomeIcons.star,
                        color: Colors.white,
                      ),
                      selectIcon: const Icon(FontAwesomeIcons.solidStar),
                      onTap: () => introController.showFavBottomSheet(context),
                      onLongPress: () => introController.showFavBottomSheet(
                        context,
                        isLongPress: true,
                      ),
                      selectStatus: introController.hasFav.value,
                      semanticsLabel: '收藏',
                    ),
                  ),
                ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: ActionItem(
                    expand: false,
                    icon: const Icon(CustomIcons.download, color: Colors.white),
                    onTap: () => videoDetailCtr.onDownload(context),
                    text: '缓存',
                    semanticsLabel: '缓存',
                  ),
                ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: ActionItem(
                    expand: false,
                    icon: const Icon(
                      FontAwesomeIcons.shareFromSquare,
                      color: Colors.white,
                    ),
                    onTap: () => introController.actionShareVideo(context),
                    semanticsLabel: '分享',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
