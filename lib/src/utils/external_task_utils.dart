// lib/src/utils/external_task_utils.dart
import '../data/models/project.dart';
import '../data/models/external_assignee_option.dart';

class ProjectTeamField {
  const ProjectTeamField({required this.key, required this.label});

  final String key;
  final String label;
}

const List<ProjectTeamField> kProjectTeamFields = [
  ProjectTeamField(key: 'teamOwner', label: 'Owner'),
  ProjectTeamField(key: 'teamArchitect', label: 'Architect'),
  ProjectTeamField(key: 'teamSurveyor', label: 'Surveyor'),
  ProjectTeamField(key: 'teamGeotechnical', label: 'Geotechnical'),
  ProjectTeamField(key: 'teamMechanical', label: 'Mechanical'),
  ProjectTeamField(key: 'teamStructural', label: 'Structural'),
  ProjectTeamField(key: 'teamElectrical', label: 'Electrical'),
  ProjectTeamField(key: 'teamPlumbing', label: 'Plumbing'),
  ProjectTeamField(key: 'teamLandscape', label: 'Landscape'),
  ProjectTeamField(key: 'teamContractor', label: 'Contractor'),
  ProjectTeamField(key: 'teamEnvironmental', label: 'Environmental'),
  ProjectTeamField(key: 'teamOther', label: 'Other'),
];

Map<String, String?> projectTeamValueMap(Project project) => {
      'teamOwner': project.teamOwner,
      'teamArchitect': project.teamArchitect,
      'teamSurveyor': project.teamSurveyor,
      'teamGeotechnical': project.teamGeotechnical,
      'teamMechanical': project.teamMechanical,
      'teamStructural': project.teamStructural,
      'teamElectrical': project.teamElectrical,
      'teamPlumbing': project.teamPlumbing,
      'teamLandscape': project.teamLandscape,
      'teamContractor': project.teamContractor,
      'teamEnvironmental': project.teamEnvironmental,
      'teamOther': project.teamOther,
    };

List<ExternalAssigneeOption> buildExternalAssigneeOptions(
  Project project, {
  String? ownerEmail,
}) {
  final options = <ExternalAssigneeOption>[];

  if (ownerEmail != null) {
    final email = ownerEmail.trim();
    final label = email.isEmpty ? 'Owner' : 'Owner ($email)';
    options.add(
      ExternalAssigneeOption(key: 'owner', label: label, value: label),
    );
  }

  final values = projectTeamValueMap(project);
  for (final field in kProjectTeamFields) {
    final value = values[field.key];
    if (value == null) continue;
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    final label = '${field.label} - $trimmed';
    options.add(
      ExternalAssigneeOption(key: field.key, label: label, value: label),
    );
  }

  return options;
}

List<ExternalAssigneeOption> dedupeExternalAssigneeOptions(
  List<ExternalAssigneeOption> options,
) {
  final map = <String, ExternalAssigneeOption>{};
  for (final option in options) {
    map[option.key] = option;
  }
  return map.values.toList(growable: false);
}
