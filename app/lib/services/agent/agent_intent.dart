import '../../core/models/agent/agent_profile.dart';

/// Deterministic request hint built locally before the main analysis call.
///
/// It is not a classifier gate: the user request stays authoritative and no
/// extra provider call is made. The hint only helps the main model prioritize
/// translation, grammar, explanation, reading and correction sections.
class AgentIntentHint {
  const AgentIntentHint({
    this.tasks = const <String>[],
    this.multipleTasks = false,
  });

  final List<String> tasks;
  final bool multipleTasks;

  bool get isEmpty => tasks.isEmpty && !multipleTasks;

  String toPrompt(AgentResponseLanguage language) {
    final taskText = tasks.isEmpty
        ? 'general reading/explanation'
        : tasks.join(', ');
    return '''
Local request hint (deterministic; the user request remains authoritative):
- likely tasks: $taskText
- output language: ${language.wireName}
- multiple tasks/questions: ${multipleTasks ? 'yes' : 'no'}
Use this only to prioritize response sections; do not add a task the user did not ask for.
''';
  }
}

AgentIntentHint detectAgentIntent(String request) {
  final text = request.toLowerCase();
  final tasks = <String>[];

  void addTask(String task, List<String> keywords) {
    if (tasks.contains(task)) return;
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        tasks.add(task);
        return;
      }
    }
  }

  addTask('translation', const <String>[
    '翻译',
    '译成',
    '译为',
    '译文',
    'translate',
    'translation',
    '翻訳',
    '訳して',
    '訳す',
  ]);
  addTask('grammar', const <String>[
    '语法',
    '文法',
    '句型',
    '助词',
    '助動詞',
    '活用',
    'grammar',
    'particle',
    'conjugation',
  ]);
  addTask('explanation', const <String>[
    '解释',
    '意思',
    '含义',
    '怎么理解',
    '说明',
    'explain',
    'meaning',
    '意味',
    '解説',
  ]);
  addTask('reading', const <String>[
    '读音',
    '怎么读',
    '发音',
    'reading',
    'pronunciation',
    '読み',
    '発音',
  ]);
  addTask('correction', const <String>[
    '校对',
    '纠错',
    '修正',
    '识别错',
    'ocr',
    'typo',
    'correct',
  ]);

  final questionMarks = RegExp(r'[?？]').allMatches(request).length;
  return AgentIntentHint(
    tasks: List<String>.unmodifiable(tasks),
    multipleTasks: tasks.length > 1 || questionMarks >= 2,
  );
}
