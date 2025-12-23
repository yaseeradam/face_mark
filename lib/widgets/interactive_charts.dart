import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class InteractiveCharts extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String type;
  
  const InteractiveCharts({super.key, required this.data, required this.type});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case 'line':
        return _buildLineChart();
      case 'bar':
        return _buildBarChart();
      case 'pie':
        return _buildPieChart();
      default:
        return _buildLineChart();
    }
  }

  Widget _buildLineChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString()),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString()),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: data.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), (entry.value['value'] ?? 0).toDouble());
            }).toList(),
            isCurved: true,
            color: Colors.blue,
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString()),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString()),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        barGroups: data.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: (entry.value['value'] ?? 0).toDouble(),
                color: Colors.blue,
                width: 20,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPieChart() {
    return PieChart(
      PieChartData(
        sections: data.asMap().entries.map((entry) {
          final colors = [Colors.blue, Colors.green, Colors.orange, Colors.red, Colors.purple];
          return PieChartSectionData(
            value: (entry.value['value'] ?? 0).toDouble(),
            title: '${entry.value['label'] ?? ''}',
            color: colors[entry.key % colors.length],
            radius: 100,
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
          );
        }).toList(),
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }
}

class AttendanceChart extends StatelessWidget {
  final List<Map<String, dynamic>> attendanceData;
  
  const AttendanceChart({super.key, required this.attendanceData});

  @override
  Widget build(BuildContext context) {
    final chartData = _processAttendanceData();
    
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Attendance Trends', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Expanded(
            child: InteractiveCharts(data: chartData, type: 'line'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _processAttendanceData() {
    final Map<String, int> dailyCount = {};
    
    for (final record in attendanceData) {
      final date = record['date']?.toString() ?? '';
      dailyCount[date] = (dailyCount[date] ?? 0) + 1;
    }
    
    return dailyCount.entries.map((entry) => {
      'label': entry.key,
      'value': entry.value,
    }).toList();
  }
}