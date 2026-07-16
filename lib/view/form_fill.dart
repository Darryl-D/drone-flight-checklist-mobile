import 'dart:convert';
import 'package:drone_checklist/database/database_helper.dart';
import 'package:drone_checklist/helper/utils.dart';
import 'package:flutter/material.dart';

class FormFill extends StatefulWidget {
  final int formId;
  const FormFill({super.key, required this.formId});

  @override
  _FormFillState createState() => _FormFillState();
}

class _FormFillState extends State<FormFill> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final Map<String, TextEditingController> _questionControllers = {};
  final Map<String, Set<String>> _checkboxValues = {};

  final Map<String, TimeOfDay?> _takeOffTimes = {};
  final Map<String, TimeOfDay?> _landingTimes = {};

  List<Map<String, dynamic>>? _formData;
  Map<String, dynamic>? _fullFormData = {};
  bool _isLoading = true;
  bool _isSync = false; 
  String? _activeSectionType; 
  int? _activeFlightId; 

  @override
  void dispose() {
    _titleController.dispose();
    _questionControllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFormData(widget.formId);
  }

  Future<void> _updateForm() async {
    if (_isSync) return;

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a submission title')),
      );
      return;
    }

    try {
      if (_formData == null) return;

      List<Map<String, dynamic>> updatedSections = [];
      for (var section in _formData!) {
        _updateSectionData(section);
        updatedSections.add(section);
      }

      String encodeUpdatedFormData = jsonEncode(updatedSections);
      String newTitle = _titleController.text.trim();

      await DatabaseHelper.updateForm(widget.formId, encodeUpdatedFormData, encodeUpdatedFormData);
      await DatabaseHelper.updateFormTitle(widget.formId, newTitle);
      
      if (mounted) {
        await showAlert(context, "Success", "Form updated successfully!", AlertType.success, () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) {
        showAlert(context, "Error", "Failed to update form: $e", AlertType.failed, () {});
      }
    }
  }

  void _updateSectionData(Map<String, dynamic> section) {
    if (section['type'] == 'assessment') {
      for (var question in section['answer']) {
        String questionName = question['questionName'];
        String controllerKey = '$questionName-0';

        if (question['qType'] == 'checklist') {
          question['answer'] = _checkboxValues[controllerKey]?.join(', ') ?? '';
        } else {
          TextEditingController? controller = _questionControllers[controllerKey];
          if (controller != null) {
            question['answer'] = controller.text;
          }
        }
        question['dataChanged'] = DateTime.now().toString().split('.').first.replaceAll('-', '/');
      }
    } else {
      int newFlightNum = 1;
      List<dynamic> flights = section['answer'];
      for (var flight in flights) {
        int oldFlightNum = flight['flightNum'] ?? 0;
        if (flight['data'] != null) {
          for (var data in flight['data']) {
            String questionName = data['questionName'];
            String controllerKey = '$questionName-$oldFlightNum';

            if (data['qType'] == 'checklist') {
              data['answer'] = _checkboxValues[controllerKey]?.join(', ') ?? '';
            } else {
              TextEditingController? controller = _questionControllers[controllerKey];
              if (controller != null) {
                data['answer'] = controller.text;
              }
            }
            data['dataChanged'] = DateTime.now().toString().split('.').first.replaceAll('-', '/');
          }
        }
        flight['flightNum'] = newFlightNum++;
      }
    }
  }

  void _loadFormData(int formId) async {
    try {
      var form = await DatabaseHelper.getFormById(formId);
      if (form == null) {
        setState(() => _isLoading = false);
        return;
      }

      _isSync = (form['syncStatus'] == 1);

      List<Map<String, dynamic>> formData = form['updatedFormData'] != null
          ? List<Map<String, dynamic>>.from(jsonDecode(form['updatedFormData']))
          : (form['formData'] != null ? List<Map<String, dynamic>>.from(jsonDecode(form['formData'])) : []);

      _formData = formData;
      for (var section in _formData!) {
        if (section['type'] == 'assessment') {
          for (var question in section['answer']) {
            _initQuestionState(question, 0);
          }
        } else {
          for (var flight in section['answer']) {
            int flightNum = flight['flightNum'] ?? 0;
            if (flight['data'] != null) {
              for (var data in flight['data']) {
                _initQuestionState(data, flightNum);
              }
            }
          }
        }
      }

      setState(() {
        _fullFormData = form;
        _titleController.text = form['formName'] ?? "";
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print("Error loading form data: $e");
    }
  }

  void _initQuestionState(Map<String, dynamic> data, int flightNum) {
    String questionName = data['questionName'];
    String controllerKey = '$questionName-$flightNum';
    String answer = data['answer']?.toString() ?? '';

    if (data['qType'] == 'checklist') {
      List<String> selectedOptions = answer.split(', ').where((item) => item.isNotEmpty).toList();
      _checkboxValues[controllerKey] = Set<String>.from(selectedOptions);
      _questionControllers[controllerKey] = TextEditingController(text: answer);
    } else {
      _questionControllers[controllerKey] = TextEditingController(text: answer);
    }
  }

  void _duplicateSection(String sectionType) {
    if (sectionType == 'assessment' || _isSync) return;

    setState(() {
      var section = _formData!.firstWhere((s) => s['type'] == sectionType);
      List<dynamic> flights = section['answer'];
      
      if (flights.isNotEmpty) {
        int maxFlightNum = 0;
        for (var f in flights) {
          if ((f['flightNum'] ?? 0) > maxFlightNum) maxFlightNum = f['flightNum'];
        }
        int nextFlightId = maxFlightNum + 1;

        var firstFlight = flights[0];
        var newData = (firstFlight['data'] as List<dynamic>).map((item) {
          var newItem = Map<String, dynamic>.from(item);
          newItem['answer'] = ''; 
          return newItem;
        }).toList();

        var newFlight = {
          "flightNum": nextFlightId,
          "data": newData
        };
        flights.add(newFlight);
        
        for (var data in newData) {
          _initQuestionState(data, nextFlightId);
        }
      }
    });
  }

  void _removeInstance(String sectionType, int flightNum) {
    if (_isSync) return;
    
    setState(() {
      var section = _formData!.firstWhere((s) => s['type'] == sectionType);
      List<dynamic> flights = section['answer'];
      
      if (flights.length > 1) {
        flights.removeWhere((f) => f['flightNum'] == flightNum);
        _questionControllers.keys.where((k) => k.endsWith('-$flightNum')).toList().forEach((k) {
          _questionControllers[k]?.dispose();
          _questionControllers.remove(k);
          _checkboxValues.remove(k);
          _takeOffTimes.remove(k);
          _landingTimes.remove(k);
        });
      }
    });
  }

  void _calculateDuration(String uniqueId) {
    final takeOff = _takeOffTimes[uniqueId];
    final landing = _landingTimes[uniqueId];

    if (takeOff != null && landing != null) {
      int takeOffMinutes = takeOff.hour * 60 + takeOff.minute;
      int landingMinutes = landing.hour * 60 + landing.minute;

      int diffMinutes = landingMinutes - takeOffMinutes;
      if (diffMinutes < 0) {
        diffMinutes += 24 * 60;
      }

      int hours = diffMinutes ~/ 60;
      int minutes = diffMinutes % 60;

      String result = "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}";
      _questionControllers[uniqueId]?.text = result;
      setState(() {});
    }
  }

  bool _isInstanceCompleted(Map<String, dynamic> section, Map<String, dynamic> flight) {
    if (section['type'] == 'assessment') {
      List<dynamic> answers = section['answer'];
      for (var q in answers) {
        bool isRequired = q['isRequired'] ?? false;
        String controllerKey = '${q['questionName']}-0';
        String value = q['qType'] == 'checklist'
            ? (_checkboxValues[controllerKey]?.join(', ') ?? '') 
            : (_questionControllers[controllerKey]?.text ?? '');
        if (isRequired && value.trim().isEmpty) return false;
      }
    } else {
      List<dynamic> data = flight['data'] ?? [];
      int fNum = flight['flightNum'];
      for (var q in data) {
        bool isRequired = q['isRequired'] ?? false;
        String controllerKey = '${q['questionName']}-$fNum';
        String value = q['qType'] == 'checklist'
            ? (_checkboxValues[controllerKey]?.join(', ') ?? '') 
            : (_questionControllers[controllerKey]?.text ?? '');
        if (isRequired && value.trim().isEmpty) return false;
      }
    }
    return true;
  }

  bool _isSectionCompleted(String type) {
    if (_formData == null) return false;
    var section = _formData!.firstWhere(
        (s) => s['type'].toString().toLowerCase() == type.toLowerCase(),
        orElse: () => {});
    if (section.isEmpty) return false;

    if (section['type'] == 'assessment') {
      return _isInstanceCompleted(section, {});
    } else {
      List<dynamic> flights = section['answer'];
      if (flights.isEmpty) return false;
      for (var flight in flights) {
        if (!_isInstanceCompleted(section, flight)) return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    String titleText = _activeSectionType == null 
        ? 'Edit Form' 
        : _getSectionTitle(_activeSectionType!);

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
            : _formData == null
                ? const Center(child: Text('No form data available'))
                : _activeSectionType == null 
                    ? _buildOverview() 
                    : _buildSectionDetail(_activeSectionType!, _activeFlightId),
      ),
    );
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
                  enabled: !_isSync,
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
        if (!_isSync)
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
                onPressed: _updateForm,
                child: const Text('SAVE CHANGES', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              ),
            ),
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSectionCard(String title, String subtitle, String type) {
    bool isCompleted = _isSectionCompleted(type);
    var section = _formData!.firstWhere(
        (s) => s['type'].toString().toLowerCase() == type.toLowerCase(),
        orElse: () => {});
    List<dynamic> flights = section['answer'] ?? [];
    
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
                    color: isCompleted ? Colors.green[600] : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isCompleted ? "COMPLETED" : "NOT STARTED",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCompleted ? Colors.white : Colors.black54
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

            if (type == 'assessment')
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _activeSectionType = type;
                      _activeFlightId = null;
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
                          isCompleted ? Icons.check_circle : Icons.radio_button_off,
                          color: isCompleted ? Colors.green[600] : Colors.grey[400],
                          size: 24,
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          "Open Form",
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[400], size: 16),
                      ],
                    ),
                  ),
                ),
              )
            else
              ...flights.asMap().entries.map((entry) {
                int displayIndex = entry.key + 1;
                var flight = entry.value;
                int flightId = flight['flightNum'];
                bool isDone = _isInstanceCompleted(section, flight);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _activeSectionType = type;
                        _activeFlightId = flightId;
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
                            "Flight $displayIndex",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: isDone ? Colors.black87 : Colors.black54,
                            ),
                          ),
                          const Spacer(),
                          if (!_isSync && flights.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete_rounded, color: Colors.red, size: 24),
                              onPressed: () => _removeInstance(type, flightId),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[400], size: 16),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),

            if (!_isSync && type != 'assessment')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: () => _duplicateSection(type),
                    icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.black),
                    label: const Text("DUPLICATE FORM", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF9A825),
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

  Widget _buildSectionDetail(String type, int? flightId) {
    var section = _formData!.firstWhere(
        (s) => s['type'].toString().toLowerCase() == type.toLowerCase(),
        orElse: () => {});

    if (section.isEmpty) return const Center(child: Text("Section not found"));

    List<dynamic> questionsToDisplay = [];
    String subTitle = "";

    if (section['type'] == 'assessment') {
      questionsToDisplay = section['answer'];
    } else {
      var flight = (section['answer'] as List<dynamic>).firstWhere((f) => f['flightNum'] == flightId);
      questionsToDisplay = flight['data'];
      int displayIdx = (section['answer'] as List<dynamic>).indexOf(flight) + 1;
      subTitle = "FLIGHT $displayIdx";
    }

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
                  if (subTitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        subTitle,
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
                        children: questionsToDisplay.map<Widget>((qData) {
                          String questionName = qData['questionName'];
                          int fId = (section['type'] == 'assessment') ? 0 : flightId!;
                          String controllerKey = '$questionName-$fId';
                          TextEditingController controller = _questionControllers[controllerKey]!;
                          return _buildQuestionField(qData, questionName, controller, fId);
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            if (!_isSync)
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
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => _activeSectionType = null);
                        }
                      },
                      child: const Text('SAVE & BACK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    ),
                  ),
                ),
              ),
            if (_isSync)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "This form has been synced and cannot be modified.",
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionField(Map<String, dynamic> question, String questionId, TextEditingController controller, int flightNum) {
    String controllerKey = '$questionId-$flightNum';
    List<String> options = List<String>.from(question['option'] ?? []);
    bool isRequired = question['isRequired'] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: question['questionName'],
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
          if (question['qType'] == 'text')
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Your answer',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              enabled: !_isSync,
              validator: (value) => isRequired && (value == null || value.trim().isEmpty) ? 'This field cannot be empty' : null,
            ),
          if (question['qType'] == 'checklist')
            FormField<Set<String>>(
              initialValue: _checkboxValues[controllerKey],
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select at least one option' : null,
              builder: (state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...options.map((option) {
                      bool isChecked = (_checkboxValues[controllerKey] ??= <String>{}).contains(option);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(option),
                        value: isChecked,
                        activeColor: const Color(0xFFF9A825),
                        controlAffinity: ListTileControlAffinity.leading,
                        enabled: !_isSync,
                        onChanged: _isSync ? null : (bool? isSelected) {
                          setState(() {
                            if (isSelected ?? false) {
                              _checkboxValues[controllerKey]?.add(option);
                            } else {
                              _checkboxValues[controllerKey]?.remove(option);
                            }
                            controller.text = _checkboxValues[controllerKey]?.join(', ') ?? '';
                            state.didChange(_checkboxValues[controllerKey]);
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
          if (question['qType'] == 'dropdown')
            DropdownButtonFormField<String>(
              value: options.contains(controller.text) ? controller.text : null,
              onChanged: _isSync ? null : (String? newValue) => setState(() => controller.text = newValue ?? ''),
              items: options.map((option) => DropdownMenuItem(value: option, child: Text(option))).toList(),
              decoration: InputDecoration(
                hintText: 'Select one',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select an option' : null,
            ),
          if (question['qType'] == 'multiple')
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
                          onChanged: _isSync ? null : (String? value) {
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
          if (question['qType'] == 'longtext')
            TextFormField(
              maxLines: 4,
              controller: controller,
              decoration: InputDecoration(
                hintText: "Your answer",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              keyboardType: TextInputType.multiline,
              enabled: !_isSync,
              validator: (value) => isRequired && (value == null || value.trim().isEmpty) ? 'This field cannot be empty' : null,
            ),
          if (question['qType'] == 'date')
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Select Date",
                suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFFF9A825)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              readOnly: true,
              enabled: !_isSync,
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select a date' : null,
              onTap: _isSync ? null : () async {
                DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
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
                  setState(() => controller.text = "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}");
                }
              },
            ),
          if (question['qType'] == 'time')
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Select Time",
                suffixIcon: const Icon(Icons.access_time, color: Color(0xFFF9A825)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              readOnly: true,
              enabled: !_isSync,
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select a time' : null,
              onTap: _isSync ? null : () async {
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
                  setState(() => controller.text = "${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}");
                }
              },
            ),
          if (question['qType'] == 'datetime')
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Select Date & Time",
                suffixIcon: const Icon(Icons.event, color: Color(0xFFF9A825)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              readOnly: true,
              enabled: !_isSync,
              validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Please select date and time' : null,
              onTap: _isSync ? null : () async {
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
          if (question['qType'] == 'duration')
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Take Off", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: _isSync ? null : () async {
                              TimeOfDay? picked = await showTimePicker(
                                context: context,
                                initialTime: _takeOffTimes[controllerKey] ?? TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setState(() => _takeOffTimes[controllerKey] = picked);
                                _calculateDuration(controllerKey);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_takeOffTimes[controllerKey]?.format(context) ?? "Select"),
                                  const Icon(Icons.access_time, size: 18, color: Color(0xFFF9A825)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Landing", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: _isSync ? null : () async {
                              TimeOfDay? picked = await showTimePicker(
                                context: context,
                                initialTime: _landingTimes[controllerKey] ?? TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setState(() => _landingTimes[controllerKey] = picked);
                                _calculateDuration(controllerKey);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_landingTimes[controllerKey]?.format(context) ?? "Select"),
                                  const Icon(Icons.access_time, size: 18, color: Color(0xFFF9A825)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text("Total Duration", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                TextFormField(
                  controller: controller,
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: "00:00",
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  validator: (value) => isRequired && (value == null || value.isEmpty) ? 'Take off and Landing times are required' : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
