/// Example: Quick Reference for Widget Lifecycle Safety
/// Copy and paste these patterns when adding new async operations

// ==========================================
// PATTERN 1: Basic Async Function with UI Feedback
// ==========================================
Future<void> loadData() async {
  if (!mounted) return;  // Always check first
  setState(() => _isLoading = true);
  
  final result = await ApiService.getData();
  if (!mounted) return;  // Always check after async
  
  setState(() => _isLoading = false);
  
  if (result['success']) {
    UIHelpers.showSuccess(context, "Data loaded successfully!");
  } else {
    UIHelpers.showError(context, result['error'] ?? 'Failed to load data');
  }
}

// ==========================================
// PATTERN 2:  Async Function with Navigation
// ==========================================
Future<void> saveAndReturn() async {
  if (!mounted) return;
  setState(() => _isSaving = true);
  
  final result = await ApiService.saveData(data);
  if (!mounted) return;
  
  setState(() => _isSaving = false);
  
  if (result['success']) {
    UIHelpers.showSuccess(context, "Saved successfully!");
    if (mounted) Navigator.pop(context);  // Check before navigating
  } else {
    UIHelpers.showError(context, result['error'] ?? 'Failed to save');
  }
}

// ==========================================
// PATTERN 3: Dialog with Async Submit
// ==========================================
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
            // Close dialog first
            Navigator.pop(context);
            
            // Then do async work
            final result = await ApiService.createItem({
              'name': nameController.text,
            });
            
            // Check mounted before showing feedback
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

// ==========================================
// PATTERN 4: Delete with Confirmation
// ==========================================
Future<void> deleteItem(int itemId) async {
  final confirmed = await UIHelpers.showConfirmDialog(
    context: context,
    title: "Delete Item",
    message: "Are you sure you want to delete this item?",
    isDangerous: true,
  );
  
  if (confirmed) {
    final result = await ApiService.deleteItem(itemId);
    if (!mounted) return;
    
    if (result['success']) {
      UIHelpers.showSuccess(context, 'Item deleted');
      await _loadItems();
    } else {
      UIHelpers.showError(context, result['error'] ?? 'Failed to delete');
    }
  }
}

// ==========================================
// PATTERN 5: Multiple Async Operations
// ==========================================
Future<void> loadAllData() async {
  if (!mounted) return;
  setState(() => _isLoading = true);
  
  try {
    // First call
    final users = await ApiService.getUsers();
    if (!mounted) return;
    
    // Second call (depends on first)
    final classes = await ApiService.getClasses();
    if (!mounted) return;
    
    // Third call
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

// ==========================================
// PATTERN 6: Form Validation + Submit
// ==========================================
Future<void> handleSubmit() async {
  // Validate first (synchronous)
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
