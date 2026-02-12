# Widget Lifecycle Safety Patterns (Flutter)

This is a copy/paste reference for common async UI patterns. It used to live in `lib/` but was moved here so it doesn't break Flutter analysis/builds.

## Pattern 1: Basic async function with UI feedback

```dart
Future<void> loadData() async {
  if (!mounted) return;
  setState(() => _isLoading = true);

  final result = await ApiService.getData();
  if (!mounted) return;

  setState(() => _isLoading = false);

  if (result['success']) {
    UIHelpers.showSuccess(context, "Data loaded successfully!");
  } else {
    UIHelpers.showError(context, result['error'] ?? 'Failed to load data');
  }
}
```

## Pattern 2: Async function with navigation

```dart
Future<void> saveAndReturn() async {
  if (!mounted) return;
  setState(() => _isSaving = true);

  final result = await ApiService.saveData(data);
  if (!mounted) return;

  setState(() => _isSaving = false);

  if (result['success']) {
    UIHelpers.showSuccess(context, "Saved successfully!");
    if (mounted) Navigator.pop(context);
  } else {
    UIHelpers.showError(context, result['error'] ?? 'Failed to save');
  }
}
```

## Pattern 3: Dialog with async submit

```dart
void _showCreateDialog(BuildContext context) {
  final nameController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Create Item"),
      content: TextField(controller: nameController),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(context);

            final result = await ApiService.createItem({
              'name': nameController.text,
            });

            if (!mounted) return;

            if (result['success']) {
              UIHelpers.showSuccess(context, 'Item created!');
              await _loadItems();
            } else {
              UIHelpers.showError(context, result['error'] ?? 'Failed to create');
            }
          },
          child: const Text("Create"),
        ),
      ],
    ),
  );
}
```

## Pattern 4: Delete with confirmation

```dart
Future<void> deleteItem(int itemId) async {
  final confirmed = await UIHelpers.showConfirmDialog(
    context: context,
    title: "Delete Item",
    message: "Are you sure you want to delete this item?",
    isDangerous: true,
  );

  if (!confirmed) return;

  final result = await ApiService.deleteItem(itemId);
  if (!mounted) return;

  if (result['success']) {
    UIHelpers.showSuccess(context, 'Item deleted');
    await _loadItems();
  } else {
    UIHelpers.showError(context, result['error'] ?? 'Failed to delete');
  }
}
```

## Pattern 5: Multiple async operations

```dart
Future<void> loadAllData() async {
  if (!mounted) return;
  setState(() => _isLoading = true);

  try {
    final users = await ApiService.getUsers();
    if (!mounted) return;

    final classes = await ApiService.getClasses();
    if (!mounted) return;

    final attendance = await ApiService.getAttendance();
    if (!mounted) return;

    setState(() {
      _users = users['data'] ?? [];
      _classes = classes['data'] ?? [];
      _attendance = attendance['data'] ?? [];
      _isLoading = false;
    });

    UIHelpers.showSuccess(context, "All data loaded!");
  } catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    UIHelpers.showError(context, "Error loading data: $e");
  }
}
```

## Pattern 6: Form validation + submit

```dart
Future<void> handleSubmit() async {
  if (!_formKey.currentState!.validate()) {
    UIHelpers.showWarning(context, "Please fill all required fields");
    return;
  }

  if (!mounted) return;
  setState(() => _isSubmitting = true);

  try {
    final result = await ApiService.submitForm({
      'field1': _controller1.text,
      'field2': _controller2.text,
    });

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success']) {
      UIHelpers.showSuccess(context, "Form submitted successfully!");
      if (mounted) Navigator.pop(context);
    } else {
      UIHelpers.showError(context, result['error'] ?? 'Submission failed');
    }
  } catch (e) {
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    UIHelpers.showError(context, "Error: $e");
  }
}
```

