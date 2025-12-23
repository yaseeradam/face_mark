import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateRangePicker extends StatefulWidget {
  final DateTimeRange? initialRange;
  final Function(DateTimeRange?) onRangeChanged;
  final String label;
  
  const DateRangePicker({
    super.key,
    this.initialRange,
    required this.onRangeChanged,
    this.label = 'Select Date Range',
  });

  @override
  State<DateRangePicker> createState() => _DateRangePickerState();
}

class _DateRangePickerState extends State<DateRangePicker> {
  DateTimeRange? _selectedRange;

  @override
  void initState() {
    super.initState();
    _selectedRange = widget.initialRange;
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedRange,
    );

    if (picked != null && picked != _selectedRange) {
      setState(() {
        _selectedRange = picked;
      });
      widget.onRangeChanged(picked);
    }
  }

  void _clearRange() {
    setState(() {
      _selectedRange = null;
    });
    widget.onRangeChanged(null);
  }

  String _formatRange(DateTimeRange range) {
    final formatter = DateFormat('MMM dd, yyyy');
    return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(Icons.date_range, color: theme.colorScheme.primary),
        title: Text(
          _selectedRange != null ? _formatRange(_selectedRange!) : widget.label,
          style: TextStyle(
            color: _selectedRange != null ? theme.colorScheme.onSurface : theme.hintColor,
          ),
        ),
        trailing: _selectedRange != null
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: _clearRange,
              )
            : const Icon(Icons.arrow_drop_down),
        onTap: _selectDateRange,
      ),
    );
  }
}

class QuickDateFilters extends StatelessWidget {
  final Function(DateTimeRange?) onRangeSelected;
  
  const QuickDateFilters({super.key, required this.onRangeSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        _buildFilterChip('Today', _getTodayRange()),
        _buildFilterChip('This Week', _getThisWeekRange()),
        _buildFilterChip('This Month', _getThisMonthRange()),
        _buildFilterChip('Last 7 Days', _getLast7DaysRange()),
        _buildFilterChip('Last 30 Days', _getLast30DaysRange()),
      ],
    );
  }

  Widget _buildFilterChip(String label, DateTimeRange range) {
    return ActionChip(
      label: Text(label),
      onPressed: () => onRangeSelected(range),
    );
  }

  DateTimeRange _getTodayRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
  }

  DateTimeRange _getThisWeekRange() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    return DateTimeRange(start: start, end: start.add(const Duration(days: 7)));
  }

  DateTimeRange _getThisMonthRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    return DateTimeRange(start: start, end: end);
  }

  DateTimeRange _getLast7DaysRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 7));
    return DateTimeRange(start: start, end: end);
  }

  DateTimeRange _getLast30DaysRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 30));
    return DateTimeRange(start: start, end: end);
  }
}