import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'judging_store.dart';
import 'models.dart';
import 'supabase_api.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supabaseApiKey = supabasePublishableKey.isNotEmpty ? supabasePublishableKey : supabaseAnonKey;
  final store = JudgingStore(SupabaseApi(url: supabaseUrl, anonKey: supabaseApiKey));
  await store.initialize();
  runApp(JueceoTabletApp(store: store));
}

class JueceoTabletApp extends StatelessWidget {
  const JueceoTabletApp({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jueceo Coreografias',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff111827)),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      home: AnimatedBuilder(
        animation: store,
        builder: (context, _) => TabletShell(store: store),
      ),
    );
  }
}

class TabletShell extends StatefulWidget {
  const TabletShell({super.key, required this.store});

  final JudgingStore store;

  @override
  State<TabletShell> createState() => _TabletShellState();
}

class _TabletShellState extends State<TabletShell> {
  int section = 0;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final pages = [
      EventsPage(store: store),
      BlocksPage(store: store),
      JudgingPage(store: store),
      ScoresPage(store: store),
      DictamenPage(store: store),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(store.selectedEvent?.name ?? 'Jueceo Coreografias'),
        actions: [
          SyncChip(store: store),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () {
              store.refreshEvents();
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: section,
            onDestinationSelected: (index) => setState(() => section = index),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.event), label: Text('Evento')),
              NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('Bloques')),
              NavigationRailDestination(icon: Icon(Icons.fact_check), label: Text('Jueceo')),
              NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Calificaciones')),
              NavigationRailDestination(icon: Icon(Icons.emoji_events), label: Text('Dictamen')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[section]),
        ],
      ),
    );
  }
}

class SyncChip extends StatelessWidget {
  const SyncChip({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    final color = switch (store.syncState) {
      SyncState.online => Colors.green,
      SyncState.connecting || SyncState.syncing => Colors.blue,
      SyncState.pending => Colors.orange,
      SyncState.offline => Colors.red,
      SyncState.localOnly => Colors.grey,
    };
    final label = store.pendingCount > 0 ? '${store.syncState.name} ${store.pendingCount}' : store.syncState.name;
    return Chip(
      avatar: Icon(Icons.cloud_queue, color: color, size: 18),
      label: Text(label),
      side: BorderSide(color: color.withOpacity(0.35)),
      backgroundColor: color.withOpacity(0.10),
    );
  }
}

class EventsPage extends StatelessWidget {
  const EventsPage({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    if (!store.api.isConfigured) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: 'Supabase no configurado',
        message: store.syncMessage,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Eventos', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        for (final event in store.events)
          Card(
            child: ListTile(
              leading: Icon(event.isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(event.name),
              subtitle: Text(event.sourceName.isEmpty ? event.slug : event.sourceName),
              trailing: event.id == store.selectedEvent?.id ? const Icon(Icons.check_circle) : null,
              onTap: () {
                store.selectEvent(event);
              },
            ),
          ),
      ],
    );
  }
}

class BlocksPage extends StatefulWidget {
  const BlocksPage({super.key, required this.store});

  final JudgingStore store;

  @override
  State<BlocksPage> createState() => _BlocksPageState();
}

class _BlocksPageState extends State<BlocksPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final filtered = store.routines.where((routine) {
      final haystack = '${routine.id} ${routine.name} ${routine.academy} ${routine.genre} ${routine.category}'.toUpperCase();
      return haystack.contains(query.toUpperCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar coreografia, academia o genero'),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final block in store.blocks)
                if (filtered.any((routine) => routine.block == block.name))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(block.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        if (block.title.isNotEmpty) Text(block.title),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final routine in filtered.where((routine) => routine.block == block.name))
                              SizedBox(
                                width: 320,
                                child: RoutineCard(
                                  routine: routine,
                                  selected: routine.id == store.selectedRoutineId,
                                  onTap: () => store.selectRoutine(routine.id),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class RoutineCard extends StatelessWidget {
  const RoutineCard({super.key, required this.routine, required this.selected, required this.onTap});

  final Routine routine;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('#${routine.id}  ${routine.time}', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(routine.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(routine.academy, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${routine.genre} · ${routine.division} · ${routine.category}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class JudgingPage extends StatefulWidget {
  const JudgingPage({super.key, required this.store});

  final JudgingStore store;

  @override
  State<JudgingPage> createState() => _JudgingPageState();
}

class _JudgingPageState extends State<JudgingPage> {
  final Map<int, TextEditingController> controllers = {};
  final feedbackController = TextEditingController();

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final routine = store.selectedRoutine;
    if (routine == null) {
      return const EmptyState(icon: Icons.inbox, title: 'Sin rutinas', message: 'Carga un evento para empezar.');
    }
    final template = store.templateFor(routine);
    for (final criterion in template.criteria) {
      controllers.putIfAbsent(
        criterion.id,
        () => TextEditingController(
          text: store.scoreFor(routine, store.selectedJudge, criterion) == 0
              ? ''
              : store.scoreFor(routine, store.selectedJudge, criterion).toStringAsFixed(1),
        ),
      );
    }
    feedbackController.text = store.feedback[store.feedbackKey(routine.id, store.selectedJudge)] ?? '';

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              DropdownButtonFormField<String>(
                value: store.judges.contains(store.selectedJudge) ? store.selectedJudge : null,
                decoration: const InputDecoration(labelText: 'Juez'),
                items: [for (final judge in store.judges) DropdownMenuItem(value: judge, child: Text(judge))],
                onChanged: (value) {
                  if (value != null) store.selectJudge(value);
                },
              ),
              const SizedBox(height: 12),
              for (final item in store.routines)
                ListTile(
                  dense: true,
                  selected: item.id == routine.id,
                  title: Text('#${item.id} ${item.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(item.genre),
                  onTap: () {
                    controllers.clear();
                    store.selectRoutine(item.id);
                  },
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('#${routine.id} ${routine.name}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text('${routine.academy} · ${routine.genre} · ${routine.division} · ${routine.category}'),
              const SizedBox(height: 20),
              for (final criterion in template.criteria)
                Card(
                  child: ListTile(
                    title: Text('${criterion.id}. ${criterion.label}'),
                    subtitle: Text(criterion.section),
                    trailing: SizedBox(
                      width: 96,
                      child: TextField(
                        controller: controllers[criterion.id],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(suffixText: '/10'),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: feedbackController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Feedback', alignLabelWithHint: true),
                onChanged: (value) {
                  store.setFeedback(routine, value);
                },
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  final values = <int, double>{};
                  for (final criterion in template.criteria) {
                    final value = double.tryParse(controllers[criterion.id]?.text.replaceAll(',', '.') ?? '');
                    if (value == null || value < 0 || value > 10) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Completa todas las notas entre 0 y 10.')),
                      );
                      return;
                    }
                    values[criterion.id] = value;
                  }
                  await store.submitScores(routine, values);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Calificaciones enviadas.')));
                  }
                },
                icon: const Icon(Icons.send),
                label: const Text('Submit'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ScoresPage extends StatelessWidget {
  const ScoresPage({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    final results = store.rankings;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('${results.length} resultados', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  exportResultsPdf(store);
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Pos')),
                const DataColumn(label: Text('#')),
                const DataColumn(label: Text('Coreografia')),
                const DataColumn(label: Text('Academia')),
                const DataColumn(label: Text('Genero')),
                for (final judge in store.judges) DataColumn(label: Text(judge)),
                const DataColumn(label: Text('Total')),
              ],
              rows: [
                for (final indexed in results.indexed)
                  DataRow(cells: [
                    DataCell(Text(indexed.$2.total > 0 ? '${indexed.$1 + 1}' : '-')),
                    DataCell(Text(indexed.$2.routine.id)),
                    DataCell(SizedBox(width: 220, child: Text(indexed.$2.routine.name, overflow: TextOverflow.ellipsis))),
                    DataCell(SizedBox(width: 220, child: Text(indexed.$2.routine.academy, overflow: TextOverflow.ellipsis))),
                    DataCell(Text(indexed.$2.routine.genre)),
                    for (final judge in store.judges) DataCell(Text((indexed.$2.judgeTotals[judge] ?? 0).toStringAsFixed(1))),
                    DataCell(Text(indexed.$2.total > 0 ? indexed.$2.total.toStringAsFixed(2) : '-')),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DictamenPage extends StatelessWidget {
  const DictamenPage({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<RoutineResult>>{};
    for (final result in store.rankings) {
      final key = '${result.routine.genre} · ${result.routine.division} · ${result.routine.category}';
      groups.putIfAbsent(key, () => []).add(result);
    }
    return GridView.extent(
      padding: const EdgeInsets.all(16),
      maxCrossAxisExtent: 430,
      childAspectRatio: 1.55,
      children: [
        for (final entry in groups.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(),
                  for (final indexed in entry.value.take(5).toList().indexed)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(child: Text('${indexed.$1 + 1}')),
                      title: Text(indexed.$2.routine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(indexed.$2.routine.academy, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text(indexed.$2.total > 0 ? indexed.$2.total.toStringAsFixed(2) : '-'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

Future<void> exportResultsPdf(JudgingStore store) async {
  final document = pw.Document();
  final results = store.rankings;
  document.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text('Calificaciones y Dictamen Final', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Fuente: ${store.appData?.sourceName ?? store.selectedEvent?.name ?? ''}'),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: ['Pos', '#', 'Coreografia', 'Academia', 'Categoria', 'Total'],
          data: [
            for (final indexed in results.indexed)
              [
                indexed.$2.total > 0 ? '${indexed.$1 + 1}' : '-',
                indexed.$2.routine.id,
                indexed.$2.routine.name,
                indexed.$2.routine.academy,
                '${indexed.$2.routine.genre} ${indexed.$2.routine.division} ${indexed.$2.routine.category}',
                indexed.$2.total > 0 ? indexed.$2.total.toStringAsFixed(2) : '-',
              ],
          ],
        ),
      ],
    ),
  );
  await Printing.sharePdf(bytes: await document.save(), filename: 'calificaciones-dictamen-final.pdf');
}
