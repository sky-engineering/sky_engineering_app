import 'package:flutter_test/flutter_test.dart';
import 'package:sky_engineering_app/src/data/models/task.dart';

TaskItem _taskWithStatus(String? status) => TaskItem(
      id: 'id',
      projectId: 'project',
      ownerUid: 'owner',
      title: 'Example task',
      status: status,
    );

void main() {
  group('TaskItem legacy status mapping', () {
    test('normalizes both legacy and new names', () {
      expect(_taskWithStatus('Done').taskStatus, 'Completed');
      expect(_taskWithStatus('completed').taskStatus, 'Completed');
      expect(_taskWithStatus('Blocked').taskStatus, 'On Hold');
      expect(_taskWithStatus('On Hold').taskStatus, 'On Hold');
      expect(_taskWithStatus('Open').taskStatus, 'Pending');
      expect(_taskWithStatus('pending').taskStatus, 'Pending');
      expect(_taskWithStatus('In Progress').taskStatus, 'In Progress');
      expect(_taskWithStatus('in-progress').taskStatus, 'In Progress');
    });

    test('falls back to Pending for unknown values', () {
      expect(_taskWithStatus('Something Else').taskStatus, 'Pending');
      expect(_taskWithStatus(null).taskStatus, 'Pending');
    });
  });
}
