import 'dart:convert';
import 'package:drone_checklist/database/database_helper.dart';
import 'package:drone_checklist/view/form_fill.dart';
import 'package:drone_checklist/view/login_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:drone_checklist/view/template_view.dart';
import 'package:drone_checklist/view/template_downloaded.dart';
import 'package:drone_checklist/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drone_checklist/view/app_drawer.dart';

class FormView extends StatefulWidget {
  const FormView({super.key});

  @override
  _FormViewState createState() => _FormViewState();
}

class _FormViewState extends State<FormView> {
  List<Map<String, dynamic>> _formList = [];
  int? selectedFormIndex;
  String? _username;
  String? _email;

  void _callData() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username');
    _email = prefs.getString('email');
    
    if (_username == null) return;

    var listData = await DatabaseHelper.getAllForms(_username!);

    _formList = listData.map((element) {
      return {
        'formId': element['formId'],
        'formName': element['formName'],
        'isChecked': false,
        'syncStatus': element['syncStatus'],
      };
    }).toList();

    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _callData();
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

  void _navigateToDownloadedTemplates() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TemplateDownloaded(),
      ),
    );
    _callData();
  }

  void _sync() async {
    int? selectedForm = selectedFormIndex;

    if (selectedForm == null) {
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text("No Form Selected"),
              content: const Text("Please select at least one form to sync."),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("OK"),
                ),
              ],
            );
          });
      return;
    }

    bool confirm = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("Confirm Sync"),
            content: const Text("Are you sure you want to sync selected form?"),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("No"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Yes"),
              ),
            ],
          );
        }) ?? false;

    if (confirm) {
      try {
        var getForm = await DatabaseHelper.getFormById(selectedForm);
        if (getForm == null) return;

        bool allRequiredAnswered = true;
        String missingQuestion = "";

        try {
          List<dynamic> formData = jsonDecode(getForm['updatedFormData'] ?? getForm['formData']);
          for (var section in formData) {
            if (section['type'] == 'assessment') {
              for (var q in section['answer']) {
                bool isRequired = q['isRequired'] ?? false;
                if (isRequired && (q['answer'] == null || q['answer'].toString().trim().isEmpty)) {
                  allRequiredAnswered = false;
                  missingQuestion = q['questionName'];
                  break;
                }
              }
            } else {
              for (var flight in section['answer']) {
                if (flight['data'] != null) {
                  for (var q in flight['data']) {
                    bool isRequired = q['isRequired'] ?? false;
                    if (isRequired && (q['answer'] == null || q['answer'].toString().trim().isEmpty)) {
                      allRequiredAnswered = false;
                      missingQuestion = q['questionName'];
                      break;
                    }
                  }
                }
                if (!allRequiredAnswered) break;
              }
            }
            if (!allRequiredAnswered) break;
          }
        } catch (e) {
          allRequiredAnswered = false;
        }

        if (!allRequiredAnswered) {
          if (mounted) {
            showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text("Cannot Sync"),
                    content: Text("Required question '$missingQuestion' is not answered. Please fill in all required fields."),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("OK"),
                      ),
                    ],
                  );
                });
          }
          return;
        }

        var dio = Dio();
        var apiService = ApiService(dio);

        FormData sync = FormData.fromMap({
          "submissionName": getForm['formName'].toString(),
          "templateId": getForm['serverTemplateId'].toString(),
          "submittedBy": _username ?? "User",
          "submittedDate": DateTime.now().toString(),
          "formData": getForm['formData'].toString(),
        });

        final response = await dio.post(
          "http://103.102.152.249/webdrone/class/database/syncData.php",
          data: sync
        );

        await DatabaseHelper.updateSyncStatus(selectedForm, 1);

        setState(() {
          _formList.firstWhere((form) => form['formId'] == selectedForm)['syncStatus'] = 1;
          selectedFormIndex = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sync Successful')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sync Failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Checklist Form',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _sync,
            icon: const Icon(Icons.cloud_upload, color: Colors.black, size: 30),
            tooltip: 'Sync Selected Form',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: AppDrawer(username: _username, email: _email, onLogout: _logout),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFF9A825),
        onPressed: _navigateToDownloadedTemplates,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: _formList.isEmpty
          ? const Center(
        child: Text(
          "No Form Available Yet :(",
          style: TextStyle(fontSize: 18),
        )
      )
          : ListView.builder(
        itemCount: _formList.length,
        itemBuilder: (context, index) => Card(
          margin: const EdgeInsets.all(15),
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 8,
                  backgroundColor: _formList[index]['syncStatus'] == 1
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(width: 10),
                const Icon(Icons.description, color: Colors.blue),
              ],
            ),
            title: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                _formList[index]['formName'],
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FormFill(
                    formId: _formList[index]['formId'],
                  ),
                ),
              );
              _callData();
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () async {
                    int formId = _formList[index]['formId'];
                    await DatabaseHelper.deleteForm(formId);
                    setState(() {
                      _formList.removeAt(index);
                    });
                  },
                  icon: const Icon(
                    Icons.delete,
                    color: Colors.redAccent,
                  ),
                ),
                Checkbox(
                  value: selectedFormIndex == _formList[index]['formId'],
                  onChanged: _formList[index]['syncStatus'] == 1
                      ? null
                      : (bool? value) {
                        setState(() {
                          if (value == true) {
                            selectedFormIndex = _formList[index]['formId'];
                          } else {
                            selectedFormIndex = null;
                          }
                        });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
