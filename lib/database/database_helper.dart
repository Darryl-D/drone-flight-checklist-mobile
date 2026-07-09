import 'package:drone_checklist/model/form_model.dart';
import 'package:drone_checklist/model/template_model.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'dart:convert';

class DatabaseHelper {
  static Future<void> createTables(sqlite.Database database) async {
    //aktifkan foreign key
    await database.execute("PRAGMA foreign_keys = ON");

    //membuat table template
    await database.execute('''CREATE TABLE template(
      templateId INTEGER PRIMARY KEY AUTOINCREMENT,
      serverTemplateId INTEGER,
      templateName TEXT,      
      formType TEXT,
      updatedDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      templateFormData TEXT,
      owner TEXT,
      is_public INTEGER DEFAULT 0,
      deletedAt TIMESTAMP
    )
    ''');

    //membuat table form
    await database.execute('''CREATE TABLE form (
      formId INTEGER PRIMARY KEY AUTOINCREMENT,
      serverTemplateId INTEGER,
      templateId INTEGER,
      formName TEXT,
      updatedDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      formData TEXT,
      updatedFormData TEXT,
      syncStatus INTEGER DEFAULT 0,
      owner TEXT,
      deletedAt TIMESTAMP
      )
    ''');

    // User table for local session if needed, though usually handled by SharedPreferences
    await database.execute('''CREATE TABLE user (
      username TEXT PRIMARY KEY,
      email TEXT
    )''');
  }

  //jika database ada maka buka
  static Future<sqlite.Database> db() async {
    return sqlite.openDatabase(
      "drone_checklist.db", version: 2, // Incremented version
      //jika tidak ada maka buat database baru
      onCreate: (sqlite.Database database, int version) async {
        await createTables(database);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Simple upgrade: drop and recreate for this specific update
          // In a real app, use ALTER TABLE
          await db.execute("DROP TABLE IF EXISTS template");
          await db.execute("DROP TABLE IF EXISTS form");
          await db.execute("DROP TABLE IF EXISTS user");
          await createTables(db);
        }
      },
      onOpen: (db) async {
        await db.execute("PRAGMA foreign_keys = ON");
      },
    );
  }

  static Future<void> updateSyncStatus(int formId, int syncStatus) async {
    final db = await DatabaseHelper.db();

    await db.update('form', {'syncStatus': syncStatus},
        where: 'formId = ?', whereArgs: [formId]);
  }

  static Future<int> createForm(FormModel model, String? owner) async {
    final db = await DatabaseHelper.db();

    final form = {
      'templateId': model.templateId,
      'serverTemplateId': model.serverTemplateId,
      'formName': model.formName,
      'formData': jsonEncode(model.formData),
      'updatedFormData': jsonEncode(model.updatedFormData),
      'owner': owner,
      'deletedAt': null
    };

    final formId = await db.insert('form', form);
    return formId;
  }

  static Future<int> updateForm(
      int formId, String formData, String updatedFormData) async {
    final db = await DatabaseHelper.db();

    final form = {
      'formData': formData,
      'updatedFormData': updatedFormData
    };

    final result =
        await db.update("form", form, where: "formId = ?", whereArgs: [formId]);

    return result;
  }

  static Future<int> updateFormTitle(int formId, String newTitle) async {
    final db = await DatabaseHelper.db();
    return await db.update(
      'form',
      {'formName': newTitle},
      where: 'formId = ?',
      whereArgs: [formId],
    );
  }

  static Future<void> deleteForm(int formId) async {
    final db = await DatabaseHelper.db();

    try {
      await db.delete('form', where: "formId = ?", whereArgs: [formId]);
    } catch (e) {
      print("Delete Failed: $e");
    }
  }

  static Future<void> deleteTemplate(int templateId) async {
    final db = await DatabaseHelper.db();

    try {
      await db
          .delete('template', where: "templateId = ?", whereArgs: [templateId]);
    } catch (e) {
      print("Delete Failed: $e");
    }
  }


  static Future<int> insertTemplate(TemplateModel model, String? owner) async {
    final db = await DatabaseHelper.db();

    final template = {
      'serverTemplateId' : model.serverTemplateId,
      'templateName' : model.templateName,
      'formType' : model.formType,
      'templateFormData' : jsonEncode(model.templateFormData),
      'owner': owner,
      'is_public': model.isPublic ? 1 : 0,
      'deletedAt' : null
    };

    final templateId = await db.insert('template', template);
    return templateId;
  }

  static Future<List<Map<String, dynamic>>> getAllForms(String username) async {
    final db = await DatabaseHelper.db();
    return db.query("form", where: "owner = ?", whereArgs: [username], orderBy: "formId");
  }

  static Future<List<Map<String, dynamic>>> getAllTemplates(String username) async {
    final db = await DatabaseHelper.db();
    // Local templates are those downloaded by the user
    return await db.query('template', where: "owner = ?", whereArgs: [username]);
  }

  static Future<Map<String, dynamic>?> getFormById(int id) async {
    final db = await DatabaseHelper.db();
    List<Map> results = await db.query(
      'form',
      where: 'formId = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return Map<String, dynamic>.from(results.first);
    }
    return null;
  }

  static Future<Map<String, dynamic>> getTemplateById(int id) async {
    final db = await DatabaseHelper.db();
    List<Map> results = await db.query(
      'template',
      where: 'templateId = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return Map<String, dynamic>.from(results.first);
    }
    return <String, dynamic>{};
  }
}
