import 'package:quan_ly_giao_thong/models/car.dart';

class CarService {
  // Singleton pattern
  static final CarService _instance = CarService._internal();
  factory CarService() => _instance;
  CarService._internal();

  // Sample car data
  final List<Car> _cars = [
    Car(
      id: '1',
      make: 'Toyota',
      model: 'Camry',
      licensePlate: 'ABC-1234',
      year: 2020,
      color: 'Silver',
      mileage: 15000,
      purchaseDate: DateTime(2020, 5, 15),
      fuelLevel: 0.75,
      lastMaintenanceDate: DateTime(2023, 3, 10),
      nextMaintenanceDate: DateTime(2023, 9, 10),
    ),
    Car(
      id: '2',
      make: 'Honda',
      model: 'Civic',
      licensePlate: 'XYZ-5678',
      year: 2021,
      color: 'Blue',
      mileage: 8500,
      purchaseDate: DateTime(2021, 1, 20),
      fuelLevel: 0.5,
      lastMaintenanceDate: DateTime(2023, 2, 5),
      nextMaintenanceDate: DateTime(2023, 8, 5),
    ),
    Car(
      id: '3',
      make: 'Ford',
      model: 'F-150',
      licensePlate: 'DEF-9012',
      year: 2019,
      color: 'Red',
      mileage: 25000,
      purchaseDate: DateTime(2019, 8, 10),
      fuelLevel: 0.25,
      lastMaintenanceDate: DateTime(2023, 1, 15),
      nextMaintenanceDate: DateTime(2023, 7, 15),
    ),
    Car(
      id: '4',
      make: 'Chevrolet',
      model: 'Malibu',
      licensePlate: 'GHI-3456',
      year: 2022,
      color: 'Black',
      mileage: 5000,
      purchaseDate: DateTime(2022, 3, 5),
      fuelLevel: 0.9,
      lastMaintenanceDate: DateTime(2023, 4, 20),
      nextMaintenanceDate: DateTime(2023, 10, 20),
    ),
    Car(
      id: '5',
      make: 'Nissan',
      model: 'Altima',
      licensePlate: 'JKL-7890',
      year: 2020,
      color: 'White',
      mileage: 18000,
      purchaseDate: DateTime(2020, 11, 12),
      fuelLevel: 0.6,
      lastMaintenanceDate: DateTime(2023, 5, 8),
      nextMaintenanceDate: DateTime(2023, 11, 8),
    ),
  ];

  // Get all cars
  List<Car> getAllCars() {
    return _cars;
  }

  // Get car by ID
  Car? getCarById(String id) {
    try {
      return _cars.firstWhere((car) => car.id == id);
    } catch (e) {
      return null;
    }
  }

  // Add a new car
  void addCar(Car car) {
    _cars.add(car);
  }

  // Update an existing car
  void updateCar(Car updatedCar) {
    final index = _cars.indexWhere((car) => car.id == updatedCar.id);
    if (index != -1) {
      _cars[index] = updatedCar;
    }
  }

  // Delete a car
  void deleteCar(String id) {
    _cars.removeWhere((car) => car.id == id);
  }

  // Get cars that need maintenance (next maintenance date is within 30 days)
  List<Car> getCarsNeedingMaintenance() {
    final now = DateTime.now();
    final thirtyDaysLater = now.add(const Duration(days: 30));
    return _cars
        .where((car) => car.nextMaintenanceDate.isBefore(thirtyDaysLater))
        .toList();
  }

  // Get total fuel level across all cars
  double getTotalFuelLevel() {
    return _cars.fold(0, (sum, car) => sum + car.fuelLevel);
  }

  // Get average mileage across all cars
  double getAverageMileage() {
    if (_cars.isEmpty) return 0;
    final totalMileage = _cars.fold(0.0, (sum, car) => sum + car.mileage);
    return totalMileage / _cars.length;
  }

  // Generate a simple maintenance report
  Map<String, dynamic> generateMaintenanceReport() {
    final carsNeedingMaintenance = getCarsNeedingMaintenance();
    final totalMaintenance = carsNeedingMaintenance.length;
    final nextMaintenanceDate =
        carsNeedingMaintenance.isNotEmpty
            ? carsNeedingMaintenance
                .map((car) => car.nextMaintenanceDate)
                .reduce((a, b) => a.isBefore(b) ? a : b)
            : null;

    return {
      'totalCarsNeedingMaintenance': totalMaintenance,
      'nextMaintenanceDate': nextMaintenanceDate,
      'carsNeedingMaintenance': carsNeedingMaintenance,
    };
  }
}
