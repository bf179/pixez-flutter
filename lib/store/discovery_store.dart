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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/followed_artist.dart';
import 'package:pixez/models/hidden_artist.dart';
import 'package:pixez/models/user_detail.dart';
import 'package:pixez/models/user_preview.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/saf_plugin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 隐藏画师的详情缓存（头像 + 作品预览，运行时拉取，不落库）
class HiddenArtistDetail {
  final String? avatarUrl;
  final List<String> previewUrls;

  HiddenArtistDetail({this.avatarUrl, this.previewUrls = const []});
}

/// 发现过滤相关：
/// 1. 隐藏已关注画师的作品（关注列表按账号缓存本地数据库，关注/取关即时更新）
/// 2. 隐藏已收藏的作品
/// 3. 隐藏画师列表（uid 去重，支持导入导出搜索清空，对所有账号生效）
/// 4. 多账号：关注列表按账号隔离；"隐藏公共关注库"开启后所有账号的关注一并隐藏
///
/// 说明：不使用 mobx 代码生成，观察能力全部由运行时 Observable 集合
/// （ObservableMap / ObservableSet / ObservableList）提供，开关状态也存
/// 在 ObservableMap 中并同步到 SharedPreferences，读取即建立观察依赖。
class DiscoveryStore {
  static const String HIDE_FOLLOWED_KEY = 'hide_followed_artists';
  static const String HIDE_FAVORITED_KEY = 'hide_favorited_works';

  /// 隐藏公共关注库：开启后所有登录账号的关注画师都会被隐藏；
  /// 关闭则仅隐藏当前账号的关注画师（其他账号的关注不受影响）
  static const String HIDE_PUBLIC_FOLLOWED_KEY = 'hide_public_followed';

  final FollowedArtistProvider followedProvider = FollowedArtistProvider();
  final HiddenArtistProvider hiddenProvider = HiddenArtistProvider();

  /// 开关状态（可观察，同步持久化到 SharedPreferences）
  final ObservableMap<String, bool> _flags = ObservableMap();

  /// 已关注画师 uid（按当前账号 + 公共关注库开关过滤后的缓存）
  final ObservableSet<String> followedUids = ObservableSet();

  /// 隐藏列表画师 uid（由 hiddenArtists 派生，便于快速查找）
  final ObservableSet<String> hiddenUids = ObservableSet();

  /// 隐藏画师列表（完整信息）
  final ObservableList<HiddenArtistPersist> hiddenArtists = ObservableList();

  /// 隐藏画师详情缓存（头像 + 作品预览）
  final ObservableMap<String, HiddenArtistDetail> hiddenArtistDetails =
      ObservableMap();

  bool _syncing = false;

  Timer? _syncTimer;

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

  bool get hidePublicFollowed => _flags[HIDE_PUBLIC_FOLLOWED_KEY] ?? false;

  String? get _currentAccountId => accountStore.now?.userId;

  Future<void> init() async {
    await Prefer.init();
    _flags[HIDE_FOLLOWED_KEY] = Prefer.getBool(HIDE_FOLLOWED_KEY) ?? false;
    _flags[HIDE_FAVORITED_KEY] = Prefer.getBool(HIDE_FAVORITED_KEY) ?? false;
    _flags[HIDE_PUBLIC_FOLLOWED_KEY] =
        Prefer.getBool(HIDE_PUBLIC_FOLLOWED_KEY) ?? false;
    await loadFollowed();
    await loadHidden();
    // 多账号：切换账号时重新按当前账号加载关注缓存
    reaction((_) => accountStore.now, (_) => loadFollowed());
    startPeriodicSync();
  }

  /// 后台定时同步关注列表（每 6 小时一次），保证缓存与服务器一致
  void startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(hours: 6), (_) {
      if (hideFollowedArtists || hidePublicFollowed) {
        syncFollowed();
      }
    });
  }

  Future<void> loadFollowed() async {
    await followedProvider.open();
    final list = await followedProvider.getAll();
    final currentAccountId = _currentAccountId;
    followedUids.clear();
    for (final e in list) {
      if (hidePublicFollowed) {
        // 公共关注库：所有账号的关注都隐藏
        followedUids.add(e.userId);
      } else if (e.accountId == null || e.accountId == currentAccountId) {
        // 仅当前账号（accountId 为 null 的旧数据视为当前账号）
        followedUids.add(e.userId);
      }
    }
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
    } else {
      await loadFollowed();
    }
  }

  Future<void> setHideFavoritedWorks(bool value) async {
    _flags[HIDE_FAVORITED_KEY] = value;
    await Prefer.setBool(HIDE_FAVORITED_KEY, value);
  }

  /// 隐藏公共关注库：开启后所有账号的关注都被隐藏，关闭则仅隐藏当前账号的关注
  Future<void> setHidePublicFollowed(bool value) async {
    _flags[HIDE_PUBLIC_FOLLOWED_KEY] = value;
    await Prefer.setBool(HIDE_PUBLIC_FOLLOWED_KEY, value);
    if (value) {
      await syncFollowed();
    } else {
      await loadFollowed();
    }
  }

  // ---------- 关注列表缓存（即时更新，按账号隔离） ----------

  /// 关注了新画师：写入当前账号缓存
  Future<void> onFollow(int userId, String name) async {
    final uid = userId.toString();
    final accountId = _currentAccountId;
    await followedProvider.open();
    var exist = await followedProvider.getByUserId(uid, accountId);
    if (exist == null && accountId != null) {
      // 采纳旧数据（account_id 为 null 的公共记录）归属到当前账号
      exist = await followedProvider.getByUserId(uid, null);
      if (exist != null) {
        exist.accountId = accountId;
        exist.name = name.isEmpty ? exist.name : name;
        await followedProvider.update(exist);
      }
    }
    if (exist != null) {
      exist.name = name.isEmpty ? exist.name : name;
      await followedProvider.update(exist);
    } else {
      await followedProvider.insert(
          FollowedArtistPersist(userId: uid, name: name, accountId: accountId));
    }
    followedUids.add(uid);
  }

  /// 取消关注了画师：从当前账号缓存移除（含旧数据公共记录）
  Future<void> onUnfollow(int userId) async {
    final uid = userId.toString();
    final accountId = _currentAccountId;
    await followedProvider.open();
    var exist = await followedProvider.getByUserId(uid, accountId);
    if (exist == null && accountId != null) {
      exist = await followedProvider.getByUserId(uid, null);
    }
    if (exist != null) {
      await followedProvider.delete(exist.id!);
    }
    followedUids.remove(uid);
  }

  /// 全量同步当前账号关注列表（public + private），分页拉取，返回同步数量。
  /// 每页请求之间间隔 2000ms 限流，避免触发服务器 429。
  Future<int> syncFollowed() async {
    if (_syncing) return 0;
    _syncing = true;
    try {
      if (accountStore.now == null) return 0;
      final accountId = accountStore.now!.userId;
      final userId = int.parse(accountId);
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
          // 请求间隔 2 秒，避免频率过高被服务器限流（429）
          await Future.delayed(const Duration(milliseconds: 2000));
        } while (nextUrl != null && nextUrl.isNotEmpty);
        // 切换 restrict 时也稍作停顿
        await Future.delayed(const Duration(milliseconds: 2000));
      }
      if (collected.isEmpty) return 0;
      await followedProvider.open();
      // 先清空当前账号旧缓存（含迁移前的公共记录），避免残留已取关的画师
      await followedProvider.deleteByAccount(accountId);
      await followedProvider.deleteByAccount(null);
      await followedProvider.insertAll(collected.entries
          .map((e) => FollowedArtistPersist(
              userId: e.key, name: e.value, accountId: accountId))
          .toList());
      await loadFollowed();
      return collected.length;
    } catch (e) {
      return 0;
    } finally {
      _syncing = false;
    }
  }

  // ---------- 隐藏画师列表（对所有账号生效） ----------

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
    String? uid;
    for (final e in hiddenArtists) {
      if (e.id == id) {
        uid = e.userId;
        break;
      }
    }
    await hiddenProvider.open();
    await hiddenProvider.delete(id);
    await loadHidden();
    if (uid != null) hiddenArtistDetails.remove(uid);
  }

  Future<void> clearHidden() async {
    await hiddenProvider.open();
    await hiddenProvider.deleteAll();
    await loadHidden();
    hiddenArtistDetails.clear();
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

  /// 从 sqlite 文件导入隐藏画师列表（合并，uid 去重）
  Future<int> importHiddenFromSqlite(Uint8List bytes) async {
    final dbPath = join(await getDatabasesPath(), 'import_hidden_tmp.db');
    await File(dbPath).writeAsBytes(bytes);
    final tmp = await openDatabase(dbPath, readOnly: true);
    final rows = await tmp.query(tableHiddenArtist);
    await tmp.close();
    try {
      await File(dbPath).delete();
    } catch (e) {}
    var added = 0;
    final uids = <String>{};
    await hiddenProvider.open();
    for (final row in rows) {
      final uid = row[hiddenColumnUserId]?.toString();
      if (uid == null || int.tryParse(uid) == null) continue;
      if (uids.contains(uid)) continue;
      uids.add(uid);
      final exist = await hiddenProvider.getByUserId(uid);
      if (exist == null) {
        await hiddenProvider.insert(HiddenArtistPersist(
          userId: uid,
          name: row[hiddenColumnName]?.toString() ?? uid,
          comment: row[hiddenColumnComment]?.toString() ?? '',
        ));
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

  /// 导出关注列表数据库文件（sqlite）
  Future<bool> exportFollowedToSqlite() async {
    return _exportDb('followedartist.db', 'followed_artists');
  }

  /// 导出隐藏画师列表数据库文件（sqlite）
  Future<bool> exportHiddenToSqlite() async {
    return _exportDb('hiddenartist.db', 'hidden_artists');
  }

  Future<bool> _exportDb(String dbFile, String prefix) async {
    try {
      final dbPath = join(await getDatabasesPath(), dbFile);
      await followedProvider.open();
      await hiddenProvider.open();
      // 先做 WAL checkpoint，确保主库文件包含全部最新数据
      final db = dbFile == 'followedartist.db'
          ? followedProvider.db
          : hiddenProvider.db;
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (e) {}
      // 关闭数据库连接以便安全读取文件（导出后重新打开）
      if (dbFile == 'followedartist.db') {
        await followedProvider.close();
      } else {
        await hiddenProvider.close();
      }
      final bytes = await File(dbPath).readAsBytes();
      if (dbFile == 'followedartist.db') {
        await followedProvider.open();
      } else {
        await hiddenProvider.open();
      }
      final uri = await SAFPlugin.createFile(
          '${prefix}_${DateTime.now().millisecondsSinceEpoch}.db',
          'application/octet-stream');
      if (uri == null) return false;
      await SAFPlugin.writeUri(uri, bytes);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ---------- 隐藏画师详情缓存（头像 + 作品预览） ----------

  final Set<String> _loadingDetails = {};

  /// 异步拉取隐藏画师的头像与作品预览并缓存（失败静默）
  Future<void> loadHiddenDetail(String uid) async {
    if (hiddenArtistDetails.containsKey(uid)) return;
    if (_loadingDetails.contains(uid)) return;
    _loadingDetails.add(uid);
    try {
      final id = int.tryParse(uid);
      if (id == null) return;
      String? avatar;
      final userResp = await apiClient.getUser(id);
      final detail = UserDetail.fromJson(userResp.data);
      avatar = detail.user.profileImageUrls.medium;

      List<String> previews = [];
      try {
        final illustResp = await apiClient.getUserIllusts(id, 'illust');
        final decoded = jsonDecode(illustResp.data);
        final list = (decoded['illusts'] as List? ?? []);
        previews = list
            .take(3)
            .map((e) => (e['image_urls']?['square_medium'] ?? '') as String)
            .where((u) => u.isNotEmpty)
            .toList();
      } catch (e) {}

      hiddenArtistDetails[uid] =
          HiddenArtistDetail(avatarUrl: avatar, previewUrls: previews);
    } catch (e) {
      // 拉取失败留空，不缓存，允许下次重试
    } finally {
      _loadingDetails.remove(uid);
    }
  }
}
