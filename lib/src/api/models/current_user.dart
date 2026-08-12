/// The authenticated account, from Redmine's core `/users/current.json`.
/// Used to scope "assigned to me"; optional, since a token or role may not
/// permit the endpoint.
class CurrentUser {
  const CurrentUser({required this.id, required this.displayName});

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    if (user is! Map<String, dynamic>) {
      return const CurrentUser(id: 0, displayName: '');
    }
    final firstname = user['firstname'] as String? ?? '';
    final lastname = user['lastname'] as String? ?? '';
    final name = [
      firstname,
      lastname,
    ].where((part) => part.isNotEmpty).join(' ');
    return CurrentUser(
      id: (user['id'] as num?)?.toInt() ?? 0,
      displayName: name,
    );
  }

  final int id;

  /// Redmine's display form (firstname lastname), which is what bundle
  /// summaries carry in `assigned_to`.
  final String displayName;
}
