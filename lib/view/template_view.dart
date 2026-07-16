import 'dart:convert';
import 'package:drone_checklist/database/database_helper.dart';
import 'package:drone_checklist/helper/utils.dart';
import 'package:drone_checklist/model/template_model.dart';
import 'package:drone_checklist/view/template_select.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:drone_checklist/model/json_model.dart';
import 'package:drone_checklist/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drone_checklist/view/app_drawer.dart';
import 'package:drone_checklist/view/login_view.dart';

class TemplateView extends StatefulWidget {
  const TemplateView({super.key});

  @override
  State<TemplateView> createState() => _TemplateViewState();
}

class _TemplateViewState extends State<TemplateView> {
  Future<List<Template>>? _templatesFuture;
  String? _username;
  String? _email;
  Set<int> _downloadedTemplateIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username');
    _email = prefs.getString('email');
    await _checkDownloadedTemplates();
    setState(() {
      _templatesFuture = _getAllTemplate();
    });
  }

  Future<void> _checkDownloadedTemplates() async {
    if (_username == null) return;
    final localTemplates = await DatabaseHelper.getAllTemplates(_username!);
    setState(() {
      _downloadedTemplateIds = localTemplates
          .map((t) => t['serverTemplateId'] as int)
          .toSet();
    });
  }

  Future<List<Template>> _getAllTemplate() async {
    try {
      final dio = Dio();
      final client = ApiService(dio);

      String responseData = await client.getAllTemplate(_username ?? "");

      if (responseData.isNotEmpty) {
        final trimmedData = responseData.trim();
        if (trimmedData.isEmpty || trimmedData == "null") return [];
        
        var jsonData = jsonDecode(trimmedData);
        
        List<dynamic> list;
        if (jsonData is Map && jsonData.containsKey('data')) {
          list = jsonData['data'];
        } else if (jsonData is List) {
          list = jsonData;
        } else {
          return [];
        }

        List<Template> templates =
            List.from(list.map((model) => Template.fromJson(model)));
        return templates;
      } else {
        return [];
      }
    } on DioException catch (dioError){
      String errorMessage = _handleDioError(dioError);
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception("An unexpected error occured: $e");
    }
  }

  String _handleDioError(DioException error){
    switch (error.type){
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return "Connection timed out. Please check your internet connection.";
      case DioExceptionType.badResponse:
        return "Server error: ${error.response?.statusCode}. Please try again later.";
      case DioExceptionType.cancel:
        return "Request was cancelled.";
      case DioExceptionType.unknown:
        return "No connection available. Please check your network.";
      default:
        return "An unexpected error occured.";
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await prefs.remove('email');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginView()),
      );
    }
  }

  Future<void> _downloadTemplate(int templateId) async {
    if (_downloadedTemplateIds.contains(templateId)) {
      showAlert(context, "Already Downloaded", "This template is already in your downloaded list.", AlertType.failed, () {});
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dio = Dio();
      final apiService = ApiService(dio);
      final response = await apiService.downloadTemplate(templateId);
      
      Map<String, dynamic> templateData;
      if (response is String) {
        templateData = jsonDecode(response);
      } else if (response is Map) {
        templateData = Map<String, dynamic>.from(response);
      } else {
        throw Exception("Invalid response format");
      }

      Map<String, dynamic> templateFormData = {
        'assessment': templateData['assessment'] ?? {},
        'pre': templateData['pre'] ?? {},
        'post': templateData['post'] ?? {}
      };

      final templateModel = TemplateModel(
          templateId: null,
          serverTemplateId: templateData['id'] ?? templateId,
          templateName: templateData['templateName'] ?? "Unnamed Template",
          formType: 'assessment-pre-post',
          updatedDate: DateTime.now(),
          templateFormData: templateFormData,
          isPublic: templateData['is_public'] == 1,
          owner: _username,
          deletedAt: null
      );

      await DatabaseHelper.insertTemplate(templateModel, _username);
      await _checkDownloadedTemplates();

      if (mounted) {
        Navigator.pop(context);
        showAlert(context, "Success", "Template downloaded successfully", AlertType.success, () {});
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showAlert(context, "Failed", "Failed to download template: $e", AlertType.failed, () {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const String appTitle = 'Checklist Template';
    return Scaffold(
        appBar: AppBar(
          title: const Text(
            appTitle,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        drawer: AppDrawer(username: _username, email: _email, onLogout: _logout),
        body: RefreshIndicator(
          onRefresh: () async {
            await _checkDownloadedTemplates();
            setState(() {
              _templatesFuture = _getAllTemplate();
            });
          },
          child: FutureBuilder<List<Template>>(
            future: _templatesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text("Error: ${snapshot.error}", textAlign: TextAlign.center),
                  ),
                );
              } else if (snapshot.hasData) {
                if (snapshot.data!.isEmpty) {
                  return const Center(child: Text("No templates available."));
                }
                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    var template = snapshot.data![index];
                    bool isDownloaded = _downloadedTemplateIds.contains(template.id);
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.description, color: Colors.blue),
                        title: Text(template.templateName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: Text(isDownloaded ? "Already downloaded" : "Tap to view details"),
                        trailing: IconButton(
                          icon: Icon(Icons.download, color: isDownloaded ? Colors.grey : const Color(0xFFF9A825)),
                          onPressed: isDownloaded ? null : () => _downloadTemplate(template.id),
                          tooltip: isDownloaded ? 'Already Downloaded' : 'Download Template',
                        ),
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => TemplateSelect(
                                        templateId: template.id,
                                      )));
                          _checkDownloadedTemplates();
                        },
                      ),
                    );
                  },
                );
              } else {
                return const Center(child: Text("No data available"));
              }
            },
          ),
        ),
    );
  }
}
