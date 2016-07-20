library angular2.src.core.di.reflective_provider;

import "package:angular2/src/core/reflection/reflection.dart" show reflector;
import "package:angular2/src/facade/collection.dart"
    show MapWrapper, ListWrapper, StringMapWrapper;
import "package:angular2/src/facade/lang.dart"
    show Type, isBlank, isPresent, isArray, isType;

import "../metadata/di.dart"
    show InjectorModuleMetadata, ProviderPropertyMetadata;
import "forward_ref.dart" show resolveForwardRef;
import "metadata.dart"
    show
        InjectMetadata,
        OptionalMetadata,
        SelfMetadata,
        HostMetadata,
        SkipSelfMetadata,
        DependencyMetadata;
import "provider.dart" show Provider, ProviderBuilder, provide, noValueProvided;
import "reflective_exceptions.dart"
    show
        NoAnnotationError,
        MixingMultiProvidersWithRegularProvidersError,
        InvalidProviderError;
import "reflective_key.dart" show ReflectiveKey;


/// `Dependency` is used by the framework to extend DI.
/// This is internal to Angular and should not be used directly.
class ReflectiveDependency {
  ReflectiveKey key;
  bool optional;
  dynamic lowerBoundVisibility;
  dynamic upperBoundVisibility;
  List<dynamic> properties;
  ReflectiveDependency(this.key, this.optional, this.lowerBoundVisibility,
      this.upperBoundVisibility, this.properties) {}
  static ReflectiveDependency fromKey(ReflectiveKey key) {
    return new ReflectiveDependency(key, false, null, null, []);
  }
}

_identityPostProcess(obj) {
  return obj;
}

/// An internal resolved representation of a [Provider] used by the [Injector].
///
/// It is usually created automatically by `Injector.resolveAndCreate`.
///
/// It can be created manually, as follows:
///
/// Example:
///
///     var resolvedProviders = Injector.resolve([provide('message', useValue: 'Hello')]);
///     var injector = Injector.fromResolvedProviders(resolvedProviders);
///     expect(injector.get('message')).toEqual('Hello');
///
abstract class ResolvedReflectiveProvider {

  /// A key, usually a [Type].
  ReflectiveKey key;

  /// Return instances of objects for the given [key].
  List<ResolvedReflectiveFactory> resolvedFactories;

  /// Indicates if the provider is a multi-provider or a regular provider.
  bool multiProvider;
}


/// See [ResolvedProvider] instead.
abstract class ResolvedReflectiveBinding implements ResolvedReflectiveProvider {
}

class ResolvedReflectiveProvider_ implements ResolvedReflectiveBinding {
  ReflectiveKey key;
  List<ResolvedReflectiveFactory> resolvedFactories;
  bool multiProvider;
  ResolvedReflectiveProvider_(
      this.key, this.resolvedFactories, this.multiProvider) {}
  ResolvedReflectiveFactory get resolvedFactory {
    return this.resolvedFactories[0];
  }
}


/// An internal resolved representation of a factory function created by
/// resolving [Provider].
class ResolvedReflectiveFactory {
  Function factory;
  List<ReflectiveDependency> dependencies;
  Function postProcess;

  /// Constructs a resolved factory.
  ///
  /// [factory] returns an instance of an object represented by a key.
  ///
  /// [dependencies] is a list of dependencies passed to [factory] as
  /// parameters.
  ///
  /// [postProcess] function is applied to the value constructed by [factory].
  ResolvedReflectiveFactory(this.factory, this.dependencies, this.postProcess);
}


/// Resolve a single provider.
ResolvedReflectiveFactory resolveReflectiveFactory(Provider provider) {
  Function factoryFn;
  List<ReflectiveDependency> resolvedDeps;
  if (provider.useExisting != null) {
    factoryFn = (aliasInstance) => aliasInstance;
    resolvedDeps = [
      ReflectiveDependency.fromKey(ReflectiveKey.get(provider.useExisting))
    ];
  } else if (provider.useFactory != null) {
    factoryFn = provider.useFactory;
    resolvedDeps =
        constructDependencies(provider.useFactory, provider.dependencies);
  } else if (provider.useClass != null) {
    var useClass = resolveForwardRef(provider.useClass);
    factoryFn = reflector.factory(useClass);
    resolvedDeps = _dependenciesFor(useClass);
  } else if (provider.useValue != noValueProvided) {
    factoryFn = () => provider.useValue;
    resolvedDeps = const <ReflectiveDependency>[];
  } else if (provider.token is Type) {
    var useClass = resolveForwardRef(provider.token);
    factoryFn = reflector.factory(useClass);
    resolvedDeps = _dependenciesFor(useClass);
  } else {
    throw new InvalidProviderError.withCustomMessage(provider,
        'token is not a Type and no factory was specified');
  }

  var postProcess = isPresent(provider.useProperty)
      ? reflector.getter(provider.useProperty)
      : _identityPostProcess;
  return new ResolvedReflectiveFactory(factoryFn, resolvedDeps, postProcess);
}


/// Converts the [Provider] into [ResolvedProvider].
///
/// [Injector] internally only uses [ResolvedProvider], [Provider] contains
/// convenience provider syntax.
ResolvedReflectiveProvider resolveReflectiveProvider(Provider provider) {
  return new ResolvedReflectiveProvider_(ReflectiveKey.get(provider.token),
      [resolveReflectiveFactory(provider)], provider.multi);
}


/// Resolve a list of Providers.
List<ResolvedReflectiveProvider> resolveReflectiveProviders(
    List<dynamic /* Type | Provider | List < dynamic > */ > providers) {
  var normalized = _normalizeProviders(providers, []);
  var resolved = normalized.map(resolveReflectiveProvider).toList();
  return MapWrapper.values(mergeResolvedReflectiveProviders(
      resolved, new Map<num, ResolvedReflectiveProvider>()));
}


/// Merges a list of ResolvedProviders into a list where
/// each key is contained exactly once and multi providers
/// have been merged.
Map<num, ResolvedReflectiveProvider> mergeResolvedReflectiveProviders(
    List<ResolvedReflectiveProvider> providers,
    Map<num, ResolvedReflectiveProvider> normalizedProvidersMap) {
  for (var i = 0; i < providers.length; i++) {
    var provider = providers[i];
    var existing = normalizedProvidersMap[provider.key.id];
    if (isPresent(existing)) {
      if (!identical(provider.multiProvider, existing.multiProvider)) {
        throw new MixingMultiProvidersWithRegularProvidersError(
            existing, provider);
      }
      if (provider.multiProvider) {
        for (var j = 0; j < provider.resolvedFactories.length; j++) {
          existing.resolvedFactories.add(provider.resolvedFactories[j]);
        }
      } else {
        normalizedProvidersMap[provider.key.id] = provider;
      }
    } else {
      var resolvedProvider;
      if (provider.multiProvider) {
        resolvedProvider = new ResolvedReflectiveProvider_(
            provider.key,
            ListWrapper.clone(provider.resolvedFactories),
            provider.multiProvider);
      } else {
        resolvedProvider = provider;
      }
      normalizedProvidersMap[provider.key.id] = resolvedProvider;
    }
  }
  return normalizedProvidersMap;
}

List<Provider> _normalizeProviders(
    List<
        dynamic /* Type | Provider | ProviderBuilder | List < dynamic > */ > providers,
    List<Provider> res) {
  providers.forEach((b) {
    if (b is Type) {
      res.add(provide(b, useClass: b));
      _normalizeProviders(getInjectorModuleProviders(b), res);
    } else if (b is Provider) {
      res.add(b);
      _normalizeProviders(getInjectorModuleProviders(b.token), res);
    } else if (b is List) {
      _normalizeProviders(b, res);
    } else if (b is ProviderBuilder) {
      throw new InvalidProviderError(b.token);
    } else {
      throw new InvalidProviderError(b);
    }
  });
  return res;
}

List<ReflectiveDependency> constructDependencies(
    dynamic typeOrFunc, List<dynamic> dependencies) {
  if (isBlank(dependencies)) {
    return _dependenciesFor(typeOrFunc);
  } else {
    List<List<dynamic>> params = dependencies.map((t) => [t]).toList();
    return dependencies
        .map((t) => _extractToken(typeOrFunc, t, params))
        .toList();
  }
}

List<ReflectiveDependency> _dependenciesFor(dynamic typeOrFunc) {
  var params = reflector.parameters(typeOrFunc);
  if (isBlank(params)) return [];
  if (params.any(isBlank)) {
    throw new NoAnnotationError(typeOrFunc, params);
  }
  return params
      .map((List<dynamic> p) => _extractToken(typeOrFunc, p, params))
      .toList();
}

ReflectiveDependency _extractToken(
    typeOrFunc, metadata, List<List<dynamic>> params) {
  var depProps = [];
  var token = null;
  var optional = false;
  if (!isArray(metadata)) {
    if (metadata is InjectMetadata) {
      return _createDependency(metadata.token, optional, null, null, depProps);
    } else {
      return _createDependency(metadata, optional, null, null, depProps);
    }
  }
  var lowerBoundVisibility = null;
  var upperBoundVisibility = null;
  for (var i = 0; i < metadata.length; ++i) {
    var paramMetadata = metadata[i];
    if (paramMetadata is Type) {
      token = paramMetadata;
    } else if (paramMetadata is InjectMetadata) {
      token = paramMetadata.token;
    } else if (paramMetadata is OptionalMetadata) {
      optional = true;
    } else if (paramMetadata is SelfMetadata) {
      upperBoundVisibility = paramMetadata;
    } else if (paramMetadata is HostMetadata) {
      upperBoundVisibility = paramMetadata;
    } else if (paramMetadata is SkipSelfMetadata) {
      lowerBoundVisibility = paramMetadata;
    } else if (paramMetadata is DependencyMetadata) {
      if (isPresent(paramMetadata.token)) {
        token = paramMetadata.token;
      }
      depProps.add(paramMetadata);
    }
  }
  token = resolveForwardRef(token);
  if (isPresent(token)) {
    return _createDependency(
        token, optional, lowerBoundVisibility, upperBoundVisibility, depProps);
  } else {
    throw new NoAnnotationError(typeOrFunc, params);
  }
}

ReflectiveDependency _createDependency(
    token, optional, lowerBoundVisibility, upperBoundVisibility, depProps) {
  return new ReflectiveDependency(ReflectiveKey.get(token), optional,
      lowerBoundVisibility, upperBoundVisibility, depProps);
}


/// Retruns [InjectorModuleMetadata] providers for a given token if possible.
List<dynamic> getInjectorModuleProviders(dynamic token) {
  var providers = [];
  List<dynamic> annotations = null;
  try {
    if (isType(token)) {
      annotations = reflector.annotations(resolveForwardRef(token));
    }
  } catch (e) {}
  InjectorModuleMetadata metadata = isPresent(annotations)
      ? annotations.firstWhere((type) => type is InjectorModuleMetadata,
          orElse: () => null)
      : null;
  if (isPresent(metadata)) {
    var propertyMetadata = reflector.propMetadata(token);
    ListWrapper.addAll(providers, metadata.providers);
    StringMapWrapper.forEach(propertyMetadata,
        (List<dynamic> metadata, String propName) {
      metadata.forEach((a) {
        if (a is ProviderPropertyMetadata) {
          providers.add(new Provider(a.token,
              multi: a.multi, useProperty: propName, useExisting: token));
        }
      });
    });
  }
  return providers;
}
