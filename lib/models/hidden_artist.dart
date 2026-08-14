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
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final String hiddenColumnId = 'id';
final String hiddenColumnUserId = 'user_id';
final String hiddenColumnName = 'name';
final String hiddenColumnComment = 'comment';
final String tableHiddenArtist = 'hiddenartist';

class HiddenArtistPersist {
  String userId;
  String name;
  String comment;
  int? id;

  HiddenArtistPersist(
      {required this.userId, required this.name, this.comment = '', this.id});

  factory HiddenArtistPersist.fromJson(Map<String, dynamic> json) {
    return HiddenArtistPersist(
      id: json[hiddenColumnId],
      userId: json[hiddenColumnUserId],
      name: json[hiddenColumnName] ?? '',
      comment: json[hiddenColumnComment] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      hiddenColumnId: id,
      hiddenColumnUserId: userId,
      hiddenColumnName: name,
      hiddenColumnComment: comment,
    };
  }
}

class HiddenArtistProvider {
  late Database db;

  Future open() async {
    String databasesPath = (await getDatabasesPath());
    String path = join(databasesPath, 'hiddenartist.db');
    db = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      await db.execute('''
create table $tableHiddenArtist ( 
  $hiddenColumnId integer primary key autoincrement, 
  $hiddenColumnUserId text not null unique,
  $hiddenColumnName text not null,
  $hiddenColumnComment text not null
  )
''');
    });
  }

  Future<HiddenArtistPersist> insert(HiddenArtistPersist todo) async {
    todo.id = await db.insert(tableHiddenArtist, todo.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return todo;
  }

  Future<HiddenArtistPersist?> getByUserId(String userId) async {
    List<Map<String, dynamic>> maps = await db.query(tableHiddenArtist,
        columns: [hiddenColumnId, hiddenColumnUserId, hiddenColumnName, hiddenColumnComment],
        where: '$hiddenColumnUserId = ?',
        whereArgs: [userId]);
    if (maps.isNotEmpty) return HiddenArtistPersist.fromJson(maps.first);
    return null;
  }

  Future<List<HiddenArtistPersist>> getAll() async {
    List<Map<String, dynamic>> maps = await db.query(tableHiddenArtist,
        columns: [hiddenColumnId, hiddenColumnUserId, hiddenColumnName, hiddenColumnComment]);
    return maps.map((f) => HiddenArtistPersist.fromJson(f)).toList();
  }

  Future<int> delete(int id) async {
    return await db
        .delete(tableHiddenArtist, where: '$hiddenColumnId = ?', whereArgs: [id]);
  }

  Future<int> deleteAll() async {
    return await db.delete(tableHiddenArtist);
  }

  Future<int> update(HiddenArtistPersist todo) async {
    return await db.update(tableHiddenArtist, todo.toJson(),
        where: '$hiddenColumnId = ?', whereArgs: [todo.id]);
  }

  Future close() async => db.close();
}
