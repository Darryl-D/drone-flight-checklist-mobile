import 'package:flutter/material.dart';

enum AlertType { success, failed }

Future<void> showAlert(
    BuildContext context,
    String title,
    String message,
    AlertType type,
    VoidCallback onOkPressed) {
  // Set background to a light grey
  Color bgColor = Colors.grey[200]!;
  
  // Set all text colors to black as requested
  const Color textColor = Colors.black;

  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          title, 
          style: const TextStyle(color: textColor, fontWeight: FontWeight.bold)
        ),
        content: Text(
          message, 
          style: const TextStyle(color: textColor)
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
            child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[400], // Darker grey for button
                  foregroundColor: textColor, // Black text
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onOkPressed();
                },
                child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    },
  );
}
