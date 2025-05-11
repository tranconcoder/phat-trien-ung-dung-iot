import 'package:quan_ly_giao_thong/models/maintenance.dart';

class MaintenanceService {
  // Singleton pattern
  static final MaintenanceService _instance = MaintenanceService._internal();
  factory MaintenanceService() => _instance;
  MaintenanceService._internal();

  // Sample maintenance data
  final List<Maintenance> _maintenanceRecords = [
    Maintenance(
      id: '1',
      carId: '1',
      title: 'Oil Change',
      description: 'Regular oil change and filter replacement',
      date: DateTime(2023, 9, 15),
      cost: 50.0,
      serviceCenter: 'Toyota Service Center',
      isCompleted: false,
    ),
    Maintenance(
      id: '2',
      carId: '2',
      title: 'Tire Rotation',
      description: 'Rotate tires for even wear',
      date: DateTime(2023, 8, 22),
      cost: 30.0,
      serviceCenter: 'Honda Service Center',
      isCompleted: false,
    ),
    Maintenance(
      id: '3',
      carId: '3',
      title: 'Brake Inspection',
      description: 'Check brake pads and rotors',
      date: DateTime(2023, 7, 10),
      cost: 75.0,
      serviceCenter: 'Ford Service Center',
      isCompleted: false,
    ),
    Maintenance(
      id: '4',
      carId: '4',
      title: 'Air Filter Replacement',
      description: 'Replace cabin and engine air filters',
      date: DateTime(2023, 10, 5),
      cost: 40.0,
      serviceCenter: 'Chevrolet Service Center',
      isCompleted: false,
    ),
    Maintenance(
      id: '5',
      carId: '5',
      title: 'Battery Check',
      description: 'Inspect battery condition and terminals',
      date: DateTime(2023, 11, 15),
      cost: 25.0,
      serviceCenter: 'Nissan Service Center',
      isCompleted: false,
    ),
    Maintenance(
      id: '6',
      carId: '1',
      title: 'Transmission Fluid Change',
      description: 'Change transmission fluid',
      date: DateTime(2023, 12, 20),
      cost: 120.0,
      serviceCenter: 'Toyota Service Center',
      isCompleted: false,
    ),
  ];

  // Get all maintenance records
  List<Maintenance> getAllMaintenanceRecords() {
    return _maintenanceRecords;
  }

  // Get maintenance records for a specific car
  List<Maintenance> getMaintenanceRecordsForCar(String carId) {
    return _maintenanceRecords
        .where((record) => record.carId == carId)
        .toList();
  }

  // Get upcoming maintenance records (not completed)
  List<Maintenance> getUpcomingMaintenanceRecords() {
    return _maintenanceRecords.where((record) => !record.isCompleted).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // Mark maintenance record as completed
  void markMaintenanceAsCompleted(String id) {
    final index = _maintenanceRecords.indexWhere((record) => record.id == id);
    if (index != -1) {
      final updated = _maintenanceRecords[index].copyWith(isCompleted: true);
      _maintenanceRecords[index] = updated;
    }
  }

  // Add new maintenance record
  void addMaintenanceRecord(Maintenance record) {
    _maintenanceRecords.add(record);
  }

  // Update existing maintenance record
  void updateMaintenanceRecord(Maintenance updatedRecord) {
    final index = _maintenanceRecords.indexWhere(
      (record) => record.id == updatedRecord.id,
    );
    if (index != -1) {
      _maintenanceRecords[index] = updatedRecord;
    }
  }

  // Delete maintenance record
  void deleteMaintenanceRecord(String id) {
    _maintenanceRecords.removeWhere((record) => record.id == id);
  }

  // Get total maintenance cost
  double getTotalMaintenanceCost() {
    return _maintenanceRecords.fold(0, (sum, record) => sum + record.cost);
  }

  // Get upcoming maintenance cost
  double getUpcomingMaintenanceCost() {
    return _maintenanceRecords
        .where((record) => !record.isCompleted)
        .fold(0, (sum, record) => sum + record.cost);
  }
}
