import 'package:flutter_test/flutter_test.dart';
import 'package:frontalminds_fr/services/validation_service.dart';

void main() {
  group('ValidationService Tests', () {
    test('validateEmail should return null for valid email', () {
      expect(ValidationService.validateEmail('test@example.com'), null);
      expect(ValidationService.validateEmail('user.name@domain.co.uk'), null);
    });

    test('validateEmail should return error for invalid email', () {
      expect(ValidationService.validateEmail(''), 'Email is required');
      expect(ValidationService.validateEmail('invalid-email'), 'Invalid email format');
      expect(ValidationService.validateEmail('test@'), 'Invalid email format');
    });

    test('validateStudentId should return null for valid ID', () {
      expect(ValidationService.validateStudentId('STU001'), null);
      expect(ValidationService.validateStudentId('2024001'), null);
    });

    test('validateStudentId should return error for invalid ID', () {
      expect(ValidationService.validateStudentId(''), 'Student ID is required');
      expect(ValidationService.validateStudentId('123'), 'Student ID must be at least 6 characters');
      expect(ValidationService.validateStudentId('stu001'), 'Only uppercase letters and numbers allowed');
    });

    test('validateName should return null for valid name', () {
      expect(ValidationService.validateName('John Doe'), null);
      expect(ValidationService.validateName('Alice'), null);
    });

    test('validateName should return error for invalid name', () {
      expect(ValidationService.validateName(''), 'Name is required');
      expect(ValidationService.validateName('A'), 'Name must be at least 2 characters');
      expect(ValidationService.validateName('John123'), 'Only letters and spaces allowed');
    });

    test('validatePassword should return null for valid password', () {
      expect(ValidationService.validatePassword('password123'), null);
      expect(ValidationService.validatePassword('123456'), null);
    });

    test('validatePassword should return error for invalid password', () {
      expect(ValidationService.validatePassword(''), 'Password is required');
      expect(ValidationService.validatePassword('123'), 'Password must be at least 6 characters');
    });
  });
}