// ─── Slot Model ──────────────────────────────────────────────────────────────

class SlotModel {
  final String id;
  final double left, top, width, height;
  final String type;
  final String? localPath;

  const SlotModel({
    required this.id,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.type,
    this.localPath,
  });

  factory SlotModel.fromMap(Map<String, dynamic> map) {
    return SlotModel(
      id: map['id'] as String? ?? '',
      left: (map['left'] ?? 0.0).toDouble(),
      top: (map['top'] ?? 0.0).toDouble(),
      width: (map['width'] ?? 1.0).toDouble(),
      height: (map['height'] ?? 1.0).toDouble(),
      type: map['type'] as String? ?? 'image',
      localPath: map['localPath'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    'type': type,
    'localPath': localPath,
  };

  SlotModel copyWith({
    String? id,
    double? left,
    double? top,
    double? width,
    double? height,
    String? type,
    String? localPath,
  }) {
    return SlotModel(
      id: id ?? this.id,
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
    );
  }
}

// ─── Template Model ──────────────────────────────────────────────────────────

class TemplateModel {
  final String id;
  final String name;
  final String thumbnail;
  final double aspectRatio;
  final List<SlotModel> slots;

  const TemplateModel({
    required this.id,
    required this.name,
    required this.thumbnail,
    required this.aspectRatio,
    required this.slots,
  });

  factory TemplateModel.fromMap(Map<String, dynamic> map) {
    return TemplateModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      thumbnail: map['thumbnail'] as String? ?? '',
      aspectRatio: (map['aspectRatio'] ?? (9.0 / 16.0)).toDouble(),
      slots: (map['slots'] as List<dynamic>? ?? [])
          .map((x) => SlotModel.fromMap(x as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'thumbnail': thumbnail,
    'aspectRatio': aspectRatio,
    'slots': slots.map((s) => s.toMap()).toList(),
  };

  TemplateModel copyWith({
    String? id,
    String? name,
    String? thumbnail,
    double? aspectRatio,
    List<SlotModel>? slots,
  }) {
    return TemplateModel(
      id: id ?? this.id,
      name: name ?? this.name,
      thumbnail: thumbnail ?? this.thumbnail,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      slots: slots ?? this.slots,
    );
  }
}

// ─── Home Screen Models ──────────────────────────────────────────────────────

class PromoBanner {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String tag;
  final String actionText;

  const PromoBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.tag,
    required this.actionText,
  });

  factory PromoBanner.fromMap(Map<String, dynamic> map) {
    return PromoBanner(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      tag: map['tag'] ?? '',
      actionText: map['actionText'] ?? '',
    );
  }
}

class DesignTemplate {
  final String id;
  final String title;
  final String category;
  final String imageUrl;
  final String duration;
  final int likes;
  final double rating;
  final bool isFavorite;
  final String author;

  const DesignTemplate({
    required this.id,
    required this.title,
    required this.category,
    required this.imageUrl,
    required this.duration,
    required this.likes,
    required this.rating,
    required this.isFavorite,
    required this.author,
  });

  factory DesignTemplate.fromMap(Map<String, dynamic> map) {
    return DesignTemplate(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      category: map['category'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      duration: map['duration'] ?? '0:00',
      likes: map['likes'] ?? 0,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      isFavorite: map['isFavorite'] ?? false,
      author: map['author'] ?? 'Unknown',
    );
  }
}
