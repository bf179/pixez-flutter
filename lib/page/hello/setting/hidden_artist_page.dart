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
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/hidden_artist.dart';
import 'package:pixez/saf_plugin.dart';

/// 隐藏画师列表管理页（仅安卓）
/// 支持：搜索（uid/画师名/备注）、新增（批量，每行一个 uid）、编辑、删除、
/// txt/sqlite 导入导出、一键清空；列表展示头像、名称与作品预览
class HiddenArtistPage extends StatefulWidget {
  @override
  _HiddenArtistPageState createState() => _HiddenArtistPageState();
}

class _HiddenArtistPageState extends State<HiddenArtistPage> {
  String _keyword = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    discoveryStore.loadHidden();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HiddenArtistPersist> _filtered() {
    final list = discoveryStore.hiddenArtists;
    if (_keyword.isEmpty) return list.toList();
    final kw = _keyword.toLowerCase();
    return list
        .where((e) =>
            e.userId.toLowerCase().contains(kw) ||
            e.name.toLowerCase().contains(kw) ||
            e.comment.toLowerCase().contains(kw))
        .toList();
  }

  // ---------- 导入 / 导出 ----------

  Future<void> _importTxt() async {
    final data = await SAFPlugin.openFile(type: 'text/plain');
    if (data == null) return;
    final text = utf8.decode(data, allowMalformed: true);
    BotToast.showLoading();
    final n = await discoveryStore.importHiddenFromText(text);
    BotToast.closeAllLoading();
    BotToast.showText(text: n > 0 ? '导入完成，新增 $n 位画师' : '没有可导入的新画师（uid 已去重）');
  }

  Future<void> _importSqlite() async {
    final data = await SAFPlugin.openFile(type: 'application/octet-stream');
    if (data == null) return;
    BotToast.showLoading();
    final n = await discoveryStore.importHiddenFromSqlite(data);
    BotToast.closeAllLoading();
    BotToast.showText(text: n > 0 ? '导入完成，新增 $n 位画师' : '没有可导入的新画师（uid 已去重）');
  }

  Future<void> _exportTxt() async {
    final list = discoveryStore.hiddenArtists;
    if (list.isEmpty) {
      BotToast.showText(text: '列表为空');
      return;
    }
    final content = list.map((e) => e.userId).join('\n');
    final uri = await SAFPlugin.createFile(
        'hidden_artists_${DateTime.now().millisecondsSinceEpoch}.txt',
        'text/plain');
    if (uri != null) {
      await SAFPlugin.writeUri(uri, utf8.encode(content));
      BotToast.showText(text: '已导出 ${list.length} 条（一行一个 uid）');
    }
  }

  Future<void> _exportSqlite() async {
    BotToast.showLoading();
    final ok = await discoveryStore.exportHiddenToSqlite();
    BotToast.closeAllLoading();
    BotToast.showText(text: ok ? '已导出 sqlite 数据库' : '导出失败');
  }

  Future<void> _clearAll() async {
    final result = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空隐藏画师列表'),
        content: Text('确定要清空全部 ${discoveryStore.hiddenArtists.length} 位隐藏画师吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'OK'),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (result == 'OK') {
      await discoveryStore.clearHidden();
      BotToast.showText(text: '已清空');
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量添加隐藏画师'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '每行一个画师 uid\n支持一次粘贴多个',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    BotToast.showLoading();
    final n = await discoveryStore.importHiddenFromText(result);
    BotToast.closeAllLoading();
    BotToast.showText(
        text: n > 0 ? '已添加 $n 位画师（uid 已去重）' : '没有可添加的画师（uid 无效或已存在）');
  }

  Future<void> _edit(HiddenArtistPersist e) async {
    final nameController = TextEditingController(text: e.name);
    final commentController = TextEditingController(text: e.comment);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑隐藏画师'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: '画师名', hintText: e.userId),
            ),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(labelText: '备注'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == true) {
      e.name = nameController.text.trim().isEmpty
          ? e.userId
          : nameController.text.trim();
      e.comment = commentController.text.trim();
      await discoveryStore.updateHidden(e);
      BotToast.showText(text: '已保存');
    }
  }

  Future<void> _delete(HiddenArtistPersist e) async {
    final result = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: Text('删除隐藏画师 ${e.name}（uid: ${e.userId}）？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'OK'),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (result == 'OK') {
      await discoveryStore.removeHidden(e.id!);
    }
  }

  Widget _buildPreviewRow(HiddenArtistPersist e) {
    return Observer(builder: (_) {
      final detail = discoveryStore.hiddenArtistDetails[e.userId];
      final previews = detail?.previewUrls ?? const [];
      return Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: i < previews.length
                    ? PixivImage(
                        previews[i],
                        fit: BoxFit.cover,
                        enableMemoryCache: false,
                      )
                    : Container(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
              ),
            ),
        ],
      );
    });
  }

  Widget _buildAvatar(HiddenArtistPersist e) {
    return Observer(builder: (_) {
      final avatar = discoveryStore.hiddenArtistDetails[e.userId]?.avatarUrl;
      return ClipOval(
        child: SizedBox(
          width: 40,
          height: 40,
          child: avatar != null
              ? PixivImage(
                  avatar,
                  fit: BoxFit.cover,
                  enableMemoryCache: false,
                )
              : Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Text(
                    String.fromCharCode(
                        (e.name.isNotEmpty ? e.name : e.userId).runes.first),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐藏画师列表'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入',
            onSelected: (v) {
              if (v == 'txt') _importTxt();
              if (v == 'sqlite') _importSqlite();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'txt', child: Text('导入 txt（每行一个 uid）')),
              PopupMenuItem(value: 'sqlite', child: Text('导入 sqlite 数据库')),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导出',
            onSelected: (v) {
              if (v == 'txt') _exportTxt();
              if (v == 'sqlite') _exportSqlite();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'txt', child: Text('导出 txt')),
              PopupMenuItem(value: 'sqlite', child: Text('导出 sqlite 数据库')),
            ],
          ),
          IconButton(
            tooltip: '一键清空',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜索 uid / 画师名 / 备注',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _keyword = v.trim()),
            ),
          ),
          Expanded(
            child: Observer(builder: (_) {
              final list = _filtered();
              if (list.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_off_outlined,
                          size: 48, color: Theme.of(context).disabledColor),
                      const SizedBox(height: 8),
                      Text(_keyword.isEmpty
                          ? '暂无隐藏画师，点击右下角添加'
                          : '没有匹配的结果'),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final e = list[index];
                  // 按需异步拉取头像与作品预览（内部去重）
                  discoveryStore.loadHiddenDetail(e.userId);
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPreviewRow(e),
                        ListTile(
                          leading: _buildAvatar(e),
                          title: Text(
                            e.name.isEmpty ? e.userId : e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            e.comment.isEmpty
                                ? 'uid: ${e.userId}'
                                : '${e.comment} · uid: ${e.userId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(e),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '批量添加隐藏画师',
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
    );
  }
}
