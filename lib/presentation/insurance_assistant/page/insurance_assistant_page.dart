import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/datasources/remote/insurance_assistant_remote_ds.dart';
import '../../../data/repositories/insurance_assistant_repository_impl.dart';
import '../../../core/utils/insurance_conversation_pdf_exporter.dart';
import '../../../domain/entities/insurance_assistant_models.dart';
import '../../../domain/repositories/insurance_assistant_repository.dart';

class InsuranceAssistantPage extends StatefulWidget {
  final String branchName;
  final VoidCallback onBack;
  final InsuranceAssistantRepository? repository;

  const InsuranceAssistantPage({
    super.key,
    required this.branchName,
    required this.onBack,
    this.repository,
  });

  @override
  State<InsuranceAssistantPage> createState() => _InsuranceAssistantPageState();
}

class _InsuranceAssistantPageState extends State<InsuranceAssistantPage> {
  late final InsuranceAssistantRepository _repository;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  List<InsuranceChatSession> _sessions = const [];
  List<InsuranceChatMessage> _messages = const [];
  String? _sessionId;
  InsuranceCitation? _selectedCitation;
  bool _loading = true;
  bool _sending = false;
  bool _exporting = false;
  bool _canManage = false;
  String? _error;
  int _sessionLoadGeneration = 0;
  final Set<String> _confirmedClarifications = {};

  static const _suggestions = [
    (
      'CGRP coverage',
      'What are the coverage conditions for CGRP inhibitors?',
      Icons.verified_user_rounded,
    ),
    (
      'Dose check',
      'What is the maximum dose of Ubrogepant?',
      Icons.medication_liquid_rounded,
    ),
    (
      'Age eligibility',
      'Is CGRP covered for a 16-year-old patient?',
      Icons.badge_outlined,
    ),
    (
      'GLP-1 documents',
      'What documentation is required for the initial GLP-1 dose?',
      Icons.description_outlined,
    ),
    (
      'سؤال بالعربية',
      'ما شروط صرف أدوية CGRP وهل تحتاج موافقة؟',
      Icons.translate_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        InsuranceAssistantRepositoryImpl(
          InsuranceAssistantRemoteDs(Supabase.instance.client),
        );
    _loadWorkspace();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspace() async {
    try {
      final results = await Future.wait([
        _repository.fetchSessions(),
        _repository.canManageDocuments(),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<InsuranceChatSession>;
        _canManage = results[1] as bool;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _openSession(InsuranceChatSession session) async {
    if (_sending) return;
    final generation = ++_sessionLoadGeneration;
    setState(() {
      _sessionId = session.id;
      _messages = const [];
      _selectedCitation = null;
      _loading = true;
    });
    try {
      final messages = await _repository.fetchMessages(session.id);
      if (!mounted || generation != _sessionLoadGeneration) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted || generation != _sessionLoadGeneration) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _newConversation() {
    if (_sending) return;
    _sessionLoadGeneration++;
    setState(() {
      _sessionId = null;
      _messages = const [];
      _selectedCitation = null;
      _error = null;
    });
    _focusNode.requestFocus();
  }

  Future<void> _send([String? suggestedQuestion]) async {
    final question = (suggestedQuestion ?? _messageController.text).trim();
    if (question.isEmpty || _sending) return;
    _messageController.clear();
    final optimistic = InsuranceChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      message: question,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, optimistic];
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final result = await _repository.ask(
        question: question,
        branchName: widget.branchName,
        sessionId: _sessionId,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = result.sessionId;
        _messages = [..._messages, result.message];
        _sending = false;
        if (result.message.citations.isNotEmpty) {
          _selectedCitation = result.message.citations.first;
        }
      });
      unawaited(_refreshSessions());
      _scrollToBottom();
      _focusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _friendlyError(error);
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _confirmClarification(
    InsuranceClarification clarification,
    InsuranceClarificationCandidate candidate,
  ) async {
    if (_sending || _confirmedClarifications.contains(clarification.id)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final result = await _repository.confirmClarification(
        clarificationId: clarification.id,
        candidateId: candidate.id,
        branchName: widget.branchName,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = result.sessionId;
        _messages = [..._messages, result.message];
        _confirmedClarifications.add(clarification.id);
        _sending = false;
        if (result.message.citations.isNotEmpty) {
          _selectedCitation = result.message.citations.first;
        }
      });
      unawaited(_refreshSessions());
      _scrollToBottom();
      _focusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _friendlyError(error);
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _refreshSessions() async {
    try {
      final sessions = await _repository.fetchSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _friendlyError(Object error) {
    final value = error.toString().replaceFirst('Exception: ', '');
    if (value.contains('insurance_documents') ||
        value.contains('is_insurance_knowledge') ||
        value.contains('insurance-assistant')) {
      return 'Insurance Knowledge backend is not deployed yet. Apply the migration and deploy the insurance-assistant function, then retry.';
    }
    return value;
  }

  Future<void> _openCitation(InsuranceCitation citation) async {
    try {
      final url = await _repository.createSourceUrl(citation);
      final launched = await launchUrl(
        Uri.parse(url),
        webOnlyWindowName: '_blank',
      );
      if (!launched)
        throw Exception('The source document could not be opened.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  Future<void> _showDocuments() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DocumentCenterDialog(repository: _repository),
    );
  }

  Future<void> _exportConversation() async {
    if (_messages.isEmpty || _exporting) return;
    String? title;
    for (final session in _sessions) {
      if (session.id == _sessionId) {
        title = session.title;
        break;
      }
    }
    setState(() => _exporting = true);
    try {
      await InsuranceConversationPdfExporter.export(
        messages: _messages,
        branchName: widget.branchName,
        conversationTitle: title,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversation PDF is ready to save or share.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not export conversation: ${_friendlyError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSessions = constraints.maxWidth >= 1040;
        final showEvidence = constraints.maxWidth >= 1320;
        return ColoredBox(
          color: const Color(0xFFF4F7FB),
          child: Column(
            children: [
              _AssistantHeader(
                branchName: widget.branchName,
                canManage: _canManage,
                onBack: widget.onBack,
                onNewConversation: _newConversation,
                onDocuments: _showDocuments,
                onExport: _exportConversation,
                exportEnabled: _messages.isNotEmpty && !_sending,
                exporting: _exporting,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showSessions) ...[
                        SizedBox(
                          width: 260,
                          child: _SessionsPanel(
                            sessions: _sessions,
                            selectedId: _sessionId,
                            onSelect: _openSession,
                            onNew: _newConversation,
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(child: _buildConversation(showEvidence)),
                      if (showEvidence) ...[
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 330,
                          child: _EvidencePanel(
                            citation: _selectedCitation,
                            onOpen: _openCitation,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConversation(bool evidenceBesideChat) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDE7F1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: .05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _ConversationStatus(
            documentCountLabel: 'Source-grounded • Arabic + English',
          ),
          if (_error != null)
            _ErrorBanner(message: _error!, onRetry: _loadWorkspace),
          Expanded(
            child: SelectionArea(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? _WelcomeView(suggestions: _suggestions, onAsk: _send)
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 20),
                      itemBuilder: (context, index) {
                        if (index == _messages.length)
                          return const _ThinkingBubble();
                        final message = _messages[index];
                        return _MessageBubble(
                          message: message,
                          selectedCitation: _selectedCitation,
                          onCitationTap: (citation) {
                            setState(() => _selectedCitation = citation);
                            if (!evidenceBesideChat) {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => FractionallySizedBox(
                                  heightFactor: .72,
                                  child: _EvidencePanel(
                                    citation: citation,
                                    onOpen: _openCitation,
                                  ),
                                ),
                              );
                            }
                          },
                          onFeedback: message.isUser
                              ? null
                              : (rating) => _repository.submitFeedback(
                                  message.id,
                                  rating,
                                ),
                          clarificationEnabled:
                              message.clarification != null &&
                              !_confirmedClarifications.contains(
                                message.clarification!.id,
                              ) &&
                              !_sending,
                          onClarificationSelected: (candidate) {
                            final clarification = message.clarification;
                            if (clarification != null) {
                              unawaited(
                                _confirmClarification(clarification, candidate),
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
          ),
          _Composer(
            controller: _messageController,
            focusNode: _focusNode,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _AssistantHeader extends StatelessWidget {
  final String branchName;
  final bool canManage;
  final VoidCallback onBack;
  final VoidCallback onNewConversation;
  final VoidCallback onDocuments;
  final VoidCallback onExport;
  final bool exportEnabled;
  final bool exporting;

  const _AssistantHeader({
    required this.branchName,
    required this.canManage,
    required this.onBack,
    required this.onNewConversation,
    required this.onDocuments,
    required this.onExport,
    required this.exportEnabled,
    required this.exporting,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Back to orders',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6D5DFB), Color(0xFF0EA5E9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6D5DFB).withValues(alpha: .25),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Insurance Knowledge Assistant',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$branchName • Clinical & coverage intelligence',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (canManage) ...[
            OutlinedButton.icon(
              onPressed: onDocuments,
              icon: const Icon(Icons.folder_copy_outlined),
              label: const Text('Knowledge Library'),
            ),
            const SizedBox(width: 10),
          ],
          OutlinedButton.icon(
            onPressed: exportEnabled && !exporting ? onExport : null,
            icon: exporting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(exporting ? 'Preparing…' : 'Export PDF'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onNewConversation,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5B55E7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            ),
            icon: const Icon(Icons.add_comment_rounded),
            label: const Text('New chat'),
          ),
        ],
      ),
    );
  }
}

class _SessionsPanel extends StatelessWidget {
  final List<InsuranceChatSession> sessions;
  final String? selectedId;
  final ValueChanged<InsuranceChatSession> onSelect;
  final VoidCallback onNew;

  const _SessionsPanel({
    required this.sessions,
    required this.selectedId,
    required this.onSelect,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDE7F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'RECENT CHATS',
                    style: TextStyle(
                      fontSize: 11.5,
                      letterSpacing: .8,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onNew,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  tooltip: 'New chat',
                ),
              ],
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Your evidence-backed conversations will appear here.',
                      style: TextStyle(color: Color(0xFF94A3B8), height: 1.45),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                    itemCount: sessions.length,
                    itemBuilder: (_, index) {
                      final session = sessions[index];
                      final selected = session.id == selectedId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: selected
                              ? const Color(0xFFEEF2FF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            selected: selected,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 5,
                            ),
                            leading: Icon(
                              selected
                                  ? Icons.chat_bubble_rounded
                                  : Icons.chat_bubble_outline_rounded,
                              size: 20,
                              color: selected
                                  ? const Color(0xFF5B55E7)
                                  : const Color(0xFF94A3B8),
                            ),
                            title: Text(
                              session.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFF4338CA)
                                    : const Color(0xFF1E293B),
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                DateFormat(
                                  'dd MMM · HH:mm',
                                ).format(session.updatedAt.toLocal()),
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            onTap: () => onSelect(session),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationStatus extends StatelessWidget {
  final String documentCountLabel;
  const _ConversationStatus({required this.documentCountLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8EEF5))),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            documentCountLabel,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          const Icon(Icons.shield_outlined, size: 17, color: Color(0xFF10B981)),
          const SizedBox(width: 6),
          const Text(
            'Private knowledge base',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeView extends StatelessWidget {
  final List<(String, String, IconData)> suggestions;
  final ValueChanged<String> onAsk;
  const _WelcomeView({required this.suggestions, required this.onAsk});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 36),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEEF2FF), Color(0xFFE0F2FE)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 42,
              color: Color(0xFF5B55E7),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ask. Verify. Dispense with confidence.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 670),
            child: const Text(
              'Search coverage rules, doses, age limits, required documents and prescriber criteria. Every answer stays linked to its exact source.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: suggestions
                .map(
                  (suggestion) => ActionChip(
                    avatar: Icon(
                      suggestion.$3,
                      size: 18,
                      color: const Color(0xFF5B55E7),
                    ),
                    label: Text(suggestion.$1),
                    side: const BorderSide(color: Color(0xFFD9E1F2)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    onPressed: () => onAsk(suggestion.$2),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 26),
          Container(
            constraints: const BoxConstraints(maxWidth: 700),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.fact_check_outlined, color: Color(0xFFD97706)),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'The assistant will say when evidence is insufficient. Always open the cited guideline before a final adjudication decision.',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final InsuranceChatMessage message;
  final InsuranceCitation? selectedCitation;
  final ValueChanged<InsuranceCitation> onCitationTap;
  final ValueChanged<int>? onFeedback;
  final bool clarificationEnabled;
  final ValueChanged<InsuranceClarificationCandidate> onClarificationSelected;

  const _MessageBubble({
    required this.message,
    required this.selectedCitation,
    required this.onCitationTap,
    required this.onFeedback,
    required this.clarificationEnabled,
    required this.onClarificationSelected,
  });

  List<InlineSpan> _answerSpans(String value, TextStyle style) {
    final spans = <InlineSpan>[];
    final bold = RegExp(r'\*\*(.+?)\*\*');
    var cursor = 0;
    for (final match in bold.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: style.copyWith(fontWeight: FontWeight.w900),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }

  ({String answer, String? source}) _separateAnswerAndSource() {
    final value = message.message.trim();
    final sourceMarker = RegExp(
      r'\n\s*Source\s*\n',
      caseSensitive: false,
    ).firstMatch(value);
    if (sourceMarker == null) return (answer: value, source: null);
    final answer = value.substring(0, sourceMarker.start).trim();
    final source = value.substring(sourceMarker.end).trim();
    return (answer: answer, source: source.isEmpty ? null : source);
  }

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    final content = _separateAnswerAndSource();
    final evidenceBacked =
        message.citations.isNotEmpty || content.source != null;
    final arabic = RegExp(r'[\u0600-\u06FF]').hasMatch(content.answer);
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: user ? 660 : 900),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: user
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!user) ...[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5B55E7), Color(0xFF3B82F6)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5B55E7).withValues(alpha: .22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Container(
                padding: EdgeInsets.all(user ? 17 : 18),
                decoration: BoxDecoration(
                  gradient: user
                      ? const LinearGradient(
                          colors: [Color(0xFF5B55E7), Color(0xFF3B82F6)],
                        )
                      : null,
                  color: user ? null : const Color(0xFFF5F7FF),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(user ? 18 : 7),
                    bottomRight: Radius.circular(user ? 5 : 18),
                  ),
                  border: user
                      ? null
                      : Border.all(color: const Color(0xFFD8E1FF)),
                  boxShadow: user
                      ? null
                      : [
                          BoxShadow(
                            color: const Color(
                              0xFF312E81,
                            ).withValues(alpha: .07),
                            blurRadius: 24,
                            offset: const Offset(0, 9),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!user) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E7FF),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: Color(0xFF4F46E5),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'ANSWER',
                                  style: TextStyle(
                                    color: Color(0xFF4338CA),
                                    fontSize: 11,
                                    letterSpacing: .7,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (evidenceBacked) const _EvidenceBadge(),
                        ],
                      ),
                      const SizedBox(height: 13),
                    ],
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(user ? 0 : 17),
                      decoration: user
                          ? null
                          : BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE1E7F5),
                              ),
                            ),
                      child: Directionality(
                        textDirection: arabic
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Text.rich(
                          TextSpan(
                            children: _answerSpans(
                              content.answer,
                              TextStyle(
                                color: user
                                    ? Colors.white
                                    : const Color(0xFF172033),
                                height: user ? 1.5 : 1.68,
                                fontSize: user ? 14.5 : 16,
                                fontWeight: user
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          style: TextStyle(
                            color: user
                                ? Colors.white
                                : const Color(0xFF172033),
                            height: user ? 1.5 : 1.68,
                            fontSize: user ? 14.5 : 16,
                            fontWeight: user
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    if (!user && message.clarification != null) ...[
                      const SizedBox(height: 13),
                      Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: message.clarification!.candidates
                            .map(
                              (candidate) => ActionChip(
                                avatar: const Icon(
                                  Icons.auto_fix_high_rounded,
                                  size: 17,
                                  color: Color(0xFF4F46E5),
                                ),
                                label: Text(
                                  candidate.canonicalName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF3730A3),
                                  ),
                                ),
                                backgroundColor: const Color(0xFFEEF2FF),
                                side: const BorderSide(
                                  color: Color(0xFFA5B4FC),
                                ),
                                onPressed: clarificationEnabled
                                    ? () => onClarificationSelected(candidate)
                                    : null,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (!user &&
                        message.citations.isEmpty &&
                        content.source != null) ...[
                      const SizedBox(height: 12),
                      _InlineSource(source: content.source!),
                    ],
                    if (!user && message.citations.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.menu_book_rounded,
                            size: 19,
                            color: Color(0xFF5B55E7),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            '${message.citations.length} supporting source${message.citations.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      ...message.citations
                          .take(3)
                          .map(
                            (citation) => Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => onCitationTap(citation),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        selectedCitation?.chunkId ==
                                            citation.chunkId
                                        ? const Color(0xFFEDE9FE)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          selectedCitation?.chunkId ==
                                              citation.chunkId
                                          ? const Color(0xFFA78BFA)
                                          : const Color(0xFFDCE5EF),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.picture_as_pdf_outlined,
                                        color: Color(0xFFEF4444),
                                        size: 19,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${citation.documentTitle} • ${citation.locationLabel}',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Color(0xFF334155),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ],
                    if (!user &&
                        !message.conversational &&
                        onFeedback != null) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Color(0xFFDDE5F3)),
                      Row(
                        children: [
                          const Text(
                            'Was this grounded answer useful?',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 5),
                          IconButton(
                            onPressed: () => onFeedback!(1),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.thumb_up_alt_outlined,
                              size: 16,
                            ),
                            tooltip: 'Useful',
                          ),
                          IconButton(
                            onPressed: () => onFeedback!(-1),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.thumb_down_alt_outlined,
                              size: 16,
                            ),
                            tooltip: 'Needs improvement',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineSource extends StatelessWidget {
  final String source;
  const _InlineSource({required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.menu_book_rounded,
            size: 19,
            color: Color(0xFF059669),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SOURCE',
                  style: TextStyle(
                    color: Color(0xFF047857),
                    fontSize: 10.5,
                    letterSpacing: .7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  source,
                  style: const TextStyle(
                    color: Color(0xFF166534),
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceBadge extends StatelessWidget {
  const _EvidenceBadge();
  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF059669);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'Evidence checked',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();
  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFFEEF2FF),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF5B55E7),
            size: 19,
          ),
        ),
        SizedBox(width: 10),
        _PulseDots(),
        SizedBox(width: 9),
        Text(
          'Searching policies and verifying evidence...',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _PulseDots extends StatelessWidget {
  const _PulseDots();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: CircularProgressIndicator(
      strokeWidth: 2.4,
      color: Color(0xFF6D5DFB),
    ),
  );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 17),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EEF5))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (!sending) onSend();
                    },
                    const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
                      if (!sending) onSend();
                    },
                  },
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    onSubmitted: (_) {
                      if (!sending) onSend();
                    },
                    decoration: InputDecoration(
                      hintText:
                          'Ask about coverage, dose, age, approval or documentation... / اسأل عن شروط الصرف',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF64748B),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFDCE5EF)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFDCE5EF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFF6D5DFB),
                          width: 1.6,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 50,
                height: 50,
                child: FilledButton(
                  onPressed: sending ? null : onSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5B55E7),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: sending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Answers are restricted to approved documents. Review the cited source before dispensing.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  final InsuranceCitation? citation;
  final ValueChanged<InsuranceCitation> onOpen;
  const _EvidencePanel({required this.citation, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDE7F1)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: citation == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fact_check_outlined,
                        size: 46,
                        color: Color(0xFFCBD5E1),
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Evidence preview',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF475569),
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'Select a cited source to inspect the exact excerpt and location.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF172554), Color(0xFF312E81)],
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.fact_check_rounded,
                          color: Color(0xFFA5B4FC),
                        ),
                        SizedBox(width: 9),
                        Text(
                          'VERIFIED EVIDENCE',
                          style: TextStyle(
                            color: Colors.white,
                            letterSpacing: .7,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      citation!.documentTitle,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      citation!.locationLabel,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF5B55E7),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (citation!.sectionTitle?.trim().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 17),
                            const Text(
                              'SECTION',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: .8,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              citation!.sectionTitle!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 19),
                          const Text(
                            'SOURCE EXCERPT',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: .8,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              citation!.excerpt,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF334155),
                                height: 1.55,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => onOpen(citation!),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF5B55E7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                              ),
                              label: const Text('Open original document'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 15,
                                color: Color(0xFF94A3B8),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Private signed link • expires in 5 minutes',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xFFFFF7ED),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    child: Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: Color(0xFFEA580C),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF9A3412),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _DocumentCenterDialog extends StatefulWidget {
  final InsuranceAssistantRepository repository;
  const _DocumentCenterDialog({required this.repository});
  @override
  State<_DocumentCenterDialog> createState() => _DocumentCenterDialogState();
}

class _DocumentCenterDialogState extends State<_DocumentCenterDialog> {
  List<InsuranceDocumentSummary> _documents = const [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final documents = await widget.repository.fetchDocuments();
      if (mounted)
        setState(() {
          _documents = documents;
          _loading = false;
          _error = null;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = error.toString();
        });
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'xlsx'],
      withData: true,
    );
    if (picked == null ||
        picked.files.isEmpty ||
        picked.files.single.bytes == null)
      return;
    final file = picked.files.single;
    if (!mounted) return;
    final controller = TextEditingController(
      text: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    );
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Document title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Knowledge base title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await widget.repository.uploadDocument(
        bytes: file.bytes!,
        fileName: file.name,
        title: title,
      );
      await _load();
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openSearchInspector() async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> rows = const [];
    bool loading = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.manage_search_rounded),
              SizedBox(width: 10),
              Text('Search Inspector'),
            ],
          ),
          content: SizedBox(
            width: 900,
            height: 560,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  onSubmitted: (_) async {
                    if (controller.text.trim().isEmpty) return;
                    setDialogState(() {
                      loading = true;
                      error = null;
                    });
                    try {
                      rows = await widget.repository.inspectSearch(
                        controller.text.trim(),
                      );
                    } catch (value) {
                      error = value.toString();
                    }
                    setDialogState(() => loading = false);
                  },
                  decoration: InputDecoration(
                    hintText:
                        'Enter the exact user question to inspect retrieval…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: () async {
                        if (controller.text.trim().isEmpty) return;
                        setDialogState(() {
                          loading = true;
                          error = null;
                        });
                        try {
                          rows = await widget.repository.inspectSearch(
                            controller.text.trim(),
                          );
                        } catch (value) {
                          error = value.toString();
                        }
                        setDialogState(() => loading = false);
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                if (loading) const LinearProgressIndicator(),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      final accepted = row['accepted'] == true;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accepted
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accepted
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFFCA5A5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${row['rank']}  ${row['document_title']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${accepted ? 'ACCEPTED' : 'REJECTED'} · ${row['acceptance_reason']} · score ${((row['combined_score'] as num?) ?? 0).toStringAsFixed(3)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: accepted
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB91C1C),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              row['matched_content']?.toString() ?? '',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _openSourceInspector(InsuranceDocumentSummary document) async {
    final rows = await widget.repository.inspectSource(document.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Source Inspector · ${document.title}'),
        content: SizedBox(
          width: 920,
          height: 600,
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, index) {
              final row = rows[index];
              final location = row['page_from'] != null
                  ? 'Page ${row['page_from']}'
                  : 'Sheet ${row['sheet_name']} · row ${row['row_from']}';
              return ListTile(
                title: Text(
                  'Chunk ${row['chunk_index']} · $location',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${row['section_title'] ?? 'Root'} · ${row['topic_normalized']}\n${row['content_text']}',
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        height: 650,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF172554), Color(0xFF312E81)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_copy_rounded,
                    color: Color(0xFFA5B4FC),
                    size: 29,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Insurance Knowledge Library',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Private originals, extraction status and version history',
                          style: TextStyle(
                            color: Color(0xFFC7D2FE),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openSearchInspector,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('Search inspector'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Upload document'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFEF2F2),
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _documents.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.library_books_outlined,
                            size: 58,
                            color: Color(0xFFCBD5E1),
                          ),
                          SizedBox(height: 14),
                          Text(
                            'No documents yet',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Upload PDF, DOCX or XLSX guidelines to begin.',
                            style: TextStyle(color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(18),
                      itemCount: _documents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (_, index) {
                        final document = _documents[index];
                        return _DocumentTile(
                          document: document,
                          onInspect: () => _openSourceInspector(document),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final InsuranceDocumentSummary document;
  final VoidCallback onInspect;
  const _DocumentTile({required this.document, required this.onInspect});
  @override
  Widget build(BuildContext context) {
    final colors = switch (document.status) {
      'ready' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'failed' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _ => (const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Inspect extracted source',
            onPressed: onInspect,
            icon: const Icon(Icons.fact_check_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${document.fileName} • ${(document.fileSize / 1048576).toStringAsFixed(1)} MB • ${DateFormat('dd MMM yyyy').format(document.uploadedAt)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${document.chunkCount} chunks • ${document.embeddedCount} embedded • ${document.entityCount} entities • ${document.validationStatus}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: document.validationStatus == 'verified'
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB45309),
                  ),
                ),
                if (document.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      document.error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.$1,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              document.status.toUpperCase(),
              style: TextStyle(
                color: colors.$2,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
