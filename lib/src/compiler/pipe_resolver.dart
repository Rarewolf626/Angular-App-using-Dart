import "package:angular2/src/core/di.dart" show Injectable;
import "package:angular2/src/core/metadata.dart" show PipeMetadata;
import "package:angular2/src/core/reflection/reflection.dart" show reflector;
import "package:angular2/src/core/reflection/reflector_reader.dart"
    show ReflectorReader;
import "package:angular2/src/facade/exceptions.dart" show BaseException;

/// Resolve a type for [PipeMetadata].
///
/// Application developer can inject a new implementation to customize
/// strategy to resolve Types from metadata.
///
/// See [Compiler]
@Injectable()
class PipeResolver {
  ReflectorReader _reflector;
  PipeResolver([ReflectorReader _reflector]) {
    this._reflector = _reflector ?? reflector;
  }

  /// Return [PipeMetadata] for a given [Type].
  PipeMetadata resolve(Type type) {
    var metas = this._reflector.annotations(type);
    if (metas != null) {
      var annotation = metas.firstWhere(_isPipeMetadata, orElse: () => null);
      if (annotation != null) {
        return annotation;
      }
    }
    throw new BaseException('No Pipe decorator found on $type');
  }
}

bool _isPipeMetadata(dynamic type) {
  return type is PipeMetadata;
}
