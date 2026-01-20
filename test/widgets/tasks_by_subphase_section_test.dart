import 'package:flutter_test/flutter_test.dart';
import 'package:sky_engineering_app/src/widgets/tasks_by_subphase_section.dart'
    show isProjectTaskActiveStatus;

void main() {
  group('isProjectTaskActiveStatus', () {
    test('only treats In Progress tasks as active', () {
      expect(isProjectTaskActiveStatus('In Progress'), isTrue);
      expect(isProjectTaskActiveStatus(' in progress '), isTrue);
      expect(isProjectTaskActiveStatus('Pending'), isFalse);
      expect(isProjectTaskActiveStatus('pending'), isFalse);
      expect(isProjectTaskActiveStatus('On Hold'), isFalse);
      expect(isProjectTaskActiveStatus('Completed'), isFalse);
      expect(isProjectTaskActiveStatus(null), isFalse);
    });
  });
}
