import 'package:equatable/equatable.dart';

class InsuranceCitation extends Equatable {
  final String evidenceId;
  final String chunkId;
  final String? documentId;
  final String documentTitle;
  final String fileName;
  final String storageBucket;
  final String storagePath;
  final String excerpt;
  final String? sectionTitle;
  final int? pageFrom;
  final int? pageTo;
  final String? sheetName;
  final int? rowFrom;
  final int? rowTo;
  final double score;
  final String supportLevel;

  const InsuranceCitation({
    this.evidenceId = '',
    required this.chunkId,
    required this.documentTitle,
    required this.fileName,
    required this.storageBucket,
    required this.storagePath,
    required this.excerpt,
    this.documentId,
    this.sectionTitle,
    this.pageFrom,
    this.pageTo,
    this.sheetName,
    this.rowFrom,
    this.rowTo,
    this.score = 0,
    this.supportLevel = 'supporting_evidence',
  });

  String get locationLabel {
    if (pageFrom != null) {
      return pageTo != null && pageTo != pageFrom
          ? 'Pages $pageFrom-$pageTo'
          : 'Page $pageFrom';
    }
    if (sheetName != null) {
      final rows = rowFrom == null
          ? ''
          : rowTo != null && rowTo != rowFrom
          ? ' • Rows $rowFrom-$rowTo'
          : ' • Row $rowFrom';
      return 'Sheet: $sheetName$rows';
    }
    return sectionTitle?.trim().isNotEmpty == true
        ? sectionTitle!
        : 'Source document';
  }

  String get resolvedEvidenceId => evidenceId.isEmpty ? chunkId : evidenceId;

  @override
  List<Object?> get props => [
    evidenceId,
    chunkId,
    documentId,
    storagePath,
    excerpt,
    pageFrom,
    rowFrom,
  ];
}

class InsuranceAnswerCriterion extends Equatable {
  final String label;
  final String status;
  final String? detail;
  final List<String> evidenceIds;

  const InsuranceAnswerCriterion({
    required this.label,
    required this.status,
    this.detail,
    this.evidenceIds = const [],
  });

  @override
  List<Object?> get props => [label, status, detail, evidenceIds];
}

class InsuranceDoseSchedule extends Equatable {
  final String? dose;
  final String? route;
  final String? frequency;
  final String? loading;
  final String? maintenance;
  final List<String> evidenceIds;

  const InsuranceDoseSchedule({
    this.dose,
    this.route,
    this.frequency,
    this.loading,
    this.maintenance,
    this.evidenceIds = const [],
  });

  bool get isEmpty =>
      dose == null &&
      route == null &&
      frequency == null &&
      loading == null &&
      maintenance == null;

  @override
  List<Object?> get props => [
    dose,
    route,
    frequency,
    loading,
    maintenance,
    evidenceIds,
  ];
}

class InsuranceAnswerClaim extends Equatable {
  final String id;
  final String text;
  final String? subjectEntityId;
  final String? predicate;
  final String? value;
  final String? unit;
  final String polarity;
  final String certainty;
  final List<String> evidenceIds;
  final String? evidenceQuote;

  const InsuranceAnswerClaim({
    required this.id,
    required this.text,
    this.subjectEntityId,
    this.predicate,
    this.value,
    this.unit,
    this.polarity = 'affirmed',
    this.certainty = 'direct',
    this.evidenceIds = const [],
    this.evidenceQuote,
  });

  @override
  List<Object?> get props => [
    id,
    text,
    subjectEntityId,
    predicate,
    value,
    unit,
    polarity,
    certainty,
    evidenceIds,
    evidenceQuote,
  ];
}

class InsurancePresentationRow extends Equatable {
  final String label;
  final String status;
  final String value;
  final List<String> evidenceIds;

  const InsurancePresentationRow({
    required this.label,
    required this.status,
    required this.value,
    this.evidenceIds = const [],
  });

  @override
  List<Object?> get props => [label, status, value, evidenceIds];
}

class InsurancePresentationSection extends Equatable {
  final String id;
  final String title;
  final List<InsurancePresentationRow> rows;

  const InsurancePresentationSection({
    required this.id,
    required this.title,
    this.rows = const [],
  });

  @override
  List<Object?> get props => [id, title, rows];
}

class InsuranceAnswerPresentation extends Equatable {
  final String answerType;
  final String displayTitle;
  final String displayVerdict;
  final String tone;
  final bool complete;
  final String? explanation;
  final List<InsurancePresentationRow> comparisonRows;
  final List<InsurancePresentationSection> sections;
  final List<String> missingInformation;
  final String? nextAction;
  final int evidenceSourceCount;
  final List<String> displayedEvidenceIds;

  const InsuranceAnswerPresentation({
    required this.answerType,
    required this.displayTitle,
    required this.displayVerdict,
    this.tone = 'informational',
    this.complete = false,
    this.explanation,
    this.comparisonRows = const [],
    this.sections = const [],
    this.missingInformation = const [],
    this.nextAction,
    this.evidenceSourceCount = 0,
    this.displayedEvidenceIds = const [],
  });

  @override
  List<Object?> get props => [
    answerType,
    displayTitle,
    displayVerdict,
    tone,
    complete,
    explanation,
    comparisonRows,
    sections,
    missingInformation,
    nextAction,
    evidenceSourceCount,
    displayedEvidenceIds,
  ];
}

class InsuranceAnswerCard extends Equatable {
  final String version;
  final String verdict;
  final String summary;
  final List<InsuranceAnswerCriterion> criteria;
  final InsuranceDoseSchedule? doseSchedule;
  final List<String> missingInformation;
  final String? nextAction;
  final List<InsuranceAnswerClaim> claims;
  final InsuranceAnswerPresentation? presentation;

  const InsuranceAnswerCard({
    required this.version,
    required this.verdict,
    required this.summary,
    this.criteria = const [],
    this.doseSchedule,
    this.missingInformation = const [],
    this.nextAction,
    this.claims = const [],
    this.presentation,
  });

  bool get hasStructuredDetails =>
      criteria.isNotEmpty ||
      doseSchedule?.isEmpty == false ||
      missingInformation.isNotEmpty ||
      nextAction?.trim().isNotEmpty == true ||
      claims.isNotEmpty;

  @override
  List<Object?> get props => [
    version,
    verdict,
    summary,
    criteria,
    doseSchedule,
    missingInformation,
    nextAction,
    claims,
    presentation,
  ];
}

class InsuranceClarificationCandidate extends Equatable {
  final String id;
  final String canonicalName;
  final String entityType;
  final String queryFragment;
  final double similarity;

  const InsuranceClarificationCandidate({
    required this.id,
    required this.canonicalName,
    required this.entityType,
    required this.queryFragment,
    required this.similarity,
  });

  @override
  List<Object?> get props => [id, canonicalName, entityType, queryFragment];
}

class InsuranceClarification extends Equatable {
  final String id;
  final List<InsuranceClarificationCandidate> candidates;

  const InsuranceClarification({required this.id, required this.candidates});

  @override
  List<Object?> get props => [id, candidates];
}

class InsuranceChatMessage extends Equatable {
  final String id;
  final String role;
  final String message;
  final DateTime createdAt;
  final double? confidence;
  final List<InsuranceCitation> citations;
  final bool conversational;
  final bool aiGenerated;
  final InsuranceClarification? clarification;
  final Map<String, dynamic>? debugTrace;
  final int recoveryDepth;
  final String? recoveryOfMessageId;
  final String answerStatus;
  final bool evidenceChecked;
  final String? answerGenerator;
  final InsuranceAnswerCard? answerCard;

  const InsuranceChatMessage({
    required this.id,
    required this.role,
    required this.message,
    required this.createdAt,
    this.confidence,
    this.citations = const [],
    this.conversational = false,
    this.aiGenerated = false,
    this.clarification,
    this.debugTrace,
    this.recoveryDepth = 0,
    this.recoveryOfMessageId,
    this.answerStatus = 'legacy',
    this.evidenceChecked = false,
    this.answerGenerator,
    this.answerCard,
  });

  bool get isUser => role == 'user';

  bool get hasVerifiedEvidence {
    const nonEvidenceStatuses = {
      'blocked',
      'clarification_required',
      'insufficient_evidence',
      'internal_error',
      'no_evidence',
      'provider_unavailable',
      'unsafe',
    };
    return evidenceChecked &&
        citations.isNotEmpty &&
        !nonEvidenceStatuses.contains(answerStatus);
  }

  @override
  List<Object?> get props => [
    id,
    role,
    message,
    createdAt,
    citations,
    conversational,
    aiGenerated,
    clarification,
    debugTrace,
    recoveryDepth,
    recoveryOfMessageId,
    answerStatus,
    evidenceChecked,
    answerGenerator,
    answerCard,
  ];
}

class InsuranceChatSession extends Equatable {
  final String id;
  final String title;
  final DateTime updatedAt;

  const InsuranceChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, title, updatedAt];
}

class InsuranceDocumentSummary extends Equatable {
  final String id;
  final String title;
  final String fileName;
  final String status;
  final String? error;
  final int fileSize;
  final DateTime uploadedAt;
  final String validationStatus;
  final String lifecycleStatus;
  final int chunkCount;
  final int embeddedCount;
  final int entityCount;

  const InsuranceDocumentSummary({
    required this.id,
    required this.title,
    required this.fileName,
    required this.status,
    required this.fileSize,
    required this.uploadedAt,
    this.validationStatus = 'pending',
    this.lifecycleStatus = 'current',
    this.chunkCount = 0,
    this.embeddedCount = 0,
    this.entityCount = 0,
    this.error,
  });

  @override
  List<Object?> get props => [
    id,
    status,
    validationStatus,
    chunkCount,
    uploadedAt,
  ];
}
