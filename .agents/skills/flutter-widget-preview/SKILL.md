---
name: flutter-widget-preview
description: >-
  Use this skill whenever building, updating, or previewing individual Flutter widgets, dialogs, cards, or screens in RemindBuddy. Explains how to create standalone previews, inject mock data, and test UI interactively in Antigravity IDE.
---

# Flutter Widget Preview & Isolated UI Development for RemindBuddy

This skill outlines how to build and preview UI components in RemindBuddy in total isolation, avoiding the need to compile the entire full-stack app or authenticate with Firebase for simple UI tweaks.

---

## 1. Creating Isolated Preview Harnesses

When designing a complex component (like a transaction card, gold trend widget, or task dialog), create or use a preview wrapper in `frontend/test/previews/` or run via a lightweight preview entrypoint.

### Example Harness Pattern:
```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const WidgetPreviewApp());
}

class WidgetPreviewApp extends StatelessWidget {
  const WidgetPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: Scaffold(
        appBar: AppBar(title: const Text('Widget Preview')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            // The widget under test:
            child: MyTargetWidget(
              // Injected Mock Data (No Firestore calls needed)
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## 2. Using Mock Data for Instant Rendering

Instead of connecting to live Firebase Auth or Firestore streams, use static model instances:

* **Finance Transaction**:
  ```dart
  final mockTransaction = FinanceTransaction(
    id: 'mock_1',
    amount: 1450.00,
    type: 'debit',
    category: 'Groceries',
    merchant: 'Supermarket',
    timestamp: DateTime.now(),
  );
  ```
* **Gold Price Trend**:
  Provide an in-memory `List<double>` of historical rates to immediately verify chart rendering in [`frontend/lib/screens/gold_screen.dart`](file:///home/roshan-axcess/Documents/RemindBuddy/frontend/lib/screens/gold_screen.dart).

---

## 3. Running Previews in Antigravity Phone View

1. **Launch Web Server**:
   ```bash
   cd frontend
   flutter run -t test/previews/widget_preview.dart -d web-server --web-port=8080
   ```
2. **Open in Editor Viewport**:
   * Open the IDE's Mobile Preview extension (`lirobi.phone-preview`) or Simple Browser pointing to `http://localhost:8080`.
   * Dock the tab to the left or right editor column.
3. **Hot Reload Loop**:
   * Modify widget code.
   * Hit save or press `r` in the terminal to view immediate layout updates.
