/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */
import 'package:dio/dio.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/followed_artist.dart';
import 'package:pixez/models/hidden_artist.dart';
import 'package:pixez/models/user_detail.dart';
import 'package:pixez/models/user_preview.dart';
import 'package:pixez/network/api_client.dart';

/// 发现过滤相关：
/// 1. 隐藏已关注画师的作品（关注列表缓存本地数据库，关注/取关即时更新）
/// 2. 隐藏已收藏的作品
/// 3. 隐藏画师列表（uid 去重，支持导入导出搜索清空）
///
/// 说明：不使用 mobx 代码生成，观察能力全部由运行时 Observable 集合
/// （ObservableMap / ObservableSet / ObservableList）提供，开关状态也存
/// 在 ObservableMap 中并同步到 SharedPreferences，读取即建立观察依赖。
class DiscoveryStore {
  static const String HIDE_FOLLOWED_KEY = 'hide_followed_artists';
  static const String HIDE_FAVORITED_KEY = 'hide_favorited_works';

  final FollowedArtistProvider followedProvider = FollowedArtistProvider();
  final HiddenArtistProvider hiddenProvider = HiddenArtistProvider();

  /// 开关状态（可观察，同步持久化到 SharedPreferences）
  final ObservableMap<String, bool> _flags = ObservableMap();

  /// 已关注画师 uid（缓存，即时更新）
  final ObservableSet<String> followedUids = ObservableSet();

  /// 隐藏列表画师 uid（由 hiddenArtists 派生，便于快速查找）
  final ObservableSet<String> hiddenUids = ObservableSet();

  /// 隐藏画师列表（完整信息）
  final ObservableList<HiddenArtistPersist> hiddenArtists = ObservableList();

  bool _syncing = false;

  /// 当前打开的详情页数量（嵌套详情页计数）。
  /// 详情页打开期间，列表的发现过滤暂停执行，避免正在查看的作品被
  /// 即时隐藏并导致详情页自动跳到下一张；退出详情页后过滤恢复生效。
  /// 使用可观察集合存储，退出详情页（移除元素）会触发列表重新过滤。
  final ObservableSet<int> _detailViewIds = ObservableSet();
  int _detailViewSeq = 0;

  bool get syncing => _syncing;

  bool get detailViewOpen => _detailViewIds.isNotEmpty;

  void enterDetailView() => _detailViewIds.add(_detailViewSeq++);

  void leaveDetailView() {
    if (_detailViewIds.isNotEmpty) {
      _detailViewIds.remove(_detailViewIds.last);
    }
  }

  bool get hideFollowedArtists => _flags[HIDE_FOLLOWED_KEY] ?? false;

  bool get hideFavoritedWorks => _flags[HIDE_FAVORITED_KEY] ?? false;

  Future<void> init() async {
    await Prefer.init();
    _flags[HIDE_FOLLOWED_KEY] = Prefer.getBool(HIDE_FOLLOWED_KEY) ?? false;
    _flags[HIDE_FAVORITED_KEY] = Prefer.getBool(HIDE_FAVORITED_KEY) ?? false;
    await loadFollowed();
    await loadHidden();
  }

  Future<void> loadFollowed() async {
    await followedProvider.open();
    final list = await followedProvider.getAll();
    followedUids
      ..clear()
      ..addAll(list.map((e) => e.userId));
  }

  Future<void> loadHidden() async {
    await hiddenProvider.open();
    final list = await hiddenProvider.getAll();
    hiddenArtists
      ..clear()
      ..addAll(list);
    hiddenUids
      ..clear()
      ..addAll(list.map((e) => e.userId));
  }

  Future<void> setHideFollowedArtists(bool value) async {
    _flags[HIDE_FOLLOWED_KEY] = value;
    await Prefer.setBool(HIDE_FOLLOWED_KEY, value);
    if (value) {
      // 开启时懒同步一次，保证缓存与服务器一致
      await syncFollowed();
    }
  }

  Future<void> setHideFavoritedWorks(bool value) async {
    _flags[HIDE_FAVORITED_KEY] = value;
    await Prefer.setBool(HIDE_FAVORITED_KEY, value);
  }

  // ---------- 关注列表缓存（即时更新） ----------

  /// 关注了新画师：写入缓存，避免下次过滤重新拉全量列表
  Future<void> onFollow(int userId, String name) async {
    final uid = userId.toString();
    await followedProvider.open();
    final exist = await followedProvider.getByUserId(uid);
    if (exist != null) {
      exist.name = name.isEmpty ? exist.name : name;
      await followedProvider.update(exist);
    } else {
      await followedProvider
          .insert(FollowedArtistPersist(userId: uid, name: name));
    }
    followedUids.add(uid);
  }

  /// 取消关注了画师：从缓存移除
  Future<void> onUnfollow(int userId) async {
    final uid = userId.toString();
    await followedProvider.open();
    final exist = await followedProvider.getByUserId(uid);
    if (exist != null) {
      await followedProvider.delete(exist.id!);
    }
    followedUids.remove(uid);
  }

  /// 全量同步关注列表（public + private），分页拉取，返回同步数量
  /// 每页请求之间加入延迟限流，避免触发服务器 429
  Future<int> syncFollowed() async {
    if (_syncing) return 0;
    _syncing = true;
    try {
      if (accountStore.now == null) return 0;
      final userId = int.parse(accountStore.now!.userId);
      final collected = <String, String>{};
      for (final restrict in ['public', 'private']) {
        String? nextUrl = null;
        do {
          Response response;
          if (nextUrl == null || nextUrl!.isEmpty) {
            response = await apiClient.getUserFollowing(userId, restrict);
          } else {
            response = await apiClient.getNext(nextUrl);
          }
          final data = UserPreviewsResponse.fromJson(response.data);
          for (final u in data.user_previews) {
            collected[u.user.id.toString()] = u.user.name;
          }
          nextUrl = data.next_url;
          // 请求间隔，避免频率过高被服务器限流（429）
          await Future.delayed(const Duration(milliseconds: 300));
        } while (nextUrl != null && nextUrl.isNotEmpty);
        // 切换 restrict 时也稍作停顿
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (collected.isEmpty) return 0;
      await followedProvider.open();
      await followedProvider.insertAll(collected.entries
          .map((e) => FollowedArtistPersist(userId: e.key, name: e.value))
          .toList());
      followedUids
        ..clear()
        ..addAll(collected.keys);
      return collected.length;
    } catch (e) {
      return 0;
    } finally {
      _syncing = false;
    }
  }

  // ---------- 隐藏画师列表 ----------

  /// 新增/更新隐藏画师（按 uid 去重）
  Future<void> addHidden(String uid, String name, {String comment = ''}) async {
    await hiddenProvider.open();
    final exist = await hiddenProvider.getByUserId(uid);
    if (exist != null) {
      if (name.isNotEmpty && name != uid) exist.name = name;
      if (comment.isNotEmpty) exist.comment = comment;
      await hiddenProvider.update(exist);
    } else {
      await hiddenProvider.insert(
          HiddenArtistPersist(userId: uid, name: name, comment: comment));
    }
    await loadHidden();
  }

  Future<void> updateHidden(HiddenArtistPersist e) async {
    await hiddenProvider.open();
    await hiddenProvider.update(e);
    await loadHidden();
  }

  Future<void> removeHidden(int id) async {
    await hiddenProvider.open();
    await hiddenProvider.delete(id);
    await loadHidden();
  }

  Future<void> clearHidden() async {
    await hiddenProvider.open();
    await hiddenProvider.deleteAll();
    await loadHidden();
  }

  /// 从文本导入（一行一个 uid），自动去重，导入后异步补充画师名
  Future<int> importHiddenFromText(String text) async {
    final uids = text
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && int.tryParse(e) != null)
        .toSet();
    if (uids.isEmpty) return 0;
    await hiddenProvider.open();
    var added = 0;
    for (final uid in uids) {
      final exist = await hiddenProvider.getByUserId(uid);
      if (exist == null) {
        await hiddenProvider.insert(
            HiddenArtistPersist(userId: uid, name: uid, comment: ''));
        added++;
      }
    }
    await loadHidden();
    if (added > 0) {
      enrichNames(uids);
    }
    return added;
  }

  /// 后台补充隐藏画师名称（失败忽略）
  Future<void> enrichNames(Iterable<String> uids) async {
    for (final uid in uids) {
      try {
        final e = await hiddenProvider.getByUserId(uid);
        if (e == null) continue;
        if (e.name.isNotEmpty && e.name != uid) continue;
        final response = await apiClient.getUser(int.parse(uid));
        final detail = UserDetail.fromJson(response.data);
        e.name = detail.user.name;
        await hiddenProvider.update(e);
      } catch (e) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await loadHidden();
  }
}
