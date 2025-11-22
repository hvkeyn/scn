/// File information model
class FileInfo {
  final String id;
  final String fileName;
  final int size;
  final String? mimeType;
  final FileType fileType;
  final DateTime? lastModified;
  
  FileInfo({
    required this.id,
    required this.fileName,
    required this.size,
    this.mimeType,
    required this.fileType,
    this.lastModified,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'size': size,
    'mimeType': mimeType,
    'fileType': fileType.name,
    'lastModified': lastModified?.toIso8601String(),
  };
  
  factory FileInfo.fromJson(Map<String, dynamic> json) => FileInfo(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    size: json['size'] as int,
    mimeType: json['mimeType'] as String?,
    fileType: FileType.values.firstWhere(
      (e) => e.name == json['fileType'],
      orElse: () => FileType.other,
    ),
    lastModified: json['lastModified'] != null 
      ? DateTime.parse(json['lastModified'] as String)
      : null,
  );
}

enum FileType {
  image,
  video,
  audio,
  text,
  other,
}

