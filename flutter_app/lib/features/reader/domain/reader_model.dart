class ReaderModel {
  ReaderModel({
    required this.bookId,
    required this.title,
    required this.language,
    required this.sections,
  });

  factory ReaderModel.fromJson(Map<String, dynamic> json) {
    return ReaderModel(
      bookId: json['book_id'] as String,
      title: json['title'] as String,
      language: json['language'] as String?,
      sections: (json['sections'] as List<dynamic>)
          .map(
            (section) =>
                ReaderSection.fromJson(section as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final String bookId;
  final String title;
  final String? language;
  final List<ReaderSection> sections;

  Map<String, dynamic> toJson() {
    return {
      'book_id': bookId,
      'title': title,
      'language': language,
      'sections': sections.map((section) => section.toJson()).toList(),
    };
  }
}

class ReaderSection {
  ReaderSection({
    required this.id,
    required this.title,
    required this.order,
    required this.paragraphs,
  });

  factory ReaderSection.fromJson(Map<String, dynamic> json) {
    return ReaderSection(
      id: json['id'] as String,
      title: json['title'] as String?,
      order: json['order'] as int,
      paragraphs: (json['paragraphs'] as List<dynamic>)
          .map(
            (paragraph) =>
                ReaderParagraph.fromJson(paragraph as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String? title;
  final int order;
  final List<ReaderParagraph> paragraphs;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'order': order,
      'paragraphs': paragraphs.map((paragraph) => paragraph.toJson()).toList(),
    };
  }
}

class ReaderParagraph {
  ReaderParagraph({required this.index, required this.tokens});

  factory ReaderParagraph.fromJson(Map<String, dynamic> json) {
    return ReaderParagraph(
      index: json['index'] as int,
      tokens: (json['tokens'] as List<dynamic>)
          .map((token) => ReaderToken.fromJson(token as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final int index;
  final List<ReaderToken> tokens;

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'tokens': tokens.map((token) => token.toJson()).toList(),
    };
  }
}

class ReaderToken {
  ReaderToken({
    required this.index,
    required this.text,
    required this.normalized,
    this.cfi,
  });

  factory ReaderToken.fromJson(Map<String, dynamic> json) {
    return ReaderToken(
      index: json['index'] as int,
      text: json['text'] as String,
      normalized: json['normalized'] as String,
      cfi: json['cfi'] as String?,
    );
  }

  final int index;
  final String text;
  final String normalized;
  final String? cfi;

  Map<String, dynamic> toJson() {
    return {'index': index, 'text': text, 'normalized': normalized, 'cfi': cfi};
  }
}
