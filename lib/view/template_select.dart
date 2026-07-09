import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drone_checklist/database/database_helper.dart';
import 'package:drone_checklist/helper/utils.dart';
import 'package:drone_checklist/model/template_model.dart';
import 'package:flutter/material.dart';
import 'package:drone_checklist/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TemplateSelect extends StatefulWidget {
  final int templateId;

  const TemplateSelect({
    super.key,
    required this.templateId,
  });

  @override
  _TemplateSelectState createState() => _TemplateSelectState();
}

class _TemplateSelectState extends State<TemplateSelect> {
  late Map<String, dynamic> _templateData = {};
  late bool _isLoading = true;
  bool _isAlreadyDownloaded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkAndLoadTemplate();
  }

  Future<void> _checkAndLoadTemplate() async {
    await _checkIfDownloaded();
    await _loadTemplateData(widget.templateId);
  }

  Future<void> _checkIfDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    if (username == null) return;

    final localTemplates = await DatabaseHelper.getAllTemplates(username);
    final exists = localTemplates.any((t) => t['serverTemplateId'] == widget.templateId);

    if (mounted) {
      setState(() {
        _isAlreadyDownloaded = exists;
      });
    }
  }

  Future<void> _loadTemplateData(int templateId) async {
    try {
      final dio = Dio();
      final apiService = ApiService(dio);
      final response = await apiService.downloadTemplate(templateId);
      
      Map<String, dynamic> data;
      if (response is String) {
        data = jsonDecode(response);
      } else if (response is Map) {
        data = Map<String, dynamic>.from(response);
      } else {
        throw Exception("Invalid response format: ${response.runtimeType}");
      }

      setState(() {
        _templateData = data;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      print("Error fetching template: $e");
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
        _templateData = {};
      });
    }
  }

  Future<bool> _downloadTemplate(int templateId) async {
    if (_isAlreadyDownloaded) return false;

    try {
      if (_templateData.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');

      Map<String, dynamic> templateFormData = {
        'assessment': _templateData['assessment'] ?? {},
        'pre': _templateData['pre'] ?? {},
        'post': _templateData['post'] ?? {}
      };

      final templateModel = TemplateModel(
          templateId: null,
          serverTemplateId: _templateData['id'] ?? templateId,
          templateName: _templateData['templateName'] ?? "Unnamed Template",
          formType: 'assessment-pre-post',
          updatedDate: DateTime.now(),
          templateFormData: templateFormData,
          isPublic: _templateData['is_public'] == 1,
          owner: username,
          deletedAt: null
      );

      await DatabaseHelper.insertTemplate(templateModel, username);

      if (mounted) {
        setState(() {
          _isAlreadyDownloaded = true;
        });
        showAlert(context, "Success", "Template downloaded successfully", AlertType.success, (){
          Navigator.pop(context);
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        showAlert(context, "Failed", "Failed to download template: $e", AlertType.failed, () {});
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_templateData['templateName'] ?? "Template Details"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text('Error: $_errorMessage', textAlign: TextAlign.center),
            ))
          : _templateData.isEmpty
          ? const Center(child: Text('No template data available'))
          : ListView(
        padding: const EdgeInsets.only(bottom: 85),
        children: [
          _buildSection('Assessment', 'assessment'),
          _buildSection('Pre-Check', 'pre'),
          _buildSection('Post-Check', 'post'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAlreadyDownloaded ? null : () => _downloadTemplate(widget.templateId),
        backgroundColor: _isAlreadyDownloaded ? Colors.grey : const Color(0xFFF9A825),
        icon: Icon(Icons.download, color: _isAlreadyDownloaded ? Colors.black54 : Colors.black,),
        label: Text(_isAlreadyDownloaded ? "Already Downloaded" : "Download Template", 
                   style: TextStyle(color: _isAlreadyDownloaded ? Colors.black54 : Colors.black)),
      ),
    );
  }

  Widget _buildSection(String title, String key) {
    final questions = _templateData[key];
    if (questions == null || (questions is Map && questions.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        ),
        if (questions is Map)
          ..._buildQuestions(Map<String, dynamic>.from(questions))
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text("Invalid section data format", style: TextStyle(color: Colors.red)),
          ),
        const Divider(),
      ],
    );
  }

  List<Widget> _buildQuestions(Map<String, dynamic> questions) {
    List<Widget> questionWidgets = [];
    questions.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        questionWidgets.add(_buildQuestionItem(value));
      }
    });
    return questionWidgets;
  }

  Widget _buildQuestionItem(Map<String, dynamic> question) {
    String qText = question['question'] ?? 'Unnamed Question';
    String qType = question['type'] ?? 'text';
    bool isRequired = question['required'] ?? false;
    
    return ListTile(
      title: Text.rich(
        TextSpan(
          text: qText,
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
      subtitle: Text("Type: $qType", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
      dense: true,
    );
  }
}
