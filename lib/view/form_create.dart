import 'dart:convert';
import 'package:drone_checklist/helper/utils.dart';
import 'package:flutter/material.dart';
import 'package:drone_checklist/model/form_model.dart';
import 'package:drone_checklist/database/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'form_view.dart';

class FormCreate extends StatefulWidget {
  final int templateId;

  const FormCreate({
    super.key,
    required this.templateId,
  });

  @override
  _FormCreateState createState() => _FormCreateState();
}

class _FormCreateState extends State<FormCreate> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final Map<String, TextEditingController> _questionControllers = {};
  final Map<String, Set<String>> _checkboxValues = {};

  Map<String, dynamic>? _templateData = {};
  Map<String, dynamic> _formData = {};
  final Map<String, String> _questionName = {};
  final Map<String, String> _questionType = {};
  final Map<String, List<String>> _questionOptions = {};
  final Map<String, bool> _questionRequired = {};

  final Map<String, List<int>> _instanceIndices = {
    'assessment': [0],
    'pre': [0],
    'post': [0],
  };

  bool _isLoading = true;
  String? _activeSectionType;
  int _activeInstanceIndex = 0;

  @override
  void initState() {
    super.initState();
    _getTemplate(widget.templateId);
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (var controller in _questionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _getTemplate(int templateId) async {
    try {
      final response = await DatabaseHelper.getTemplateById(templateId);
      final Map<String, dynamic> data = jsonDecode(response['templateFormData']);

      setState(() {
        _formData = data;
        _templateData = response;
        _isLoading = false;
        _titleController.text = "";
        _initFormData(data);
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _templateData = {};
        _formData = {};
      });
    }
  }

  void _initFormData(Map<String, dynamic> data) {
    for (var section in ['assessment', 'pre', 'post']) {
      if (data[section] != null) {
        _initializeInstance(section, 0, data[section]);
      }
    }
  }

  void _initializeInstance(String section, int index, Map<String, dynamic> questions) {
    questions.forEach((questionId, questionData) {
      String uniqueId = '$section-$index-$questionId';
      if (!_questionControllers.containsKey(uniqueId)) {
        _questionControllers[uniqueId] = TextEditingController();
      }
      _questionName[uniqueId] = questionData['question'];
      _questionType[uniqueId] = questionData['type'];
      _questionOptions[uniqueId] = List<String>.from(questionData['option'] ?? []);
      _questionRequired[uniqueId] = questionData['required'] ?? false;

      if (questionData['type'] == 'checklist') {
        _checkboxValues[uniqueId] = {};
      }
    });
  }

  void _duplicateSection(String section) {
    if (section == 'assessment') return;
    
    int newIndex = _instanceIndices[section]!.isEmpty ? 0 : _instanceIndices[section]!.last + 1;
    setState(() {
      _instanceIndices[section]!.add(newIndex);
      _initializeInstance(section, newIndex, _formData[section]);
    });
  }

  void _removeInstance(String section, int index) {
    if (_instanceIndices[section]!.length <= 1) return;
    
    setState(() {
      _instanceIndices[section]!.remove(index);
      // Clean up controllers
      _questionControllers.keys.where((k) => k.startsWith('$section-$index-')).toList().forEach((k) {
        _questionControllers[k]?.dispose();
        _questionControllers.remove(k);
        _checkboxValues.remove(k);
        _questionName.remove(k);
        _questionType.remove(k);
        _questionOptions.remove(k);
        _questionRequired.remove(k);
      });
    });
  }

  void _saveForm() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a submission title')),
      );
      return;
    }

    List<Map<String, dynamic>> structuredData = [];
    Map<String, Map<int, List<Map<String, dynamic>>>> organizedData = {};
    
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');

    _questionControllers.forEach((uniqueId, controller) {
      var parts = uniqueId.split('-');
      if (parts.length < 3) return;
      
      var section = parts[0];
      var instanceIndex = int.parse(parts[1]);
      // var questionId = parts[2];

      organizedData.putIfAbsent(section, () => {});
      organizedData[section]!.putIfAbsent(instanceIndex, () => []);

      String? questionName = _questionName[uniqueId];
      String? questionType = _questionType[uniqueId];
      bool isRequired = _questionRequired[uniqueId] ?? false;

      String answerValue = controller.text;
      if (questionType == 'checklist') {
        answerValue = _checkboxValues[uniqueId]?.join(', ') ?? '';
      }

      var answerEntry = {
        "questionName": questionName,
        "answer": answerValue,
        "option": _questionOptions[uniqueId] ?? [],
        "qType": questionType,
        "isRequired": isRequired,
        "dataChanged": DateTime.now().toString().split('.').first.replaceAll('-', '/')
      };
      organizedData[section]![instanceIndex]?.add(answerEntry);
    });

    for (var section in ['assessment', 'pre', 'post']) {
      if (organizedData.containsKey(section)) {
        if (section == 'assessment') {
          // Assessment usually only has one instance, but we follow the data structure
          var firstInstance = organizedData[section]!.values.first;
          structuredData.add({"type": "assessment", "answer": firstInstance});
        } else {
          List<Map<String, dynamic>> flights = [];
          int flightNum = 1;
          
          // Sort indices to maintain order
          var indices = _instanceIndices[section]!;
          for (var idx in indices) {
            if (organizedData[section]!.containsKey(idx)) {
              flights.add({
                "flightNum": flightNum++,
                "data": organizedData[section]![idx]
              });
            }
          }

          structuredData.add({
            "type": section,
            "answer": flights
          });
        }
      }
    }

    final formModel = FormModel(
      formId: null,
      templateId: widget.templateId,
      serverTemplateId: _templateData?['serverTemplateId'],
      formName: _titleController.text.trim(),
      updatedDate: DateTime.now(),
      formData: structuredData,
      updatedFormData: structuredData,
    );

    try {
      await DatabaseHelper.createForm(formModel, username);
      if (mounted) {
        await showAlert(context, "Success", "Form submitted successfully!", AlertType.success, () {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const FormView()),
              (route) => false,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        showAlert(context, "Error", "Failed to save form: $e", AlertType.failed, () {});
      }
    }
  }

  bool _isInstanceCompleted(String type, int index) {
    bool allCompleted = true;
    bool hasQuestions = false;
    _questionControllers.forEach((uniqueId, controller) {
      if (uniqueId.startsWith('$type-$index-')) {
        hasQuestions = true;
        bool isRequired = _questionRequired[uniqueId] ?? false;
        String typeOfQ = _questionType[uniqueId] ?? '';
        String value = typeOfQ == 'checklist' 
            ? (_checkboxValues[uniqueId]?.join(', ') ?? '') 
            : controller.text;
            
        if (isRequired && value.trim().isEmpty) {
          allCompleted = false;
        }
      }
    });
    return hasQuestions && allCompleted;
  }

  bool _isSectionCompleted(String type) {
    if (_instanceIndices[type] == null || _instanceIndices[type]!.isEmpty) return true;
    for (int index in _instanceIndices[type]!) {
      if (!_isInstanceCompleted(type, index)) return false;
    }
    return true;
  }

  String _getSectionTitle(String type) {
    switch (type.toLowerCase()) {
      case 'assessment':
        return 'Assessment Form';
      case 'pre':
        return 'Pre-Flight Form';
      case 'post':
        return 'Post-Flight Form';
      default:
        return 'Form';
    }
  }

  @override
  Widget build(BuildContext context) {
    String titleText = _activeSectionType == null 
        ? (_templateData?['templateName'] ?? "New Form") 
        : "${_getSectionTitle(_activeSectionType!)} ${_activeSectionType == 'assessment' ? '' : '(Flight ${_instanceIndices[_activeSectionType!]!.indexOf(_activeInstanceIndex) + 1})'}";
    
    return PopScope(
      canPop: _activeSectionType == null,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_activeSectionType != null) {
          setState(() => _activeSectionType = null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            titleText,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_activeSectionType != null) {
                setState(() => _activeSectionType = null);
              } else {
                Navigator.pop(context);
              }
            },
            tooltip: 'Back',
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _formData.isEmpty
                ? const Center(child: Text('No template data available'))
                : _activeSectionType == null 
                    ? _buildOverview() 
                    : _buildSectionDetail(_activeSectionType!, _activeInstanceIndex),
      ),
    );
  }

  Widget _buildOverview() {
    int totalSections = 3;
    int completedCount = 0;
    if (_isSectionCompleted('assessment')) completedCount++;
    if (_isSectionCompleted('pre')) completedCount++;
    if (_isSectionCompleted('post')) completedCount++;
    
    double progress = completedCount / totalSections;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Progress: $completedCount/$totalSections forms completed",
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              "${(progress * 100).toInt()}%",
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF9A825)),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 24),
        
        Card(
          elevation: 4,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Submission Title",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Give this submission a clear, descriptive name.",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    hintText: "e.g. Flight 23 - Site A - 2025-08-10",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.grey, width: 0.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  onChanged: (value) => setState(() {}),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          "Forms to Complete:",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF212121)),
        ),
        const SizedBox(height: 16),

        _buildSectionCard("Assessment Form", "ASSESSMENT", "assessment"),
        _buildSectionCard("Pre-Flight Form", "PRE", "pre"),
        _buildSectionCard("Post-Flight Form", "POST", "post"),
        const SizedBox(height: 48),
        Center(
          child: SizedBox(
            width: 250,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF9A825),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
              onPressed: _saveForm,
              child: const Text('SUBMIT FORM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSectionCard(String title, String subtitle, String type) {
    bool isSectionCompleted = _isSectionCompleted(type);
    List<int> indices = _instanceIndices[type] ?? [0];
    
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSectionCompleted ? Colors.green[600] : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isSectionCompleted ? "COMPLETED" : "NOT STARTED",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSectionCompleted ? Colors.white : Colors.black54
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 13, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),

            // List instances
            ...indices.asMap().entries.map((entry) {
              int displayIndex = entry.key + 1;
              int actualIndex = entry.value;
              bool isDone = _isInstanceCompleted(type, actualIndex);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _activeSectionType = type;
                      _activeInstanceIndex = actualIndex;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey[300]!, width: 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDone ? Icons.check_circle : Icons.radio_button_off,
                          color: isDone ? Colors.green[600] : Colors.grey[400],
                          size: 24,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          type == 'assessment' ? "Fill Form" : "Flight $displayIndex",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: isDone ? Colors.black87 : Colors.black54,
                          ),
                        ),
                        const Spacer(),
                        if (type != 'assessment' && indices.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_rounded, color: Colors.red, size: 24),
                            onPressed: () => _removeInstance(type, actualIndex),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Delete Flight',
                          ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[400], size: 16),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),

            if (type != 'assessment')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: () => _duplicateSection(type),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    label: const Text("DUPLICATE FORM", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF9A825),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(double.infinity, 45),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionDetail(String type, int instanceIndex) {
    if (_formData[type] == null) return const Center(child: Text("Section not found"));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Text(
                    type.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  if (type != 'assessment')
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        "FLIGHT ${_instanceIndices[type]!.indexOf(instanceIndex) + 1}",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, color: Color(0xFFF9A825), fontWeight: FontWeight.bold),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _formData[type].entries.map<Widget>((entry) {
                          String uniqueQuestionId = '$type-$instanceIndex-${entry.key}';
                          Map<String, dynamic> questionData = entry.value;
                          TextEditingController? controller = _questionControllers[uniqueQuestionId];
                          if (controller != null) {
                            return _buildQuestionField(uniqueQuestionId, questionData, controller);
                          }
                          return const SizedBox.shrink();
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: SizedBox(
                  width: 250,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF9A825),
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                    ),
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        setState(() => _activeSectionType = null);
                      }
                    },
                    child: const Text('SAVE & BACK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionField(String uniqueQuestionId, Map<String, dynamic> question, TextEditingController controller) {
    bool isRequired = question['required'] ?? false;
    List<String> options = List<String>.from(question['option'] ?? []);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: question['question'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              children: [
                if (isRequired)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (question['type'] == 'text')
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Your answer',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              validator: (value) => isRequired && (value == null || value.trim().isEmpty) ? 'This field cannot be empty' : null,
            ),
          if (question['type'] == 'checklist')
            FormField<Set<String>>(
              initialValue: _checkboxValues[uniqueQuestionId],
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select at least one option' : null,
              builder: (state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...options.map((option) {
                      bool isChecked = (_checkboxValues[uniqueQuestionId] ??= <String>{}).contains(option);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(option),
                        value: isChecked,
                        activeColor: const Color(0xFFF9A825),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (bool? isSelected) {
                          setState(() {
                            if (isSelected ?? false) {
                              _checkboxValues[uniqueQuestionId]?.add(option);
                            } else {
                              _checkboxValues[uniqueQuestionId]?.remove(option);
                            }
                            state.didChange(_checkboxValues[uniqueQuestionId]);
                          });
                        },
                      );
                    }).toList(),
                    if (state.hasError)
                      Padding(
                        padding: const EdgeInsets.only(left: 0, top: 8.0),
                        child: Text(state.errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                );
              }
            ),
          if (question['type'] == 'dropdown')
            DropdownButtonFormField<String>(
              value: controller.text.isNotEmpty ? controller.text : null,
              onChanged: (String? newValue) => setState(() => controller.text = newValue ?? ''),
              items: options.map((option) => DropdownMenuItem(value: option, child: Text(option))).toList(),
              decoration: InputDecoration(
                hintText: 'Select one',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select an option' : null,
            ),
          if (question['type'] == 'multiple')
            FormField<String>(
              initialValue: controller.text,
              validator: (value) => isRequired && (controller.text.isEmpty) ? 'Please select an option' : null,
              builder: (state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...options.map((option) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(option),
                          value: option,
                          activeColor: const Color(0xFFF9A825),
                          groupValue: controller.text,
                          onChanged: (String? value) {
                            setState(() {
                              controller.text = value ?? '';
                              state.didChange(value);
                            });
                          },
                        )).toList(),
                    if (state.hasError)
                      Padding(
                        padding: const EdgeInsets.only(left: 0, top: 8.0),
                        child: Text(state.errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                );
              }
            ),
          if (question['type'] == 'longtext')
            TextFormField(
              maxLines: 4,
              controller: controller,
              decoration: InputDecoration(
                hintText: "Your answer",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              keyboardType: TextInputType.multiline,
              validator: (value) => isRequired && (value == null || value.trim().isEmpty) ? 'This field cannot be empty' : null,
            ),
          if (question['type'] == 'date')
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Select Date",
                suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFFF9A825)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              readOnly: true,
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select a date' : null,
              onTap: () async {
                DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2101),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xFFF9A825),
                          onPrimary: Colors.black,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (pickedDate != null) {
                  setState(() => controller.text = "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}");
                }
              },
            ),
          if (question['type'] == 'time')
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Select Time",
                suffixIcon: const Icon(Icons.access_time, color: Color(0xFFF9A825)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              readOnly: true,
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select a time' : null,
              onTap: () async {
                TimeOfDay? pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xFFF9A825),
                          onPrimary: Colors.black,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (pickedTime != null) {
                  setState(() => controller.text = "${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}");
                }
              },
            ),
          if (question['type'] == 'datetime')
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Select Date & Time",
                suffixIcon: const Icon(Icons.event, color: Color(0xFFF9A825)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              readOnly: true,
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select date and time' : null,
              onTap: () async {
                DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2101),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xFFF9A825),
                          onPrimary: Colors.black,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (pickedDate != null) {
                  TimeOfDay? pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFFF9A825),
                            onPrimary: Colors.black,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (pickedTime != null) {
                    setState(() => controller.text = "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')} ${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}");
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}
