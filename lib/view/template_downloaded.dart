import 'package:drone_checklist/database/database_helper.dart';
import 'package:drone_checklist/view/form_view.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'form_create.dart';

class TemplateDownloaded extends StatefulWidget {
  const TemplateDownloaded({super.key});

  @override
  _TemplateDownloadedState createState() => _TemplateDownloadedState();
}

class _TemplateDownloadedState extends State<TemplateDownloaded> {

  late Future<List<Map<String, dynamic>>> _templatesFuture;
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  void _loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username');
    setState(() {
      _templatesFuture = DatabaseHelper.getAllTemplates(_username ?? "");
    });
  }

  Future<void> _deleteTemplate(int templateId) async {
    await DatabaseHelper.deleteTemplate(templateId);
    _loadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    const String appTitle = 'Downloaded Templates';
    return Scaffold(
        appBar: AppBar(
          title: const Text(
            appTitle,
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const FormView()),
              );
            },
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _templatesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text("Error: ${snapshot.error}"));
            } else if (snapshot.data != null && snapshot.data!.isEmpty) {
              return const Center(child: Text("No templates available."));
            } else {
              return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  var chosenTemp = snapshot.data![index];
                  return Card(
                    margin: const EdgeInsets.all(15),
                    child: ListTile(
                      leading: const Icon(Icons.description, color: Colors.blue),
                      title: Text(
                        chosenTemp['templateName'],
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteTemplate(chosenTemp['templateId']),
                          ),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.grey),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FormCreate(
                            templateId: chosenTemp['templateId'],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            }
          },
        ),
    );
  }
}
